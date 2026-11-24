--[[---------------------------------------------------------------------------
    Greyline :: Biolock -- server authority
    File: lua/autorun/server/greyline_biolock_server.lua

    ALL permission checks, state changes and persistence live here. The client
    never sends a message that can unlock a door.
---------------------------------------------------------------------------]]

-- Make sure every client-side file is shipped, even on addons that disable
-- automatic Lua sending.
AddCSLuaFile("autorun/greyline_biolock_config.lua")
AddCSLuaFile("autorun/client/greyline_biolock_hud.lua")
AddCSLuaFile("entities/greyline_biolock/shared.lua")
AddCSLuaFile("entities/greyline_biolock/cl_init.lua")
AddCSLuaFile("weapons/greyline_biolock_tool/shared.lua")

local Biolock = Greyline.Biolock
local STATE  = Biolock.Config.State
local PERSIST_FILE = "greyline_biolocks.json"

-- door EntIndex -> biolock entity. Rebuilt on map change.
Biolock.ByDoor = Biolock.ByDoor or {}

-- A double door is two separate door entities. One scanner covers both leaves;
-- the bare leaf keeps only a back-reference to the real lock.
local function modelYaw()
    if isfunction(Biolock.GetModelAngleOffset) then return Biolock.GetModelAngleOffset().y end
    return isangle(Biolock.Config.ModelAngleOffset) and Biolock.Config.ModelAngleOffset.y or -90
end

local function outwardFromFacing(facing)
    return Angle(0, (facing and facing.y or 0) - modelYaw(), 0):Forward()
end

local function sameDoorName(a, b)
    local name = a:GetName()
    return name ~= nil and name ~= "" and name == b:GetName()
end

function Biolock.GetPairedDoor(door, outwardHint)
    if not IsValid(door) or not Biolock.IsDoor(door) then return nil end

    if IsValid(door.GLBiolockPair) and Biolock.IsDoor(door.GLBiolockPair) then
        return door.GLBiolockPair
    end

    local range = isfunction(Biolock.GetDoubleDoorRange) and Biolock.GetDoubleDoorRange() or 96
    if range <= 0 then return nil end

    local center = door:WorldSpaceCenter()
    local outward = outwardHint or door:GetAngles():Forward()
    outward.z = 0
    if outward:LengthSqr() < 0.01 then outward = Vector(1, 0, 0) end
    outward:Normalize()

    local best, bestScore = nil, math.huge
    for _, other in ipairs(ents.GetAll()) do
        if other ~= door and IsValid(other) and Biolock.IsDoor(other) then
            local delta = other:WorldSpaceCenter() - center
            local lateral = delta - outward * delta:Dot(outward)
            local span = lateral:Length()
            local named = sameDoorName(door, other)
            local maxSpan = named and 256 or range

            if math.abs(delta.z) <= 48 and math.abs(delta:Dot(outward)) <= 24
                and span <= maxSpan then
                local score = named and (span - 10000) or span
                if score < bestScore then best, bestScore = other, score end
            end
        end
    end

    if IsValid(best) then
        door.GLBiolockPair = best
        best.GLBiolockPair = door
    end
    return best
end

function Biolock.Register(lock, door)
    Biolock.ByDoor[door:EntIndex()] = lock
end

function Biolock.Unregister(lock)
    for index, candidate in pairs(Biolock.ByDoor) do
        if candidate == lock then Biolock.ByDoor[index] = nil end
    end
end

function Biolock.GetLockForDoor(door)
    if not IsValid(door) then return nil end

    local lock = Biolock.ByDoor[door:EntIndex()]
    if IsValid(lock) and lock:GetDoor() == door then return lock end

    local pair = door.GLBiolockPair
    if IsValid(pair) then
        local pairedLock = Biolock.ByDoor[pair:EntIndex()]
        if IsValid(pairedLock) and pairedLock:GetDoor() == pair then return pairedLock end
    end

    return nil
end

function Biolock.IsLockedDoor(door)
    if not IsValid(door) then return false end
    local lock = Biolock.GetLockForDoor(door)
    return door.GLBiolockLocked == true or (IsValid(lock) and lock:GetLocked())
end

--[[
    Lock/unlock a door for every supported door class. On a double door the
    paired leaf receives the same state, so one scanner covers both leaves.

    Fire("Lock") is the canonical brush-door API. We additionally pin the
    movetype to NONE while locked: prop_door_rotating is a physics entity and
    can otherwise be shoved open with a crowbar, physgun or another prop.
    The original movetype is restored on unlock/removal.
]]
local function applyDoorState(door, locked)
    if locked then
        if door.GLBiolockOriginalMoveType == nil then
            door.GLBiolockOriginalMoveType = door:GetMoveType()
        end

        door:Fire("Lock", "", 0)
        door:SetMoveType(MOVETYPE_NONE)
        door.GLBiolockLocked = true
    else
        door:Fire("Unlock", "", 0)

        if door.GLBiolockOriginalMoveType ~= nil then
            door:SetMoveType(door.GLBiolockOriginalMoveType)
            door.GLBiolockOriginalMoveType = nil
        end

        door.GLBiolockLocked = nil
    end
end

function Biolock.SetDoorLocked(door, locked, lock)
    if not IsValid(door) then return end

    applyDoorState(door, locked)

    local pair = Biolock.GetPairedDoor(door, IsValid(lock) and (lock.GLOutward or lock:GetRight()) or nil)
    if IsValid(pair) and pair ~= door then applyDoorState(pair, locked) end

    if IsValid(lock) then lock.GLLocked = locked end
end

-- Create a scanner and attach it. pos/ang are optional hints; the final
-- handle-side placement is always resolved from the door on the server.
function Biolock.Create(door, pos, ang, ply)
    if not Biolock.IsDoor(door) then return nil end
    if Biolock.GetLockForDoor(door) then return nil end

    local place, facing = Biolock.GetPlacement(door, pos, ang, ply)
    if not place then
        if IsValid(ply) then
            Biolock.Feedback(ply, "denied", "AIM AT THE DOOR HANDLE", 0)
            Biolock.PlaySound(ply, nil, "denied")
        end
        return nil
    end

    -- Cache the adjacent leaf before the duplicate check so a second scanner
    -- cannot be placed on the other half of a double door.
    local outward = outwardFromFacing(facing)
    Biolock.GetPairedDoor(door, outward)
    if Biolock.GetLockForDoor(door) then
        if IsValid(ply) then
            Biolock.Feedback(ply, "denied", "LOCK ALREADY PRESENT", 0)
            Biolock.PlaySound(ply, nil, "denied")
        end
        return nil
    end

    local lock = ents.Create("greyline_biolock")
    if not IsValid(lock) then return nil end

    lock.GLOutward = outward
    lock:SetPos(place)
    lock:SetAngles(facing)
    lock:Spawn()
    lock:Activate()
    lock:AttachToDoor(door, ply)

    return lock
end

-- -------------------------------------------------------------------------
-- SECURITY HOOKS -- clients cannot bypass these with net messages.
-- -------------------------------------------------------------------------
hook.Add("PlayerUse", "Greyline.Biolock.BlockDoorUse", function(ply, ent)
    if Biolock.IsLockedDoor(ent) then return false end
end)

hook.Add("PhysgunPickup", "Greyline.Biolock.BlockPhysgun", function(ply, ent)
    if not IsValid(ent) then return end
    if ent:GetClass() == "greyline_biolock" then return false end
    if Biolock.IsLockedDoor(ent) then return false end
end)

hook.Add("GravGunPickupAllowed", "Greyline.Biolock.BlockGravgun", function(ply, ent)
    if not IsValid(ent) then return end
    if ent:GetClass() == "greyline_biolock" then return false end
    if Biolock.IsLockedDoor(ent) then return false end
end)

hook.Add("EntityTakeDamage", "Greyline.Biolock.DamageGate", function(target, dmginfo)
    if not IsValid(target) or target:GetClass() ~= "greyline_biolock" then return end
    if not Biolock.IsDestroyable() then return true end -- block damage entirely
end)

hook.Add("PlayerDisconnected", "Greyline.Biolock.CancelScan", function(ply)
    for _, lock in pairs(Biolock.ByDoor) do
        if IsValid(lock) and lock.GLScanningBy == ply then
            lock.GLScanningBy = nil
            lock:SetNWInt("greyline_biolock_state", STATE.Locked)
            lock:SetNWFloat("greyline_biolock_scan_start", 0)
            lock:SetNWFloat("greyline_biolock_scan_end", 0)
            Biolock.Log("scan_cancelled_disconnect", ply)
        end
    end
end)

-- -------------------------------------------------------------------------
-- PERSISTENCE -- optional, opt-in via convar
-- -------------------------------------------------------------------------
-- util.TableToJSON / JSONToTable round-trip Vectors and Angles as plain tables.
-- Accept both the short (x/y/z, p/y/r) and long (pitch/yaw/roll) key forms.
local function toVector(t)
    if not istable(t) then return Vector(0, 0, 0) end
    return Vector(tonumber(t.x) or 0, tonumber(t.y) or 0, tonumber(t.z) or 0)
end

local function toAngle(t)
    if not istable(t) then return angle_zero end
    local pitch = tonumber(t.p or t.pitch) or 0
    local yaw   = tonumber(t.y or t.yaw) or 0
    local roll  = tonumber(t.r or t.roll) or 0
    return Angle(pitch, yaw, roll)
end

function Biolock.SaveState()
    if not Biolock.GetPersist() then return end

    local entries = {}
    for _, lock in pairs(Biolock.ByDoor) do
        local door = IsValid(lock) and lock:GetDoor() or nil
        if IsValid(door) then
            entries[#entries + 1] = {
                scannerPos = lock:GetPos(),
                scannerAng = lock:GetAngles(),
                doorPos    = door:GetPos(),
                doorClass  = door:GetClass(),
            }
        end
    end

    file.Write(PERSIST_FILE, util.TableToJSON(entries, true))
end

hook.Add("InitPostEntity", "Greyline.Biolock.Restore", function()
    timer.Simple(1, function()
        if not Biolock.GetPersist() then return end

        local raw = file.Read(PERSIST_FILE, "DATA")
        if not raw or raw == "" then return end

        local entries = util.JSONToTable(raw)
        if not istable(entries) then return end

        for _, entry in ipairs(entries) do
            local target = toVector(entry.doorPos)
            local best, bestDistance = nil, math.huge

            for _, door in ipairs(ents.FindByClass(entry.doorClass or "func_door")) do
                local distance = door:GetPos():Distance(target)
                if distance < bestDistance then
                    best, bestDistance = door, distance
                end
            end

            -- 64u tolerance keeps a stale save from locking an unrelated door.
            if IsValid(best) and bestDistance <= 64 and not Biolock.GetLockForDoor(best) then
                -- Reuse the saved scanner transform so the restored lock goes
                -- back to the same handle edge and height, not a guessed side.
                local savedPos = toVector(entry.scannerPos)
                local savedAng = toAngle(entry.scannerAng)
                local yawOffset = isfunction(Biolock.GetModelAngleOffset)
                    and Biolock.GetModelAngleOffset().y
                    or (isangle(Biolock.Config.ModelAngleOffset) and Biolock.Config.ModelAngleOffset.y or -90)
                local outwardAng = Angle(0, savedAng.y - yawOffset, 0)
                Biolock.Create(best, savedPos, outwardAng, nil)
            end
        end

        Biolock.Log("restored", nil, "locks=" .. tostring(#entries))
    end)
end)

hook.Add("Shutdown", "Greyline.Biolock.SaveOnShutdown", function()
    Biolock.SaveState()
end)

-- -------------------------------------------------------------------------
-- ADMIN COMMANDS -- alternative placement path to the SWEP
-- -------------------------------------------------------------------------
local function aimTrace(ply)
    local start = ply:EyePos()
    return util.TraceLine({
        start  = start,
        endpos = start + ply:EyeAngles():Forward() * Biolock.GetPlaceDistance(),
        filter = ply,
        mask   = MASK_SOLID,
    })
end

-- `give` is sandbox-only; provide an explicit way to obtain a lock. If the
-- gamemode exposes a server-authoritative inventory service, put the lock in
-- the inventory. Otherwise fall back to the standalone SWEP.
local function giveViaInventory(ply)
    local inventory = Greyline and Greyline.Inventory
    if not inventory or not isfunction(inventory.Provision) then return false end

    local ok, reason = inventory.Provision(ply, "biolock", 1)
    if ok then
        ply:ChatPrint("[GREYLINE] Biolock added to your inventory. Aim at a door, open it, then left-click the item.")
        if isfunction(Biolock.Feedback) then
            Biolock.Feedback(ply, "granted", "BIOLOCK ADDED", 1.5)
        end
    else
        ply:ChatPrint("[GREYLINE] " .. tostring(reason))
    end
    return true
end

concommand.Add("greyline_biolock_give", function(ply)
    if not IsValid(ply) then return end
    if not Biolock.CanPlace(ply) then
        ply:ChatPrint("[GREYLINE] You are not allowed to use biolocks.")
        return
    end
    if giveViaInventory(ply) then return end

    if ply:HasWeapon("greyline_biolock_tool") then
        ply:ChatPrint("[GREYLINE] You already have the biolock tool.")
        return
    end
    local weapon = ply:Give("greyline_biolock_tool")
    if not IsValid(weapon) then
        ply:ChatPrint("[GREYLINE] Failed to give the biolock tool.")
        return
    end
    ply:SelectWeapon("greyline_biolock_tool")
    ply:ChatPrint("[GREYLINE] Biolock tool given.")
end)

concommand.Add("greyline_biolock_place", function(ply)
    if not IsValid(ply) then return end
    if not Biolock.CanPlace(ply) then
        ply:ChatPrint("[GREYLINE] You are not allowed to place biolocks.")
        return
    end
    if not Biolock.IsEnabled() then
        ply:ChatPrint("[GREYLINE] Biolock system is disabled.")
        return
    end

    local tr = aimTrace(ply)
    if not tr.Hit or not Biolock.IsDoor(tr.Entity) then
        ply:ChatPrint("[GREYLINE] Aim at a valid door.")
        Biolock.Feedback(ply, "denied", "INVALID SURFACE", 0)
        Biolock.PlaySound(ply, nil, "denied")
        return
    end
    if Biolock.GetLockForDoor(tr.Entity) then
        ply:ChatPrint("[GREYLINE] That door already has a biolock.")
        Biolock.Feedback(ply, "denied", "LOCK ALREADY PRESENT", 0)
        return
    end

    local lock = Biolock.Create(tr.Entity, tr.HitPos, tr.HitNormal:Angle(), ply)

    if IsValid(lock) then
        ply:ChatPrint("[GREYLINE] Biolock attached.")
        Biolock.PlaySound(ply, lock:GetPos(), "granted")
    else
        ply:ChatPrint("[GREYLINE] Aim at the door handle.")
    end
end)

concommand.Add("greyline_biolock_remove", function(ply)
    if not IsValid(ply) then return end
    if not Biolock.CanPlace(ply) then
        ply:ChatPrint("[GREYLINE] You are not allowed to remove biolocks.")
        return
    end

    local tr = aimTrace(ply)
    local target = tr.Entity

    if IsValid(target) and target:GetClass() == "greyline_biolock" then
        target:Remove()
        ply:ChatPrint("[GREYLINE] Biolock removed.")
        return
    end

    local lock = Biolock.GetLockForDoor(target)
    if IsValid(lock) then
        lock:Remove()
        ply:ChatPrint("[GREYLINE] Biolock removed.")
        return
    end

    ply:ChatPrint("[GREYLINE] Aim at a biolock or a locked door.")
end)
