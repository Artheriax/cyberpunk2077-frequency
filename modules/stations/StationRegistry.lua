--[[
    Frequency - StationRegistry.lua

    Discovers station folders, loads their metadata and songs, builds the
    Station objects, and owns the master list. Supports hot reload: Reload()
    tears every station down and rebuilds the list from disk without
    restarting the game.

    Written from scratch for Frequency.
]]

local Class = require("modules/core/Class")
local ModPaths = require("modules/core/ModPaths")
local Station = require("modules/stations/Station")

local StationRegistry = Class.define("StationRegistry")

local SONG_EXTENSIONS = {
    [".mp3"] = true, [".mp2"] = true, [".flac"] = true, [".ogg"] = true,
    [".wav"] = true, [".wax"] = true, [".wma"] = true, [".opus"] = true,
    [".aiff"] = true, [".aif"] = true, [".aifc"] = true,
}

function StationRegistry:initialize(context)
    -- context: { logger, files, audio, scheduler, metadataLoader, groupConfig, modConfig }
    self.logger = context.logger
    self.files = context.files
    self.audio = context.audio
    self.scheduler = context.scheduler
    self.metadataLoader = context.metadataLoader
    self.groupConfig = context.groupConfig
    self.modConfig = context.modConfig

    self.stations = {}
    self.legacyImportUsed = false
end

-- ---------------------------------------------------------------------------
-- Discovery helpers
-- ---------------------------------------------------------------------------

function StationRegistry:IsSongFile(fileName)
    local extension = fileName:match("^.+(%..+)$")
    return extension ~= nil and SONG_EXTENSIONS[extension:lower()] == true
end

--- Measures every song file in one station folder.
--- @param stationPath string game-root-relative folder (native plugin IO)
--- @return array of { path = "folder\\file", length = seconds }
function StationRegistry:MeasureSongs(stationId, stationPath)
    local songs = {}

    for _, fileName in ipairs(self.files:ListFiles(stationPath)) do
        if self:IsSongFile(fileName) then
            local nativePath = stationPath .. "\\" .. fileName
            local lengthMs = self.audio:GetSongLengthMs(nativePath)
            if lengthMs ~= 0 then
                table.insert(songs, { path = stationId .. "\\" .. fileName, length = lengthMs / 1000 })
            else
                self.logger:Warnf("Could not read song \"%s\" of station \"%s\"; skipping it.", fileName, stationId)
            end
        end
    end

    table.sort(songs, function(a, b) return a.path < b.path end)
    return songs
end

--- Loads one station folder. Returns a Station or nil + error.
function StationRegistry:LoadOne(stationId, position, source)
    -- All station IO goes through the native plugin with game-root-relative
    -- paths: CET's sandboxed io cannot reach folders outside this mod, so
    -- the legacy radioExt root would be unreadable any other way.
    local modFolder = source == "legacy" and ModPaths.LegacyModFolder or ModPaths.ModFolder
    local stationPath = "plugins\\cyber_engine_tweaks\\mods\\" .. modFolder .. "\\" .. ModPaths.RadiosFolder .. "\\" .. stationId

    local metadataPath = stationPath .. "\\metadata.json"
    if not self.files:Exists(metadataPath) then
        return nil, "no metadata.json found"
    end

    local config, err = self.metadataLoader:Load(metadataPath, stationId)
    if config == nil then
        return nil, err
    end

    self.groupConfig:Register(config.group)
    if not self.groupConfig:IsEnabled(config.group) then
        return nil, ("group \"%s\" is disabled"):format(config.group)
    end

    -- Web streams are not supported by the Audioware backend.
    if config.stream.isStream then
        return nil, "web streams are not supported by the Audioware backend"
    end

    local songs = self:MeasureSongs(stationId, stationPath)

    local station = Station({
        logger = self.logger,
        scheduler = self.scheduler,
        audio = self.audio,
    })

    local ok, loadErr = pcall(function()
        station:Load(config, songs, stationId, position, source)
    end)
    if not ok then
        station:Dispose()
        return nil, tostring(loadErr)
    end

    return station
end

-- ---------------------------------------------------------------------------
-- Master list
-- ---------------------------------------------------------------------------

--- Scans a radios root and appends loadable stations. Returns the count.
function StationRegistry:ScanRoot(nativeRootLabel, source)
    local folderNames = self.files:ListSubfolders(nativeRootLabel)
    if #folderNames == 0 then
        return 0
    end

    local loaded = 0
    for _, stationId in ipairs(folderNames) do
        -- A failed station must never take the rest of the list down with it.
        local station, err = self:LoadOne(stationId, #self.stations + 1, source)
        if station then
            table.insert(self.stations, station)
            loaded = loaded + 1
            local kind = station:IsStream() and "stream" or "file"
            self.logger:Infof("Loaded station \"%s\" (FM %s, %d song(s), %s, index %d%s).",
                station:GetName(), tostring(station:GetFm()), station:GetSongCount(), kind,
                station:GetIndex(), source == "legacy" and ", imported from radioExt" or "")
        else
            self.logger:Warnf("Skipped station folder \"%s\": %s.", stationId, tostring(err))
        end
    end

    return loaded
end

--- Full (re)build of the station list from disk.
function StationRegistry:LoadAll()
    self.stations = {}
    self.legacyImportUsed = false

    local ownRoot = "plugins\\cyber_engine_tweaks\\mods\\" .. ModPaths.ModFolder .. "\\" .. ModPaths.RadiosFolder
    local ownCount = self:ScanRoot(ownRoot, "own")
    if ownCount == 0 then
        self.logger:Info("No stations found in the Frequency radios folder.")
    end

    -- Drop-in compatibility: import stations from a legacy radioExt install.
    if self.modConfig.importLegacyRadioExt then
        local legacyRoot = "plugins\\cyber_engine_tweaks\\mods\\" .. ModPaths.LegacyModFolder .. "\\" .. ModPaths.RadiosFolder
        local legacyCount = self:ScanRoot(legacyRoot, "legacy")
        if legacyCount > 0 then
            self.legacyImportUsed = true
            self.logger:Infof("Imported %d station(s) from the legacy radioExt folder.", legacyCount)
        end
    end

    self:SortByIndex()
    self:WriteAudioManifest()
    self.logger:Infof("%d station(s) active.", #self.stations)
end

--- Regenerates the Audioware manifest so song lists and station volumes
--- are correct on the next game launch.
function StationRegistry:WriteAudioManifest()
    local Manifest = require("modules/audio/Manifest")
    Manifest({ files = self.files, logger = self.logger }):Generate(self.stations)
end

function StationRegistry:SortByIndex()
    table.sort(self.stations, function(a, b) return a:GetIndex() < b:GetIndex() end)
end

--- Hot reload: stop everything, re-read every folder, rebuild the list.
function StationRegistry:Reload()
    self.logger:Info("Hot reload requested - rebuilding station list...")
    self:DisposeAll()
    self.groupConfig:Load()
    self.modConfig:Load()
    self:LoadAll()
end

-- ---------------------------------------------------------------------------
-- Lookups
-- ---------------------------------------------------------------------------

function StationRegistry:All()
    return self.stations
end

function StationRegistry:Count()
    return #self.stations
end

function StationRegistry:GetByName(name)
    for _, station in ipairs(self.stations) do
        if station:GetName() == name then
            return station
        end
    end
    return nil
end

function StationRegistry:GetByIndex(index)
    for _, station in ipairs(self.stations) do
        if station:GetIndex() == index then
            return station
        end
    end
    return nil
end

function StationRegistry:GetAtPosition(position)
    return self.stations[position]
end

--- Data about the station currently playing on the vehicle channel, if any.
function StationRegistry:GetActiveVehicleStation()
    for _, station in ipairs(self.stations) do
        if station:IsActiveOn(-1) then
            return {
                station = station:GetName(),
                track = station.currentSong and station.currentSong.path or "",
                trackName = station:GetCurrentTrackName(),
                isStream = station:IsStream(),
                index = station:GetIndex(),
            }
        end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

--- Stops playback on every channel of every station (session end, shutdown).
function StationRegistry:StopAllPlayback()
    for _, station in ipairs(self.stations) do
        for channel, active in pairs(station.channels) do
            if active then
                station:Deactivate(channel)
            end
        end
    end
end

--- Full teardown including simulations. Used before a hot reload.
function StationRegistry:DisposeAll()
    for _, station in ipairs(self.stations) do
        station:Dispose()
    end
    self.stations = {}
end

return StationRegistry
