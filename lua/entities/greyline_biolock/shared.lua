--[[---------------------------------------------------------------------------
    Greyline :: Biolock entity -- shared definition
    File: lua/entities/greyline_biolock/shared.lua
---------------------------------------------------------------------------]]

ENT.Type            = "anim"
ENT.PrintName       = "Combine Biolock"
ENT.Author          = "Greyline"
ENT.Category        = "Greyline"
ENT.Spawnable       = false
ENT.AdminOnly       = true
ENT.RenderGroup     = RENDERGROUP_BOTH

local Biolock = Greyline and Greyline.Biolock
local STATE  = Biolock and Biolock.Config.State
            or { Locked = 1, Scanning = 2, Granted = 3, Denied = 4 }

-- The door reference is server-side only; it is never networked.
function ENT:GetDoor()
    return self.GLDoor
end

function ENT:GetLocked()
    return self.GLLocked == true
end

function ENT:GetState()
    return self:GetNWInt("greyline_biolock_state", STATE.Locked)
end

function ENT:GetScanStart()
    return self:GetNWFloat("greyline_biolock_scan_start", 0)
end

function ENT:GetScanEnd()
    return self:GetNWFloat("greyline_biolock_scan_end", 0)
end
