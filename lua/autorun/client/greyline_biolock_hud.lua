--[[---------------------------------------------------------------------------
    Greyline :: Biolock HUD -- client only
    File: lua/autorun/client/greyline_biolock_hud.lua

    Pure presentation. It receives feedback from the server and draws it.
    It sends nothing.
---------------------------------------------------------------------------]]

local Biolock = Greyline.Biolock
local active = nil

local function buildFonts()
    surface.CreateFont("Greyline.Biolock.Title", {
        font = "Roboto", size = 26, weight = 700, antialias = true,
    })
    surface.CreateFont("Greyline.Biolock.Sub", {
        font = "Roboto", size = 13, weight = 500, antialias = true,
    })
end

buildFonts()
hook.Add("Initialize", "Greyline.Biolock.Fonts", buildFonts)

net.Receive(Biolock.Config.Net.Feedback, function()
    active = {
        kind     = net.ReadString(),
        text     = net.ReadString(),
        duration = net.ReadFloat(),
        started  = CurTime(),
    }
end)

local function colourFor(kind)
    local c = Biolock.Config.Colors
    if kind == "granted" or kind == "locked" then return c.granted end
    if kind == "scanning" then return c.scanning end
    return c.denied
end

hook.Add("HUDPaint", "Greyline.Biolock.HUD", function()
    if not active then return end

    local age = CurTime() - active.started
    local hold = math.max(active.duration, 1.4)
    local total = hold + 0.3

    if age > total then
        active = nil
        return
    end

    -- Fade out over the last 0.3 seconds.
    local alpha = math.Clamp((total - age) / 0.3, 0, 1)
    local accent = colourFor(active.kind)
    local cx = ScrW() * 0.5
    local cy = ScrH() * 0.32

    draw.RoundedBox(4, cx - 190, cy - 46, 380, 88, Color(6, 6, 8, 210 * alpha))
    surface.SetDrawColor(accent.r, accent.g, accent.b, 220 * alpha)
    surface.DrawOutlinedRect(cx - 190, cy - 46, 380, 88, 1)
    surface.SetDrawColor(accent.r, accent.g, accent.b, 220 * alpha)
    surface.DrawRect(cx - 190, cy - 46, 380, 2)

    draw.SimpleText(active.text, "Greyline.Biolock.Title",
        cx, cy - 22, Color(accent.r, accent.g, accent.b, 255 * alpha), TEXT_ALIGN_CENTER)

    if active.duration > 0 then
        local fraction = math.Clamp(age / active.duration, 0, 1)
        local barWidth = 300

        draw.RoundedBox(2, cx - barWidth * 0.5, cy + 18, barWidth, 5,
            Color(40, 40, 48, 220 * alpha))
        draw.RoundedBox(2, cx - barWidth * 0.5, cy + 18, barWidth * fraction, 5,
            Color(accent.r, accent.g, accent.b, 255 * alpha))

        draw.SimpleText("BIOMETRIC VERIFICATION", "Greyline.Biolock.Sub",
            cx, cy + 30, Color(200, 200, 200, 180 * alpha), TEXT_ALIGN_CENTER)
    end
end)
