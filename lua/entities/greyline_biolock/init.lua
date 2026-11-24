--[[---------------------------------------------------------------------------
    Greyline :: Biolock entity -- server
    File: lua/entities/greyline_biolock/init.lua

    Owns the scan state machine. Permission checks happen in Use(); the timer
    completion is re-validated in Think() so a disconnect/teleport cancels it.
---------------------------------------------------------------------------]]

AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

local Biolock = Greyline.Biolock
local STATE  = Biolock.Config.State

function ENT:Initialize()
    local model = Biolock.GetModel()
    self:SetModel(model)

    -- No physics object: physgun/gravity gun cannot grab or nudge the device.
    self:SetMoveType(MOVETYPE_NONE)
    self:SetSolid(SOLID_BBOX)
    self:SetSize(Vector(-6, -6, -2), Vector(6, 6, 10))
    self:SetUseType(SIMPLE_USE)

    self.GLLocked    = false
    self.GLHealth    = 100
    self.GLScanningBy = nil
    self.GLScanEndsAt = 0

    self:SetNWInt("greyline_biolock_state", STATE.Locked)
    self:SetNWFloat("greyline_biolock_scan_start", 0)
    self:SetNWFloat("greyline_biolock_scan_end", 0)
end

-- Called by Biolock.Create / the placement SWEP immediately after spawning.
function ENT:AttachToDoor(door, ply)
    if not Biolock.IsDoor(door) then return false end
    if Biolock.GetLockForDoor(door) then return false end

    self.GLDoor = door
    door.GLBiolock = self

    -- Ride the door: parenting makes the scanner follow every open/close,
    -- including rotating doors. SetParent keeps the child's local transform,
    -- so reapply the world placement chosen by Biolock.Create afterwards.
    local worldPos, worldAng = self:GetPos(), self:GetAngles()
    self:SetParent(door)
    self:SetPos(worldPos)
    self:SetAngles(worldAng)

    Biolock.Register(self, door)
    Biolock.SetDoorLocked(door, true, self)

    self.GLLocked = true
    self:SetNWInt("greyline_biolock_state", STATE.Locked)

    Biolock.Log("placed", ply, string.format("door=%d class=%s",
        door:EntIndex(), door:GetClass()))
    Biolock.SaveState()

    return true
end

function ENT:Use(activator, caller)
    if not IsValid(activator) or not activator:IsPlayer() then return end
    if not Biolock.IsEnabled() then return end

    local door = self:GetDoor()
    if not IsValid(door) then
        self:Remove()
        return
    end

    local current = self:GetState()
    if current == STATE.Scanning then return end

    -- Per-device debounce: SIMPLE_USE can fire several times per press.
    if self.GLNextUse and CurTime() < self.GLNextUse then return end
    self.GLNextUse = CurTime() + 0.5

    local function deny()
        self:SetNWInt("greyline_biolock_state", STATE.Denied)
        self.GLDeniedUntil = CurTime() + 1

        Biolock.Feedback(activator, "denied", "ACCESS DENIED", 0)
        Biolock.PlaySound(activator, self:GetPos(), "denied")
        Biolock.Log("access_denied", activator, "door=" .. tostring(door:EntIndex()))
    end

    -- THE permission check. Everything else here is cosmetic.
    if not Biolock.CanUnlock(activator) then
        deny()
        return
    end

    -- Toggle: once granted, the door stays unlocked until an authorized
    -- player clicks the scanner again. Unauthorized clicks still deny only.
    if current == STATE.Granted then
        Biolock.SetDoorLocked(door, true, self)

        self.GLScanningBy = nil
        self:SetNWInt("greyline_biolock_state", STATE.Locked)
        self:SetNWFloat("greyline_biolock_scan_start", 0)
        self:SetNWFloat("greyline_biolock_scan_end", 0)

        Biolock.Feedback(activator, "locked", "DOOR LOCKED", 0)
        Biolock.PlaySound(activator, self:GetPos(), "granted")
        Biolock.Log("relocked", activator, "door=" .. tostring(door:EntIndex()))
        Biolock.SaveState()
        return
    end

    local duration = Biolock.GetScanDuration()
    local now = CurTime()

    self.GLScanningBy  = activator
    self.GLScanEndsAt  = now + duration

    self:SetNWInt("greyline_biolock_state", STATE.Scanning)
    self:SetNWFloat("greyline_biolock_scan_start", now)
    self:SetNWFloat("greyline_biolock_scan_end", self.GLScanEndsAt)

    Biolock.Feedback(activator, "scanning", "BIOMETRIC SCAN", duration)
    Biolock.PlaySound(activator, self:GetPos(), "scan")
end

function ENT:Think()
    local now = CurTime()

    -- Cheap liveness check. If the door was removed, the device goes with it.
    if now >= (self.GLNextCheck or 0) then
        self.GLNextCheck = now + 0.5
        if not IsValid(self:GetDoor()) then
            self:Remove()
            return
        end
    end

    local state = self:GetState()

    if state == STATE.Scanning then
        local ply = self.GLScanningBy

        -- Disconnect, death or walking away all abort the scan.
        if not IsValid(ply) or not ply:Alive()
            or ply:GetPos():Distance(self:GetPos()) > Biolock.GetUseDistance() then
            self.GLScanningBy = nil
            self:SetNWInt("greyline_biolock_state", STATE.Locked)
            self:SetNWFloat("greyline_biolock_scan_start", 0)
            self:SetNWFloat("greyline_biolock_scan_end", 0)
            return
        end

        if now >= (self.GLScanEndsAt or math.huge) then
            self.GLScanningBy = nil

            local door = self:GetDoor()
            if IsValid(door) then
                Biolock.SetDoorLocked(door, false, self)
            end

            self:SetNWInt("greyline_biolock_state", STATE.Granted)
            self:SetNWFloat("greyline_biolock_scan_end", 0)
            -- No timer: Granted is latched until the next authorized Use.

            Biolock.Feedback(ply, "granted", "ACCESS GRANTED", 0)
            Biolock.PlaySound(ply, self:GetPos(), "granted")
            Biolock.Log("access_granted", ply, "door=" .. tostring(door:EntIndex()))
            Biolock.SaveState()
        end

        return
    end

    if state == STATE.Granted then
        -- Intentionally no auto-relock. ENT:Use handles the next click.
        return
    end

    if state == STATE.Denied and now >= (self.GLDeniedUntil or 0) then
        -- A denied click must not erase a latched unlock. Restore the actual
        -- door state rather than blindly returning to Locked.
        local restored = self:GetLocked() and STATE.Locked or STATE.Granted
        self:SetNWInt("greyline_biolock_state", restored)
    end
end

function ENT:OnRemove()
    local door = self:GetDoor()

    if IsValid(door) and self:GetLocked() then
        Biolock.SetDoorLocked(door, false, self) -- never strand a locked door
    end
    if IsValid(door) then door.GLBiolock = nil end

    Biolock.Unregister(self)
    Biolock.SaveState()
end

function ENT:OnTakeDamage(dmginfo)
    if not Biolock.IsDestroyable() then return 0 end

    self.GLHealth = (self.GLHealth or 100) - dmginfo:GetDamage()
    if self.GLHealth <= 0 then
        local attacker = dmginfo:GetAttacker()
        Biolock.Log("destroyed", IsValid(attacker) and attacker:IsPlayer() and attacker or nil,
            "door=" .. tostring(IsValid(self:GetDoor()) and self:GetDoor():EntIndex() or -1))
        self:Remove() -- OnRemove unlocks the door
    end

    return 0
end
