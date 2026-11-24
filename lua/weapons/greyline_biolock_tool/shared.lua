--[[---------------------------------------------------------------------------
    Greyline :: Biolock placement tool
    File: lua/weapons/greyline_biolock_tool/shared.lua

    The weapon is only an input device: it traces locally on the server and
    calls the same Biolock.Create path as the admin console command.
---------------------------------------------------------------------------]]

SWEP.PrintName      = "Combine Biolock"
SWEP.Author         = "Greyline"
SWEP.Category       = "Greyline"
SWEP.Instructions   = "Primary: attach to a door. Secondary: remove a biolock."
SWEP.Spawnable      = true
SWEP.AdminOnly      = false -- runtime permission is checked serverside

SWEP.ViewModel      = ""
SWEP.WorldModel     = ""
SWEP.UseHands       = false
SWEP.DrawAmmo       = false
SWEP.DrawCrosshair  = true

SWEP.Primary.ClipSize    = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic   = false
SWEP.Primary.Ammo        = "none"

SWEP.Secondary.ClipSize    = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic   = false
SWEP.Secondary.Ammo        = "none"

local function aimTrace(owner)
    local start = owner:EyePos()
    return util.TraceLine({
        start  = start,
        endpos = start + owner:EyeAngles():Forward() * Greyline.Biolock.GetPlaceDistance(),
        filter = owner,
        mask   = MASK_SOLID,
    })
end

if SERVER then

function SWEP:PrimaryAttack()
    local owner = self:GetOwner()
    if not IsValid(owner) or not owner:IsPlayer() then return end

    self:SetNextPrimaryFire(CurTime() + 0.6)

    local Biolock = Greyline.Biolock

    if not Biolock.IsEnabled() then
        owner:ChatPrint("[GREYLINE] Biolock system is disabled.")
        return
    end
    if not Biolock.CanPlace(owner) then
        owner:ChatPrint("[GREYLINE] You are not allowed to place biolocks.")
        Biolock.Feedback(owner, "denied", "NOT AUTHORISED", 0)
        Biolock.PlaySound(owner, nil, "denied")
        return
    end

    local tr = aimTrace(owner)
    if not tr.Hit or not Biolock.IsDoor(tr.Entity) then
        owner:ChatPrint("[GREYLINE] Aim at a valid door.")
        Biolock.Feedback(owner, "denied", "INVALID SURFACE", 0)
        Biolock.PlaySound(owner, nil, "denied")
        return
    end
    if Biolock.GetLockForDoor(tr.Entity) then
        owner:ChatPrint("[GREYLINE] That door already has a biolock.")
        Biolock.Feedback(owner, "denied", "LOCK ALREADY PRESENT", 0)
        return
    end

    local lock = Biolock.Create(tr.Entity, tr.HitPos, tr.HitNormal:Angle(), owner)

    if IsValid(lock) then
        owner:ChatPrint("[GREYLINE] Biolock attached.")
        Biolock.PlaySound(owner, lock:GetPos(), "granted")
    else
        owner:ChatPrint("[GREYLINE] Aim at the door handle.")
        Biolock.PlaySound(owner, nil, "denied")
    end
end

function SWEP:SecondaryAttack()
    local owner = self:GetOwner()
    if not IsValid(owner) or not owner:IsPlayer() then return end

    self:SetNextSecondaryFire(CurTime() + 0.6)

    local Biolock = Greyline.Biolock
    if not Biolock.CanPlace(owner) then
        owner:ChatPrint("[GREYLINE] You are not allowed to remove biolocks.")
        return
    end

    local tr = aimTrace(owner)
    local target = tr.Entity

    if IsValid(target) and target:GetClass() == "greyline_biolock" then
        target:Remove()
        owner:ChatPrint("[GREYLINE] Biolock removed.")
        return
    end

    local lock = Biolock.GetLockForDoor(target)
    if IsValid(lock) then
        lock:Remove()
        owner:ChatPrint("[GREYLINE] Biolock removed.")
        return
    end

    owner:ChatPrint("[GREYLINE] Aim at a biolock or a locked door.")
end

function SWEP:Reload()
    -- Intentionally unused: reload must never affect server state.
end

end -- SERVER
