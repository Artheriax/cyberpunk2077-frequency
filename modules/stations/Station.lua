--[[
    Frequency - Station.lua

    One radio station: its TweakDB record, its playlist, and the background
    "radio simulation" that keeps track of what would be playing even when
    nobody is listening, so a radio switched on mid-song joins in progress.

    Written from scratch for Frequency.
]]

local Class = require("modules/core/Class")
local ModPaths = require("modules/core/ModPaths")

local Station = Class.define("Station")

-- The game ships 13 vanilla stations; custom indices start after them.
Station.VANILLA_STATION_COUNT = 13

local SONG_END_GUARD_SECONDS = 15 -- join mid-song, but not in the last 15s

function Station:initialize(context)
    -- context: { logger, scheduler, audio, songTitles (optional) }
    self.logger = context.logger
    self.scheduler = context.scheduler
    self.audio = context.audio

    self.id = nil             -- folder name, unique
    self.source = "own"       -- "own" | "legacy" (imported from radioExt)
    self.config = nil         -- normalized metadata (see MetadataLoader)
    self.songs = {}           -- array of { path, length } (length in seconds)
    self.orderedSongs = {}
    self.shuffleBag = {}

    self.index = 0            -- game radio index (>= 14)
    self.recordId = nil       -- TweakDB record name
    self.iconRecord = nil

    self.currentSong = nil
    self.elapsed = 0
    self.channels = {}        -- channelId -> bool
    self.simTimer = nil
end

-- ---------------------------------------------------------------------------
-- Properties
-- ---------------------------------------------------------------------------

function Station:GetName() return self.config.displayName end
function Station:GetFm() return self.config.fm end
function Station:GetVolume() return self.config.volume end
function Station:GetGroup() return self.config.group or "" end
function Station:IsStream() return self.config.stream.isStream end
function Station:GetStreamUrl() return self.config.stream.url end
function Station:GetSongCount() return #self.songs end
function Station:IsActiveOn(channel) return self.channels[channel] == true end
function Station:GetIndex() return self.index end
function Station:GetRecordId() return self.recordId end

function Station:GetCurrentTrackName()
    if self.currentSong == nil then
        return ""
    end
    if self:IsStream() then
        return self:GetName()
    end
    local fileName = self.currentSong.path:match("([^\\]+)$") or self.currentSong.path
    local title = self.config.songTitles and self.config.songTitles[fileName]
    if title then
        return title
    end
    return (fileName:match("(.+)%..+$")) or fileName
end

-- ---------------------------------------------------------------------------
-- Loading
-- ---------------------------------------------------------------------------

function Station:Load(config, songs, stationId, position, source)
    self.config = config
    self.id = stationId
    self.source = source or "own"
    self.index = Station.VANILLA_STATION_COUNT + position

    for _, song in ipairs(songs) do
        table.insert(self.songs, song)
    end

    self:CreateOrUpdateRecord()
    self:BuildOrderedList()

    -- Channel -1 is the vehicle/pocket radio, 1..N are physical radios.
    self.channels[-1] = false
    for channel = 1, self.audio:GetChannelCount() do
        self.channels[channel] = false
    end

    if self:IsStream() then
        self.currentSong = { path = self:GetName(), length = 0 }
        self.logger:Infof("Station \"%s\" is a web stream (%s).", self:GetName(), self:GetStreamUrl())
    elseif #self.songs == 0 then
        self.logger:Warnf("Station \"%s\" has no song files and is not a stream; it will show up but stay silent.", self:GetName())
        self.currentSong = { path = "silent", length = 999999 }
    else
        self:StartSimulation()
    end
end

function Station:CreateOrUpdateRecord()
    local config = self.config

    local iconRecord = config.icon
    if iconRecord == "default" then
        iconRecord = "UIIcon.RadioHipHop"
    end

    -- Suffix prevents collisions with vanilla records of the same name.
    local recordId = "RadioStation.freq_" .. self.id
    self.recordId = recordId

    if TweakDBInterface.GetRadioStationRecord(recordId) == nil then
        TweakDB:CloneRecord(recordId, "RadioStation.Pop")
    end
    TweakDB:SetFlat(recordId .. ".displayName", self:GetName())
    TweakDB:SetFlat(recordId .. ".icon", iconRecord)
    TweakDB:SetFlat(recordId .. ".index", self.index)
    CName.add(self:GetName())

    if config.customIcon.useCustom then
        local iconId = "UIIcon.freq_" .. self.id
        if TweakDBInterface.GetUIIconRecord(iconId) == nil then
            TweakDB:CloneRecord(iconId, "UIIcon.ICEMinor")
        end
        TweakDB:SetFlat(iconId .. ".atlasResourcePath", config.customIcon.inkAtlasPath)
        TweakDB:SetFlat(iconId .. ".atlasPartName", config.customIcon.inkAtlasPart)
        TweakDB:SetFlat(recordId .. ".icon", iconId)
        iconRecord = iconId
    end

    self.iconRecord = iconRecord
end

function Station:BuildOrderedList()
    self.orderedSongs = {}
    for _, fileName in ipairs(self.config.order) do
        local found = nil
        for _, song in ipairs(self.songs) do
            if song.path == self.id .. "\\" .. fileName then
                found = song
                break
            end
        end
        if found == nil then
            self.logger:Warnf("Station \"%s\": file \"%s\" from the order list does not exist.", self:GetName(), fileName)
        else
            table.insert(self.orderedSongs, found)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Radio simulation
-- ---------------------------------------------------------------------------

local function shallowCopySongList(list)
    local copy = {}
    for _, song in ipairs(list) do
        table.insert(copy, song)
    end
    return copy
end

function Station:RebuildShuffleBag()
    self.shuffleBag = {}

    local pool = shallowCopySongList(self.songs)
    for _, ordered in ipairs(self.orderedSongs) do
        for i, song in ipairs(pool) do
            if song == ordered then
                table.remove(pool, i)
                break
            end
        end
    end

    while #pool > 0 do
        local pick = math.random(#pool)
        table.insert(self.shuffleBag, pool[pick])
        table.remove(pool, pick)
    end

    -- Insert the ordered block at a random position.
    local insertAt = math.random(#self.shuffleBag + 1)
    for i = #self.orderedSongs, 1, -1 do
        table.insert(self.shuffleBag, insertAt, self.orderedSongs[i])
    end
end

function Station:StartSimulation()
    self:RebuildShuffleBag()
    if #self.shuffleBag == 0 then
        self.logger:Warnf("Station \"%s\": nothing to simulate (empty playlist).", self:GetName())
        self.currentSong = { path = "silent", length = 999999 }
        self.elapsed = 0
        return
    end

    self.currentSong = table.remove(self.shuffleBag, 1)
    local maxStart = math.max(self.currentSong.length - SONG_END_GUARD_SECONDS, 1)
    self.elapsed = math.random(maxStart) - 1

    self.simTimer = self.scheduler:Every(1, function()
        self:TickSimulation()
    end)
end

function Station:TickSimulation()
    if self.currentSong == nil then
        return
    end

    self.elapsed = self.elapsed + 1
    if self.elapsed < self.currentSong.length then
        return
    end

    self:StopAllChannels()

    if #self.shuffleBag == 0 then
        self:RebuildShuffleBag()
    end
    if #self.shuffleBag == 0 then
        return
    end

    self.currentSong = table.remove(self.shuffleBag, 1)
    self.elapsed = 0

    for channel, active in pairs(self.channels) do
        if active then
            local ch = channel
            self.scheduler:After(0.05, function()
                self:PlayCurrentOn(ch)
            end)
        end
    end

    self:RefreshRadioUi()
end

function Station:StopSimulation()
    if self.simTimer then
        self.scheduler:Cancel(self.simTimer)
        self.simTimer = nil
    end
end

-- ---------------------------------------------------------------------------
-- Playback
-- ---------------------------------------------------------------------------

function Station:ResolveSongPath()
    if self.source == "legacy" then
        return ModPaths.NativeRelativeLegacy(ModPaths.RadiosFolder .. "\\" .. self.currentSong.path)
    end
    return ModPaths.NativeRelative(ModPaths.RadiosFolder .. "\\" .. self.currentSong.path)
end

function Station:PlayCurrentOn(channel)
    if self:IsStream() then
        self.logger:Debugf("Playing stream \"%s\" on channel %d.", self:GetName(), channel)
        self.audio:Play(channel, self:GetStreamUrl(), -1, self:GetVolume())
    else
        self.audio:Play(channel, self:ResolveSongPath(), self.elapsed * 1000, self:GetVolume())
    end
end

function Station:Activate(channel, updateUi)
    if self.channels[channel] then
        return
    end
    self.channels[channel] = true
    self.logger:Debugf("Station \"%s\" activated on channel %d (track: %s, position: %.1fs).",
        self:GetName(), channel, tostring(self.currentSong and self.currentSong.path), self.elapsed)
    self:PlayCurrentOn(channel)

    if updateUi ~= false then
        self:RefreshRadioUi()
    end
end

function Station:Deactivate(channel)
    if not self.channels[channel] then
        return
    end
    self.channels[channel] = false
    self.audio:Stop(channel)
end

function Station:StopAllChannels()
    for channel, active in pairs(self.channels) do
        if active then
            self.audio:Stop(channel)
        end
    end
end

function Station:UpdateVolume(channel)
    self.audio:SetVolume(channel, self:GetVolume())
end

function Station:RefreshRadioUi()
    if not self.channels[-1] then
        return
    end
    Game.GetUISystem():QueueEvent(UIVehicleRadioEvent.new())
    self.scheduler:After(0.1, function()
        Game.GetUISystem():QueueEvent(VehicleRadioSongChanged.new())
    end)
end

--- Full teardown, used before a hot reload or on session end.
function Station:Dispose()
    self:StopSimulation()
    for channel, active in pairs(self.channels) do
        if active then
            self.audio:Stop(channel)
            self.channels[channel] = false
        end
    end
end

return Station
