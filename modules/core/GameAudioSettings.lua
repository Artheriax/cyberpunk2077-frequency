--[[
    Frequency - GameAudioSettings.lua

    Reads the game's own audio settings (car radio / radioport volume) so
    custom stations respect the sliders in the options menu.

    Written from scratch for Frequency.
]]

local Class = require("modules/core/Class")

local GameAudioSettings = Class.define("GameAudioSettings")

local GROUP = "/audio/volume"
local CAR_RADIO_VAR = "CarRadioVolume"
local POCKET_RADIO_VAR = "RadioportVolume"

function GameAudioSettings:initialize()
    -- no state
end

function GameAudioSettings:ReadVolume(varName)
    local ok, value = pcall(function()
        return Game.GetSettingsSystem():GetVar(GROUP, varName):GetValue()
    end)
    if ok and type(value) == "number" then
        return value
    end
    return 100
end

function GameAudioSettings:GetCarRadioVolume()
    return self:ReadVolume(CAR_RADIO_VAR)
end

function GameAudioSettings:GetPocketRadioVolume()
    return self:ReadVolume(POCKET_RADIO_VAR)
end

--- Picks the volume slider that matches the player's current context.
function GameAudioSettings:GetContextVolume()
    local ok, mounted = pcall(function()
        local player = GetPlayer()
        return player and player:GetMountedVehicle()
    end)
    if ok and mounted then
        return self:GetCarRadioVolume()
    end
    return self:GetPocketRadioVolume()
end

return GameAudioSettings
