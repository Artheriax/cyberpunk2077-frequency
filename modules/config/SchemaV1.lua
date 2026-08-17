--[[
    Frequency - SchemaV1.lua

    Handler for the legacy station metadata format ("schema v1"). This is
    the format every existing radioExt station pack ships with, so Frequency
    accepts it unchanged (drop-in compatibility) and normalizes it into the
    internal station config model.

    Example (v1):
    {
        "displayName": "69.9 My Station",
        "fm": 69.9,
        "volume": 1.0,
        "icon": "UIIcon.RadioHipHop",
        "customIcon": { "useCustom": false, "inkAtlasPath": "", "inkAtlasPart": "" },
        "streamInfo": { "isStream": false, "streamURL": "" },
        "order": []
    }

    Written from scratch for Frequency.
]]

local Class = require("modules/core/Class")

local SchemaV1 = Class.define("SchemaV1")

SchemaV1.VERSION = 1

function SchemaV1:initialize(logger)
    self.logger = logger
end

--- v1 documents simply have no "schemaVersion" field.
function SchemaV1.Matches(raw)
    return type(raw) == "table" and raw.schemaVersion == nil
end

local function coerceNumber(value, fallback)
    if type(value) == "number" then
        return value
    end
    local parsed = tonumber(value)
    if parsed then
        return parsed
    end
    return fallback
end

local function coerceBool(value, fallback)
    if type(value) == "boolean" then
        return value
    end
    if value == "true" or value == 1 then
        return true
    end
    if value == "false" or value == 0 then
        return false
    end
    return fallback
end

--- Normalizes a raw v1 table into the internal config model.
--- Also reports which fields had to be repaired so the caller can write
--- the completed file back to disk.
function SchemaV1:Normalize(raw, folderName)
    local repaired = false
    local function repair(field)
        repaired = true
        return field
    end

    -- displayName -----------------------------------------------------------
    local displayName = raw.displayName
    if type(displayName) ~= "string" or displayName == "" then
        self.logger:Warnf("Station in folder \"%s\" has an invalid displayName; using the folder name instead.", folderName)
        displayName = repair(folderName)
    end

    -- fm --------------------------------------------------------------------
    local fm = raw.fm
    if type(fm) ~= "number" then
        local coerced = tonumber(fm)
        if coerced == nil then
            self.logger:Warnf("Station \"%s\" has an invalid fm value (%s); defaulting to 0.", tostring(displayName), tostring(fm))
            coerced = 0
        end
        fm = repair(coerced)
    end

    -- volume ----------------------------------------------------------------
    local volume = raw.volume
    if type(volume) ~= "number" then
        local coerced = tonumber(volume)
        if coerced == nil then
            self.logger:Warnf("Station \"%s\" has an invalid volume value (%s); defaulting to 1.0.", tostring(displayName), tostring(volume))
            coerced = 1.0
        end
        volume = repair(coerced)
    end

    -- icon ------------------------------------------------------------------
    local icon = raw.icon
    if type(icon) ~= "string" or icon == "" then
        icon = repair("default")
    end

    -- customIcon ------------------------------------------------------------
    local customIcon = raw.customIcon
    if type(customIcon) ~= "table" then
        customIcon = repair({ useCustom = false, inkAtlasPath = "", inkAtlasPart = "" })
    else
        if type(customIcon.useCustom) ~= "boolean" then customIcon.useCustom = repair(false) end
        if type(customIcon.inkAtlasPath) ~= "string" then customIcon.inkAtlasPath = repair("") end
        if type(customIcon.inkAtlasPart) ~= "string" then customIcon.inkAtlasPart = repair("") end
    end

    -- streamInfo ------------------------------------------------------------
    -- v1 stations break hard when isStream is missing or not a boolean:
    -- the station gets treated as file-based with zero songs. Coerce it.
    local streamInfo = raw.streamInfo
    local isStream, streamURL = false, ""
    if type(streamInfo) ~= "table" then
        repair(true)
    else
        isStream = coerceBool(streamInfo.isStream, false)
        if type(streamInfo.isStream) ~= "boolean" then
            self.logger:Warnf("Station \"%s\" had a non-boolean streamInfo.isStream (%s); coerced to %s.",
                tostring(displayName), tostring(streamInfo.isStream), tostring(isStream))
            repair(true)
        end
        streamURL = streamInfo.streamURL
        if type(streamURL) ~= "string" then
            streamURL = repair(tostring(streamURL or ""))
        end
    end

    if not isStream and streamURL ~= "" then
        self.logger:Infof("Station \"%s\" sets streamURL but isStream is false. Set isStream to true if this is meant to be a web stream.",
            tostring(displayName))
    end

    -- order -----------------------------------------------------------------
    local order = raw.order
    if type(order) ~= "table" then
        order = repair({})
    end

    -- group (optional extension, harmless in v1 files) ----------------------
    local group = ""
    if type(raw.group) == "string" then
        group = raw.group
    end

    return {
        schemaVersion = SchemaV1.VERSION,
        displayName = displayName,
        fm = fm,
        volume = volume,
        icon = icon,
        customIcon = customIcon,
        stream = { isStream = isStream, url = streamURL },
        order = order,
        group = group,
    }, repaired
end

--- Writes back any missing fields into the raw v1 table (keeps v1 shape so
--- the file stays readable by older tooling).
function SchemaV1:FillMissing(raw, normalized)
    local dirty = false
    local function ensure(key, value)
        if raw[key] == nil then
            raw[key] = value
            dirty = true
        end
    end

    ensure("displayName", normalized.displayName)
    ensure("fm", normalized.fm)
    ensure("volume", normalized.volume)
    ensure("icon", normalized.icon)
    ensure("customIcon", { useCustom = false, inkAtlasPath = "", inkAtlasPart = "" })
    ensure("streamInfo", { isStream = false, streamURL = "" })
    ensure("order", {})

    return dirty
end

return SchemaV1
