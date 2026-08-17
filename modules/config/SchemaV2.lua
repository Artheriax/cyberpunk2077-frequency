--[[
    Frequency - SchemaV2.lua

    Handler for the new Frequency metadata format ("schema v2"). v2 is a
    cleaner layout: a mandatory "schemaVersion" field, a first-class
    "stream" section, a first-class "group" field for station groups, and
    optional per-song display titles.

    Example (v2):
    {
        "schemaVersion": 2,
        "displayName": "88.7 Neon Nights",
        "fm": 88.7,
        "volume": 1.0,
        "group": "myStationPack",
        "icon": "UIIcon.RadioHipHop",
        "customIcon": {
            "useCustom": true,
            "inkAtlasPath": "base\\\\gameplay\\\\gui\\\\my_atlas.inkatlas",
            "inkAtlasPart": "my_part"
        },
        "stream": { "url": "https://example.com/stream.mp3" },
        "order": ["intro.mp3", "daily_mix.mp3"],
        "songTitles": { "intro.mp3": "Neon Nights Intro" }
    }

    Written from scratch for Frequency.
]]

local Class = require("modules/core/Class")

local SchemaV2 = Class.define("SchemaV2")

SchemaV2.VERSION = 2

function SchemaV2:initialize(logger)
    self.logger = logger
end

function SchemaV2.Matches(raw)
    return type(raw) == "table" and raw.schemaVersion == SchemaV2.VERSION
end

local function asNumber(value, fallback)
    local parsed = tonumber(value)
    return parsed or fallback
end

function SchemaV2:Normalize(raw, folderName)
    local displayName = raw.displayName
    if type(displayName) ~= "string" or displayName == "" then
        self.logger:Warnf("Station in folder \"%s\" has an invalid displayName; using the folder name instead.", folderName)
        displayName = folderName
    end

    local icon = raw.icon
    if type(icon) ~= "string" or icon == "" then
        icon = "default"
    end

    local customIcon = raw.customIcon
    if type(customIcon) ~= "table" then
        customIcon = { useCustom = false, inkAtlasPath = "", inkAtlasPart = "" }
    else
        customIcon = {
            useCustom = customIcon.useCustom == true,
            inkAtlasPath = type(customIcon.inkAtlasPath) == "string" and customIcon.inkAtlasPath or "",
            inkAtlasPart = type(customIcon.inkAtlasPart) == "string" and customIcon.inkAtlasPart or "",
        }
    end

    -- v2: a "stream" section with a non-empty url means this is a web stream.
    local stream = { isStream = false, url = "" }
    if type(raw.stream) == "table" and type(raw.stream.url) == "string" and raw.stream.url ~= "" then
        stream.isStream = true
        stream.url = raw.stream.url
    end

    local order = {}
    if type(raw.order) == "table" then
        for _, entry in ipairs(raw.order) do
            if type(entry) == "string" then
                table.insert(order, entry)
            end
        end
    end

    local songTitles = {}
    if type(raw.songTitles) == "table" then
        for file, title in pairs(raw.songTitles) do
            if type(file) == "string" and type(title) == "string" then
                songTitles[file] = title
            end
        end
    end

    local group = ""
    if type(raw.group) == "string" then
        group = raw.group
    end

    return {
        schemaVersion = SchemaV2.VERSION,
        displayName = displayName,
        fm = asNumber(raw.fm, 0),
        volume = asNumber(raw.volume, 1.0),
        icon = icon,
        customIcon = customIcon,
        stream = stream,
        order = order,
        group = group,
        songTitles = songTitles,
    }, false
end

--- v2 files are never rewritten by the mod.
function SchemaV2:FillMissing(_, _)
    return false
end

return SchemaV2
