--[[---------------------------------------------------------------------------
    Greyline :: Biolock entity -- client (cosmetic only)
    File: lua/entities/greyline_biolock/cl_init.lua

    No permission decisions here. State is read from networked vars.
---------------------------------------------------------------------------]]

include("shared.lua")

local Biolock = Greyline.Biolock
local STATE  = Biolock.Config.State
local glowMat = Material("sprites/glow04_noz")

function ENT:Initialize()
    local hum = Biolock.GetHumSound()
    if hum and hum ~= "" and file.Exists("sound/" .. hum, "GAME") then
        self.GLHum = CreateSound(self, hum)
        self.GLHum:SetSoundLevel(60)
        self.GLHum:Play()
    end
end

function ENT:OnRemove()
    if self.GLHum then
        self.GLHum:Stop()
        self.GLHum = nil
    end
end

function ENT:Draw()
    self:DrawModel()
end

function ENT:DrawTranslucent()
    local state = self:GetState()
    local palette = Biolock.Config.Colors

    local colour
    if state == STATE.Granted then
        colour = palette.granted
    elseif state == STATE.Scanning then
        colour = palette.scanning
    elseif state == STATE.Denied then
        colour = palette.denied
    else
        colour = palette.locked
    end

    local pulse = state == STATE.Scanning
        and (0.65 + 0.35 * math.sin(CurTime() * 9)) or 1

    local lightOffset = Biolock.GetLightOffset and Biolock.GetLightOffset()
        or Vector(0, 8, -6)
    local pos = self:LocalToWorld(lightOffset)
    local size = 12 * pulse

    render.SetMaterial(glowMat)
    render.DrawSprite(pos, size, size, Color(colour.r, colour.g, colour.b, 200 * pulse))

    -- Scan progress: a sprite that expands across the duration. All values
    -- come from the server's start/end timestamps, so it cannot be faked.
    if state == STATE.Scanning then
        local started = self:GetScanStart()
        local finished = self:GetScanEnd()
        local duration = math.max(finished - started, 0.001)
        local frac = math.Clamp((CurTime() - started) / duration, 0, 1)

        render.DrawSprite(pos + self:GetForward() * 2,
            4 + 20 * frac, 4 + 20 * frac,
            Color(colour.r, colour.g, colour.b, 150))
    end
end
