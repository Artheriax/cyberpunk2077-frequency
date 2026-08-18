--[[
    Frequency - AudioEngine.lua

    Audioware playback facade. All station audio plays through the game's
    own audio system (Audioware-registered sounds), so the game applies
    volume sliders, ducking, and muting itself.

    Playback prefers `DynamicSoundEvent` handles (per-sound stop/seek/
    volume) and falls back to name-based Play/Stop when the handle API is
    not reachable from CET.

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
    self.handlesUnavailable = false
    self.currentSound = {} -- channel -> { id, handle, appliedWheel }
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

--- Creates a DynamicSoundEvent handle for a manifest sound id, or nil when
--- the API is not reachable from CET. Several RTTI call forms are tried.
function AudioEngine:CreateSoundEvent(soundId)
    if self.handlesUnavailable then
        return nil
    end

    local attempts = {
        function() return Game["DynamicSoundEvent;Create"](CName.new(soundId), nil) end,
        function() return Game["DynamicSoundEvent;Create"](CName.new(soundId)) end,
        function() return Game["DynamicSoundEvent;Create;CName;handle:AudioSettingsExt"](CName.new(soundId), nil) end,
    }
    for _, fn in ipairs(attempts) do
        local ok, result = pcall(fn)
        if ok and result ~= nil then
            return result
        end
    end

    self.handlesUnavailable = true
    return nil
end

--- Starts playback on a channel.
--- @param channel number logical channel id
--- @param manifestPath string depot-relative path of the song
---        ("radios\\<station>\\<file>" or "legacy\\<station>\\<file>")
--- @param startPosMs number desired join position in milliseconds
--- @param volume number station volume multiplier (baked into the
---        manifest at generation time; only kept for reference here)
--- @param fade number unused (the game handles fades)
--- @param force boolean|nil unused
function AudioEngine:Play(channel, manifestPath, startPosMs, volume, fade, force)
    local system = self:GetAudioSystem()
    if system == nil then
        self.logger:Warnf("Audio system unavailable; cannot play \"%s\".", tostring(manifestPath))
        return false
    end

    local soundId = SoundId.FromPath(manifestPath)
    self:Stop(channel)

    local handle = self:CreateSoundEvent(soundId)
    if handle ~= nil then
        local ok, queued = pcall(function()
            GetPlayer():QueueEvent(handle)
        end)
        if ok then
            self.currentSound[channel] = { id = soundId, handle = handle, appliedWheel = nil }
            if startPosMs and startPosMs > 0 then
                pcall(function()
                    handle:SeekTo(startPosMs / 1000)
                end)
            end
            return true
        end

        self.handlesUnavailable = true
        self.logger:Infof("Sound handles could not be queued (%s); falling back to name-based playback.", tostring(queued))
    end

    local ok, err = pcall(function()
        system:Play(CName.new(soundId))
    end)
    if not ok then
        self.logger:Warnf("Failed to play \"%s\": %s", soundId, tostring(err))
        return false
    end

    self.currentSound[channel] = { id = soundId }
    if startPosMs and startPosMs > 0 then
        self.logger:Debugf("Mid-song join (%d ms) not supported without handles; \"%s\" starts from the beginning.",
            startPosMs, soundId)
    end
    return true
end

function AudioEngine:Stop(channel)
    local entry = self.currentSound[channel]
    if entry == nil then
        return
    end
    self.currentSound[channel] = nil

    if entry.handle ~= nil then
        pcall(function()
            entry.handle:Stop()
        end)
    end

    -- Name-based stop is the guaranteed path (verified in the spike).
    local system = self:GetAudioSystem()
    if system ~= nil then
        pcall(function()
            system:Stop(CName.new(entry.id))
        end)
    end
end

--- Sets the per-play volume multiplier of the active handle. Used for the
--- radioport volume wheel; station volume is baked into the manifest.
function AudioEngine:SetVolume(channel, volume)
    local entry = self.currentSound[channel]
    if entry == nil or entry.handle == nil then
        return
    end
    pcall(function()
        entry.handle:SetVolume(volume)
    end)
end

--- Polls the pocket radio's own volume wheel and applies it to the active
--- vehicle-channel handle. No-op when the wheel value is not readable.
function AudioEngine:UpdateVehicleVolume()
    local entry = self.currentSound[AudioEngine.VEHICLE_CHANNEL]
    if entry == nil or entry.handle == nil then
        return
    end

    local ok, wheel = pcall(function()
        local player = GetPlayer()
        local pocket = player and player:GetPocketRadio()
        return pocket and pocket.volume
    end)
    if not ok or type(wheel) ~= "number" then
        return
    end
    if wheel > 1 then
        wheel = wheel / 100
    end
    if entry.appliedWheel ~= wheel then
        entry.appliedWheel = wheel
        self:SetVolume(AudioEngine.VEHICLE_CHANNEL, math.max(wheel, 0.01))
    end
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
