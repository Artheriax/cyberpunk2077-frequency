--[[
    Frequency - AudioEngine.lua

    Audioware playback facade. All station audio plays through the game's
    own audio system (Audioware-registered sounds), so the game applies
    volume sliders, ducking, and muting itself. This module translates
    logical channels into manifest sound ids and tracks what plays where.

    Channel convention:
      -1        -> the vehicle / pocket radio (2D playback)
       1..N     -> reserved for physical world radios (emitters, not yet
                   ported in this branch)

    Written from scratch for Frequency.
]]

local Class = require("modules/core/Class")
local SoundId = require("modules/audio/SoundId")

local AudioEngine = Class.define("AudioEngine")

AudioEngine.VEHICLE_CHANNEL = -1

function AudioEngine:initialize(nativeBridge, logger)
    self.native = nativeBridge
    self.logger = logger
    self.audioSystem = nil
    self.currentSound = {} -- channel -> manifest sound id
end

--- Lazily resolves the game's audio system. CET exposes it as a zero
--- parameter static (the GameInstance is supplied by CET itself).
function AudioEngine:GetAudioSystem()
    if self.audioSystem == nil then
        local ok, system = pcall(Game.GetAudioSystem)
        if ok and system ~= nil then
            self.audioSystem = system
        end
    end
    return self.audioSystem
end

--- Starts playback on a channel.
--- @param channel number logical channel id
--- @param manifestPath string depot-relative path of the song
---        ("radios\\<station>\\<file>" or "legacy\\<station>\\<file>")
--- @param startPosMs number desired join position; not supported by the
---        base Audioware API yet, songs start from the beginning
--- @param volume number station volume multiplier (baked into the
---        manifest at generation time)
--- @param fade number unused (the game handles fades)
--- @param force boolean|nil unused
function AudioEngine:Play(channel, manifestPath, startPosMs, volume, fade, force)
    local system = self:GetAudioSystem()
    if system == nil then
        self.logger:Warnf("Audio system unavailable; cannot play \"%s\".", tostring(manifestPath))
        return false
    end

    local soundId = SoundId.FromPath(manifestPath)
    local ok, err = pcall(function()
        system:Play(CName.new(soundId))
    end)
    if not ok then
        self.logger:Warnf("Failed to play \"%s\": %s", soundId, tostring(err))
        return false
    end

    self.currentSound[channel] = soundId
    if startPosMs and startPosMs > 0 then
        self.logger:Debugf("Mid-song join (%d ms) not supported yet; \"%s\" starts from the beginning.",
            startPosMs, soundId)
    end
    return true
end

function AudioEngine:Stop(channel)
    local soundId = self.currentSound[channel]
    if soundId == nil then
        return
    end

    local system = self:GetAudioSystem()
    if system ~= nil then
        pcall(function()
            system:Stop(CName.new(soundId))
        end)
    end
    self.currentSound[channel] = nil
end

--- The game applies volume itself (Audioware tracks the sliders).
function AudioEngine:SetVolume(_, _)
end

--- World-radio spatialization: handled by Audioware emitters (future).
function AudioEngine:SetListener(_, _, _)
end

function AudioEngine:SetChannelPosition(_, _)
end

function AudioEngine:IsChannelActive(channel)
    return self.currentSound[channel] ~= nil
end

--- Song length probing for the station simulation (header parsing in the
--- native plugin).
function AudioEngine:GetSongLengthMs(absoluteModRelativePath)
    local native = self.native:Get()
    if native == nil then
        return 0
    end
    local ok, length = pcall(native.ProbeDuration, absoluteModRelativePath)
    if ok and type(length) == "number" then
        return length
    end
    return 0
end

--- Physical world radios are not implemented in this branch.
function AudioEngine:GetChannelCount()
    return 0
end

function AudioEngine:Update(_)
    -- The game's audio engine needs no per-frame pumping from us.
end

return AudioEngine
