--[[---------------------------------------------------------------------------
    Greyline :: Biolock -- shared configuration
    File: lua/autorun/greyline_biolock_config.lua

    Loaded on BOTH realms. Every tunable lives here or in a convar defined
    below. This file never changes game state.
---------------------------------------------------------------------------]]

Greyline = Greyline or {}
Greyline.Biolock = Greyline.Biolock or {}

local Biolock = Greyline.Biolock

-- -------------------------------------------------------------------------
-- CONFIG -- defaults. Convars below override these at runtime.
-- -------------------------------------------------------------------------
Biolock.Config = {
    Enabled             = true,
    AllowedFactions     = { "combine" },   -- lower-case, comma list in convar
    AdminOverride       = "superadmin",   -- none | admin | superadmin
    ScanDuration        = 1.2,            -- seconds
    RelockDelay         = 0,              -- deprecated: locks stay unlocked until the next Use
    PlaceDistance       = 128,            -- trace length for placement
    UseDistance         = 120,            -- how far the scanner can be used
    Destroyable         = false,          -- device can be damaged/destroyed
    Persist             = false,          -- survive map changes
    AllowFactionPlacement = true,         -- Combine may place, not just admin

    Model               = "models/props_combine/combine_lock01.mdl",
    ModelYawOffset      = -90,            -- combine_lock01 faces local +Y; turn that outward
    ModelAngleOffset    = Angle(0, -90, 0), -- fallback for the yaw convar below

    HandleInset         = 10,             -- in from the handle-side edge (lock half-width is ~9)
    HandleBand          = 18,             -- max aim distance from the handle edge
    HandleOut           = 4,              -- out from the door face
    DoubleDoorRange     = 96,             -- max centre distance for paired double-door leaves; 0 disables
    LightOffset         = Vector(0, 8, -6), -- local offset to the circular status light

    DoorClasses = {
        ["func_door"]          = true,
        ["func_door_rotating"] = true,
        ["func_door_angled"]   = true,
        ["prop_door_rotating"] = true,
    },

    Sounds = {
        denied  = "buttons/combine_button1.wav",
        granted = "buttons/combine_button3.wav",
        scan    = "buttons/combine_button2.wav",
        hum     = "ambient/machines/combine_terminal_idle2.wav",
    },

    -- Used when a configured sound path is not installed on the server.
    FallbackSounds = {
        denied  = "ui/cancel.wav",
        granted = "ui/completequest.wav",
        scan    = "ui/buttonrollover.wav",
    },

    Colors = {
        locked   = Color(220, 60, 60),
        scanning = Color(80, 160, 255),
        granted  = Color(80, 220, 120),
        denied   = Color(255, 50, 50),
    },

    State = { Locked = 1, Scanning = 2, Granted = 3, Denied = 4 },
    Net   = { Feedback = "greyline_biolock_feedback" },
}

-- -------------------------------------------------------------------------
-- CONVARS -- name, default, description
-- -------------------------------------------------------------------------
Biolock.Convars = {
    enabled              = { "greyline_biolock_enabled",              "1",       "Enable the biolock system." },
    allowed_factions     = { "greyline_biolock_allowed_factions",     "combine", "Comma-separated faction ids allowed to unlock." },
    scan_duration        = { "greyline_biolock_scan_duration",        "1.2",     "Seconds a biometric scan takes." },
    relock_delay         = { "greyline_biolock_relock_delay",         "0",       "Deprecated: granted doors now stay unlocked until the next authorized Use." },
    admin_override       = { "greyline_biolock_admin_override",       "superadmin", "none | admin | superadmin bypass." },
    destroyable          = { "greyline_biolock_destroyable",          "0",       "Allow the device to be destroyed." },
    persist              = { "greyline_biolock_persist",              "0",       "Persist locks across map changes." },
    allow_faction_place  = { "greyline_biolock_allow_faction_place",  "1",       "Allow allowed-faction players to place locks." },
    place_distance       = { "greyline_biolock_place_distance",       "128",     "Placement trace length." },
    use_distance         = { "greyline_biolock_use_distance",         "120",     "Maximum distance to operate the scanner." },
    model                = { "greyline_biolock_model",                Biolock.Config.Model, "Biolock model path." },
    model_yaw_offset     = { "greyline_biolock_model_yaw_offset",     tostring(Biolock.Config.ModelYawOffset), "Yaw offset so the model's front faces out of the door." },
    handle_right         = { "greyline_biolock_handle_right",         "18",  "Deprecated: the handle edge is detected from the door itself." },
    handle_down          = { "greyline_biolock_handle_down",          "14",  "Deprecated: the handle height comes from the placement trace." },
    handle_inset         = { "greyline_biolock_handle_inset",         "10",  "Units inward from the handle-side door edge." },
    handle_band          = { "greyline_biolock_handle_band",          "18",  "Max aim distance from the handle edge; larger is more forgiving." },
    handle_out           = { "greyline_biolock_handle_out",           "4",   "Distance out from the door face." },
    double_door_range    = { "greyline_biolock_double_door_range",    "96",  "Max centre distance for pairing double-door leaves; 0 disables." },
    light_offset         = { "greyline_biolock_light_offset",         "0 8 -6", "Local offset to the circular status light (x y z)." },
    sound_denied         = { "greyline_biolock_sound_denied",         Biolock.Config.Sounds.denied,  "Access denied sound." },
    sound_granted        = { "greyline_biolock_sound_granted",        Biolock.Config.Sounds.granted, "Access granted sound." },
    sound_scan           = { "greyline_biolock_sound_scan",           Biolock.Config.Sounds.scan,    "Scan start sound." },
    sound_hum            = { "greyline_biolock_sound_hum",            Biolock.Config.Sounds.hum,     "Idle terminal hum (looping)." },
}

for _, def in pairs(Biolock.Convars) do
    if not ConVarExists(def[1]) then
        local flags = FCVAR_ARCHIVE
        if SERVER then flags = bit.bor(flags, FCVAR_REPLICATED) end
        CreateConVar(def[1], def[2], flags, def[3])
    end
end

-- -------------------------------------------------------------------------
-- Accessors -- always go through convars so runtime changes take effect.
-- -------------------------------------------------------------------------
local function cv(name, fallback)
    local c = GetConVar(name)
    return c and c:GetString() or fallback
end

local function cvFloat(name, fallback)
    local c = GetConVar(name)
    return tonumber(c and c:GetString() or nil) or fallback
end

local function bool(value)
    return value == "1" or string.lower(value) == "true" or string.lower(value) == "yes"
end

local function cvVector(name, fallback)
    local raw = cv(name, "")
    local x, y, z = string.match(raw, "^%s*(-?[%d%.]+)[%s,]+(-?[%d%.]+)[%s,]+(-?[%d%.]+)%s*$")
    if not x then return fallback end
    return Vector(tonumber(x), tonumber(y), tonumber(z))
end

function Biolock.IsEnabled()          return bool(cv(Biolock.Convars.enabled[1], "1")) end
function Biolock.IsDestroyable()      return bool(cv(Biolock.Convars.destroyable[1], "0")) end
function Biolock.GetPersist()         return bool(cv(Biolock.Convars.persist[1], "0")) end
function Biolock.AllowFactionPlace()  return bool(cv(Biolock.Convars.allow_faction_place[1], "1")) end

function Biolock.GetScanDuration()    return math.max(0.2, cvFloat(Biolock.Convars.scan_duration[1], 1.2)) end
function Biolock.GetRelockDelay()     return math.max(0, cvFloat(Biolock.Convars.relock_delay[1], Biolock.Config.RelockDelay)) end
function Biolock.GetPlaceDistance()   return math.max(32, cvFloat(Biolock.Convars.place_distance[1], 128)) end
function Biolock.GetUseDistance()     return math.max(32, cvFloat(Biolock.Convars.use_distance[1], 120)) end

function Biolock.GetHandleOffset()
    -- Only the outward offset is still used; the old right/down values are
    -- kept for save compatibility but no longer decide placement.
    return 0, 0, math.Clamp(cvFloat(Biolock.Convars.handle_out[1], Biolock.Config.HandleOut), 0, 32)
end

function Biolock.GetHandleInset()
    return math.Clamp(cvFloat(Biolock.Convars.handle_inset[1], Biolock.Config.HandleInset), 2, 32)
end

function Biolock.GetHandleBand()
    return math.Clamp(cvFloat(Biolock.Convars.handle_band[1], Biolock.Config.HandleBand), 4, 64)
end

function Biolock.GetDoubleDoorRange()
    return math.Clamp(cvFloat(Biolock.Convars.double_door_range[1], Biolock.Config.DoubleDoorRange), 0, 256)
end

function Biolock.GetLightOffset()
    local offset = cvVector(Biolock.Convars.light_offset[1], Biolock.Config.LightOffset)
    -- Archived servers may still hold the old "+X is the front" value. The
    -- combine_lock01 face is +Y, so rotate that legacy offset into place.
    if math.abs(offset.y) < 0.01 and math.abs(offset.x) > 0.01 then
        offset = Vector(0, offset.x, offset.z)
    end
    return offset
end

-- combine_lock01's visible face is along local +Y, while an entity's forward
-- is local +X. A -90 yaw makes the modelled face point straight out of the
-- door. The convar lets an admin correct this live if a custom model differs.
function Biolock.GetModelAngleOffset()
    local yaw = math.Clamp(cvFloat(Biolock.Convars.model_yaw_offset[1],
        Biolock.Config.ModelYawOffset), -180, 180)
    return Angle(0, yaw, 0)
end

local LEGACY_MODELS = {
    ["models/combine_scanner.mdl"] = true,
    ["models/combine_camera.mdl"]  = true,
}

function Biolock.GetModel()
    local model = cv(Biolock.Convars.model[1], Biolock.Config.Model)
    -- Ignore a stale archived value from the old defaults so placed locks
    -- always pick up the configured Biolock model.
    if LEGACY_MODELS[string.lower(model)] then model = Biolock.Config.Model end
    if not file.Exists(model, "GAME") then
        model = Biolock.Config.Model
    end
    return model
end

function Biolock.GetSound(key)
    return cv(Biolock.Convars["sound_" .. key][1], Biolock.Config.Sounds[key] or "")
end

function Biolock.GetHumSound()
    return cv(Biolock.Convars.sound_hum[1], Biolock.Config.Sounds.hum)
end

function Biolock.GetAllowedFactions()
    local raw = cv(Biolock.Convars.allowed_factions[1], "combine")
    local allowed = {}
    for part in string.gmatch(raw, "[^,]+") do
        part = string.lower(string.Trim(part))
        if part ~= "" then allowed[part] = true end
    end
    if not next(allowed) then allowed.combine = true end
    return allowed
end

function Biolock.GetAdminOverrideMode()
    return string.lower(cv(Biolock.Convars.admin_override[1], "superadmin"))
end

-- -------------------------------------------------------------------------
-- GAMEMODE INTEGRATION
--
-- Greyline stores faction in this order (see sh_items.lua in the gamemode):
--   ply.GLFaction          temporary override set by an admin/event
--   ply.GLCharacter.faction persisted character record
--   gl_faction NWString    replicated to clients
-- Override this function if your gamemode exposes a different API.
-- -------------------------------------------------------------------------
function Biolock.GetPlayerFaction(ply)
    if not IsValid(ply) then return nil end

    if ply.GLFaction and ply.GLFaction ~= "" then
        return string.lower(tostring(ply.GLFaction))
    end
    if ply.GLCharacter and ply.GLCharacter.faction then
        return string.lower(tostring(ply.GLCharacter.faction))
    end

    local replicated = ply:GetNWString("gl_faction", "")
    if replicated and replicated ~= "" then
        return string.lower(replicated)
    end

    if isfunction(ply.GetFaction) then
        return string.lower(tostring(ply:GetFaction()))
    end

    return nil
end

function Biolock.HasAdminOverride(ply)
    local mode = Biolock.GetAdminOverrideMode()
    if mode == "none" or not IsValid(ply) then return false end
    if mode == "admin" then return ply:IsAdmin() end
    return ply:IsSuperAdmin()
end

function Biolock.CanUnlock(ply)
    if not IsValid(ply) or not Biolock.IsEnabled() then return false end
    if Biolock.HasAdminOverride(ply) then return true end

    local faction = Biolock.GetPlayerFaction(ply)
    return faction ~= nil and Biolock.GetAllowedFactions()[faction] == true
end

function Biolock.CanPlace(ply)
    if not IsValid(ply) or not Biolock.IsEnabled() then return false end
    if Biolock.HasAdminOverride(ply) then return true end
    return Biolock.AllowFactionPlace() and Biolock.CanUnlock(ply)
end

function Biolock.IsDoor(ent)
    return IsValid(ent) and Biolock.Config.DoorClasses[ent:GetClass()] == true
end

-- Return the signed min/max extent of the door along a world-space axis,
-- relative to its centre. Used to find the handle edge, not the door centre.
local function extentsAlong(door, center, axis)
    local mins, maxs = door:GetCollisionBounds()
    if not mins or not maxs then
        mins, maxs = door:OBBMins(), door:OBBMaxs()
    end
    if not mins or not maxs then return -24, 24 end

    local low, high = math.huge, -math.huge
    for _, x in ipairs({ mins.x, maxs.x }) do
        for _, y in ipairs({ mins.y, maxs.y }) do
            for _, z in ipairs({ mins.z, maxs.z }) do
                local along = (door:LocalToWorld(Vector(x, y, z)) - center):Dot(axis)
                low = math.min(low, along)
                high = math.max(high, along)
            end
        end
    end
    if low > high then return -24, 24 end
    return low, high
end

-- The lock is ONLY mounted at the handle edge of the door. For hinged doors
-- the entity origin is the hinge, so the handle is the opposite edge. Brush
-- doors use the side the player aimed at. Interactive placement must be aimed
-- within HandleBand of that edge; restore calls (no player) skip the check.
function Biolock.GetPlacement(door, pos, ang, ply)
    if not IsValid(door) then return pos or vector_origin, ang or angle_zero end

    local center = door:WorldSpaceCenter()
    local outward = (ang and ang:Forward()) or Vector(0, 0, 0)
    if outward:LengthSqr() < 0.01 and pos then outward = pos - center end
    outward.z = 0
    if outward:LengthSqr() < 0.01 then outward = Vector(1, 0, 0) end
    outward:Normalize()

    local right = outward:Cross(Vector(0, 0, 1))
    if right:LengthSqr() < 0.01 then right = Vector(0, 1, 0) end
    right:Normalize()

    local low, high = extentsAlong(door, center, right)
    local heightLow, heightHigh = extentsAlong(door, center, Vector(0, 0, 1))
    local halfSpan = (high - low) * 0.5

    -- Hinge at the entity origin => handle is the opposite edge.
    local originAlong = (door:GetPos() - center):Dot(right)
    local handleSide
    if math.abs(originAlong) > halfSpan * 0.5 then
        handleSide = originAlong > 0 and -1 or 1
    elseif pos then
        handleSide = (pos - center):Dot(right) >= 0 and 1 or -1
    else
        handleSide = 1
    end

    local edge = handleSide > 0 and high or low
    local inset = math.Clamp(isfunction(Biolock.GetHandleInset)
        and Biolock.GetHandleInset() or Biolock.Config.HandleInset, 2, math.max(2, halfSpan - 2))
    local along = edge - handleSide * inset

    -- Handle height comes from the trace, clamped to the physical door.
    local z = center.z
    if pos then
        z = math.Clamp(pos.z, center.z + heightLow + 3, center.z + heightHigh - 3)
    end

    if pos and IsValid(ply) then
        local band = isfunction(Biolock.GetHandleBand)
            and Biolock.GetHandleBand() or Biolock.Config.HandleBand
        local aimAlong = (pos - center):Dot(right)
        if math.abs(aimAlong - along) > band or math.abs(pos.z - z) > band then
            return nil, nil -- not aimed at the handle
        end
    end

    local _, _, outOffset = Biolock.GetHandleOffset()
    local place = center + right * along + Vector(0, 0, z - center.z) + outward * outOffset
    local angleOffset = isfunction(Biolock.GetModelAngleOffset)
        and Biolock.GetModelAngleOffset()
        or (isangle(Biolock.Config.ModelAngleOffset) and Biolock.Config.ModelAngleOffset or angle_zero)
    local facing = Angle(0, outward:Angle().yaw, 0) + angleOffset

    return place, facing
end

function Biolock.Log(action, ply, details)
    if Greyline.LogEvent then
        Greyline.LogEvent("Biolock", ply, action, details)
        return
    end

    local sid = IsValid(ply) and ply:SteamID() or "system"
    print(string.format("[Greyline][Biolock][%s][%s]%s",
        sid, action, details and (" | " .. tostring(details)) or ""))
end

-- -------------------------------------------------------------------------
-- PRESENTATION HELPERS
-- -------------------------------------------------------------------------
function Biolock.ResolveSound(path, key)
    if path and path ~= "" and file.Exists("sound/" .. path, "GAME") then
        return path
    end
    return Biolock.Config.FallbackSounds[key] or "ui/buttonclick.wav"
end

if SERVER then
    util.AddNetworkString(Biolock.Config.Net.Feedback)

    function Biolock.Feedback(ply, kind, text, duration)
        if not IsValid(ply) then return end
        net.Start(Biolock.Config.Net.Feedback)
            net.WriteString(kind or "denied")
            net.WriteString(text or "")
            net.WriteFloat(duration or 0)
        net.Send(ply)
    end

    function Biolock.PlaySound(ply, pos, key)
        local path = Biolock.ResolveSound(Biolock.GetSound(key), key)
        if pos then
            sound.Play(path, pos, 75, 100)
        elseif IsValid(ply) then
            ply:EmitSound(path, 75, 100, 1)
        end
    end
end
