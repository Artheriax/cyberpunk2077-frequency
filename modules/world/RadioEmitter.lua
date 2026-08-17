--[[
    Frequency - RadioEmitter.lua

    One physical in-world radio (the stereos and TVs placed around Night
    City) that is currently playing a custom station. Owns one 3D audio
    channel and pushes its world position to the native plugin every frame.

    Written from scratch for Frequency.
]]

local Class = require("modules/core/Class")

local RadioEmitter = Class.define("RadioEmitter")

function RadioEmitter:initialize(context)
    -- context: { audio }
    self.audio = context.audio

    self.handle = nil       -- game object (the radio entity)
    self.channel = 0        -- 3D channel id (1..N)
    self.station = nil
end

function RadioEmitter:Start(station, channel, handle)
    self.station = station
    self.channel = channel
    self.handle = handle
    self.station:Activate(self.channel)
end

function RadioEmitter:Stop()
    if self.station then
        self.station:Deactivate(self.channel)
    end
    self.handle = nil
end

function RadioEmitter:SwitchTo(station)
    if self.station then
        self.station:Deactivate(self.channel)
    end
    self.station = station
    self.station:Activate(self.channel)
end

function RadioEmitter:Update()
    if self.handle then
        self.audio:SetChannelPosition(self.channel, self.handle:GetWorldPosition())
    end
end

function RadioEmitter:Matches(handle)
    if self.handle == nil or handle == nil then
        return false
    end
    return Game["OperatorEqual;IScriptableIScriptable;Bool"](self.handle, handle)
end

return RadioEmitter
