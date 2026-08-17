--[[
    Frequency - WorldRadioManager.lua

    Manages all physical in-world radios: assigns each active device a 3D
    channel, updates positions and the listener transform, and cleans up
    emitters when a device turns off, loses power, or streams out.

    Written from scratch for Frequency.
]]

local Class = require("modules/core/Class")
local RadioEmitter = require("modules/world/RadioEmitter")

local WorldRadioManager = Class.define("WorldRadioManager")

function WorldRadioManager:initialize(context)
    -- context: { logger, audio, registry }
    self.logger = context.logger
    self.audio = context.audio
    self.registry = context.registry

    self.emitters = {}        -- channel -> RadioEmitter
    self.cameraTransform = Transform.new()
end

function WorldRadioManager:FindEmitter(handle)
    for _, emitter in pairs(self.emitters) do
        if emitter:Matches(handle) then
            return emitter
        end
    end
    return nil
end

function WorldRadioManager:Acquire(station, handle)
    for channel = 1, self.audio:GetChannelCount() do
        if self.emitters[channel] == nil then
            local emitter = RadioEmitter({ audio = self.audio })
            emitter:Start(station, channel, handle)
            self.emitters[channel] = emitter
            return emitter
        end
    end

    self.logger:Error("No free 3D channels left (too many physical radios playing).")
    return nil
end

function WorldRadioManager:Release(handle)
    local emitter = self:FindEmitter(handle)
    if emitter then
        emitter:Stop()
        self.emitters[emitter.channel] = nil
    end
end

function WorldRadioManager:ReleaseAll()
    for _, emitter in pairs(self.emitters) do
        emitter:Stop()
    end
    self.emitters = {}
end

function WorldRadioManager:Update()
    for _, emitter in pairs(self.emitters) do
        emitter.station:Activate(emitter.channel) -- no-op when already active
        emitter:Update()
    end

    if next(self.emitters) == nil then
        return
    end

    Game.GetCameraSystem():GetActiveCameraWorldTransform(self.cameraTransform)
    self.audio:SetListener(self.cameraTransform.position, GetPlayer():GetWorldForward(), GetPlayer():GetWorldUp())
end

function WorldRadioManager:HandleMenu()
    for _, emitter in pairs(self.emitters) do
        emitter.station:Deactivate(emitter.channel)
    end
end

return WorldRadioManager
