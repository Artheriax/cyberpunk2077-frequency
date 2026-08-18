--[[
    Frequency - Manifest.lua

    Regenerates the Audioware manifest
    (r6\audioware\Frequency\audios.yml) from the loaded station list, with
    each station's volume multiplier baked into its song entries.
    Audioware registers sounds at game startup, so manifest changes apply
    on the next launch. The native plugin writes a baseline manifest
    (volume 1.0) at plugin load, so freshly installed stations already
    work on the very first launch.

    Written from scratch for Frequency.
]]

local Class = require("modules/core/Class")
local SoundId = require("modules/audio/SoundId")

local Manifest = Class.define("Manifest")

-- Native paths are bin/x64-relative; this reaches the game root.
Manifest.PATH = "..\\..\\r6\\audioware\\Frequency\\audios.yml"

local function quoteYaml(text)
    return "\"" .. tostring(text):gsub("\\", "\\\\"):gsub("\"", "\\\"") .. "\""
end

function Manifest:initialize(files, logger)
    self.files = files
    self.logger = logger
end

--- Rewrites the manifest from the given station list. Depot-relative song
--- paths use forward slashes (Audioware convention).
function Manifest:Generate(stations)
    local lines = { "version: 1.0.0", "jingles:" }
    local seen = {}
    local count = 0

    for _, station in ipairs(stations) do
        local volume = tonumber(station:GetVolume()) or 1.0
        for _, song in ipairs(station.songs) do
            local relative = station.manifestFolder .. "/" .. song.path:gsub("\\", "/")
            local id = SoundId.FromPath(relative)
            if not seen[id] then
                seen[id] = true
                table.insert(lines, "  " .. id .. ":")
                table.insert(lines, "    file: " .. quoteYaml(relative))
                table.insert(lines, "    captions: []")
                table.insert(lines, "    settings:")
                table.insert(lines, ("      volume: %s"):format(tostring(volume)))
                count = count + 1
            end
        end
    end

    local native = self.files:Native()
    if native == nil then
        self.logger:Warn("Cannot regenerate the Audioware manifest: native plugin missing.")
        return false
    end

    local ok, written = pcall(native.WriteText, Manifest.PATH, table.concat(lines, "\n") .. "\n")
    if not ok or written ~= true then
        self.logger:Warnf("Failed to write the Audioware manifest: %s", tostring(written))
        return false
    end

    self.logger:Infof("Audioware manifest written with %d song(s). Volume changes apply after a restart.", count)
    return true
end

return Manifest
