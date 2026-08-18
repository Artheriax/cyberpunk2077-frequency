--[[
    Frequency - AudioEngine.lua

    Lua-side audio facade. Translates logical channels into native calls,
    applies the game's volume sliders, and rate-limits play requests per
    channel so the native side never gets spammed while a stream is loading.

    Channel convention:
      -1        -> the vehicle / pocket radio (2D playback)
       1..N     -> physical radios placed in the world (3D playback)

    Written from scratch for Frequency.
]]

local Class = require("modules/core/Class")

local AudioEngine = Class.define("AudioEngine")

AudioEngine.VEHICLE_CHANNEL = -1

local PLAY_COOLDOWN = 1.0 -- seconds, per channel

function AudioEngine:initialize(nativeBridge, settings, logger)
    self.native = nativeBridge
    self.settings = settings
    self.logger = logger
    self.lastPlayAt = {}
end

function AudioEngine:ComputeVolume(channel, stationVolume)
    local volume = tonumber(stationVolume) or 1.0

    -- The game's Wwise mix applies master volume on top of the radio
    -- sliders; our separate FMOD system must mirror both manually.
    volume = volume * (self.settings:GetMasterVolume() / 100)

    if channel == AudioEngine.VEHICLE_CHANNEL then
        volume = volume * (self.settings:GetContextVolume() / 100)
    else
        volume = volume * 0.7
    end

    return volume * 0.4
end

--- Starts playback on a channel.
--- @param channel number logical channel id
--- @param path string file path (relative to bin/x64) or stream URL
--- @param startPosMs number start offset in milliseconds, or -1 for streams
--- @param stationVolume number station volume multiplier
--- @param fade number fade-in duration in seconds
--- @param force boolean|nil bypass the per-channel cooldown
function AudioEngine:Play(channel, path, startPosMs, stationVolume, fade, force)
    local now = os.clock()
    local last = self.lastPlayAt[channel] or 0
    if not force and (now - last) < PLAY_COOLDOWN then
        return false
    end
    self.lastPlayAt[channel] = now

    self.native:Get().Play(channel, path, math.floor(startPosMs), self:ComputeVolume(channel, stationVolume), fade or 0.75)
    return true
end

function AudioEngine:Stop(channel)
    self.lastPlayAt[channel] = 0
    self.native:Get().Stop(channel)
end

function AudioEngine:SetVolume(channel, stationVolume)
    self.native:Get().SetVolume(channel, self:ComputeVolume(channel, stationVolume))
end

function AudioEngine:SetListener(pos, forward, up)
    self.native:Get().SetListener(pos, forward, up)
end

function AudioEngine:SetChannelPosition(channel, pos)
    self.native:Get().SetChannelPos(channel, pos)
end

function AudioEngine:IsChannelActive(channel)
    local native = self.native:Get()
    if native.IsChannelActive then
        local ok, active = pcall(native.IsChannelActive, channel)
        if ok then
            return active == true
        end
    end
    return false
end

function AudioEngine:GetSongLengthMs(absoluteModRelativePath)
    return self.native:Get().GetSongLength(absoluteModRelativePath)
end

function AudioEngine:GetChannelCount()
    return self.native:Get().GetNumChannels()
end

function AudioEngine:Update(_)
    -- Reserved for future per-frame work (native side polls FMOD itself).
end

return AudioEngine
