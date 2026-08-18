--[[
    Frequency - AudioEngine.lua

    Audioware playback facade. All station audio plays through the game's
    own audio system (Audioware-registered sounds), so the game applies
    volume sliders, ducking, and muting itself.

    Playback prefers `DynamicSoundEvent` handles (per-sound stop/seek/
    volume) and falls back to name-based Play/Stop when the handle API is
    not reachable from CET.

    Volume model:
      - Audioware manifest `settings.volume` is in DECIBELS; the baked
        manifest value covers stations for the name-based fallback path.
      - Runtime `DynamicSoundEvent.SetVolume` takes a LINEAR amplitude
        (0..1); the handle path applies baseGain * radioport wheel there,
        which also makes gain changes apply without a restart.

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
    self.globalGain = 0.4
    self.currentSound = {} -- channel -> { id, handle, baseGain, applied }
end

function AudioEngine:SetGlobalGain(gain)
    self.globalGain = tonumber(gain) or 0.4
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
--- @param volume number station volume multiplier
--- @param fade number unused (the game handles fades)
--- @param force boolean|nil unused
function AudioEngine:Play(channel, manifestPath, startPosMs, volume, fade, force)
    local system = self:GetAudioSystem()
    if system == nil then
        self.logger:Warnf("Audio system unavailable; cannot play \"%s\".", tostring(manifestPath))
        return false
    end

    local soundId = SoundId.FromPath(manifestPath)
    local baseGain = (tonumber(volume) or 1.0) * self.globalGain
    self:Stop(channel)

    local handle = self:CreateSoundEvent(soundId)
    if handle ~= nil then
        local ok, queued = pcall(function()
            GetPlayer():QueueEvent(handle)
        end)
        if ok then
            self.currentSound[channel] = { id = soundId, handle = handle, baseGain = baseGain, applied = nil }

            if startPosMs and startPosMs > 0 then
                pcall(function()
                    handle:SeekTo(startPosMs / 1000)
                end)
            end

            -- Apply the base gain immediately; the radioport wheel is
            -- polled on top of it every frame.
            self:SetVolume(channel, baseGain)
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

--- Sets the per-play volume of the active handle (linear amplitude 0..1).
--- Used for the station/gain product and the radioport volume wheel.
function AudioEngine:SetVolume(channel, volume)
    local entry = self.currentSound[channel]
    if entry == nil or entry.handle == nil then
        return
    end
    local clamped = math.max(tonumber(volume) or 1.0, 0.0)
    pcall(function()
        entry.handle:SetVolume(clamped)
    end)
end

--- Mirrors the context-dependent radio volume settings var on top of the
--- station/gain base. The in-radioport volume wheel writes the settings
--- vars: CarRadioVolume while mounted (already applied by the Audioware
--- car_radio track) and RadioportVolume on foot (applied here).
function AudioEngine:UpdateVehicleVolume()
    local entry = self.currentSound[AudioEngine.VEHICLE_CHANNEL]
    if entry == nil or entry.handle == nil then
        return
    end

    local ok, mounted, slider = pcall(function()
        local player = GetPlayer()
        local isMounted = player ~= nil and player:GetMountedVehicle() ~= nil
        local varName = isMounted and "CarRadioVolume" or "RadioportVolume"
        local value = Game.GetSettingsSystem():GetVar("/audio/volume", varName):GetValue()
        return isMounted, value
    end)
    if not ok or type(slider) ~= "number" then
        return
    end

    local target
    if mounted then
        target = entry.baseGain
    else
        target = entry.baseGain * math.max(slider / 100, 0.01)
    end

    if entry.applied ~= target then
        entry.applied = target
        self:SetVolume(AudioEngine.VEHICLE_CHANNEL, target)
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
