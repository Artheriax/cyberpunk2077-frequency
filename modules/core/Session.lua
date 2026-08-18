--[[
    Frequency - Session.lua

    Tracks the player's current game state: inside a loaded session, in a
    menu, in a braindance, in a Johnny sequence, or on a loading screen.
    Other systems subscribe through OnSessionStart / OnSessionEnd and gate
    their per-frame work behind ShouldMuteAudio().

    Custom audio runs on its own audio engine, so it cannot rely on the
    game's mix to duck or mute it. The states tracked here are exactly the
    ones where the game silences the world, and Frequency mirrors them
    manually.

    Written from scratch for Frequency.
]]

local Class = require("modules/core/Class")

local Session = Class.define("Session")

function Session:initialize()
    self.inGame = false
    self.inMenu = false
    self.inBraindance = false
    self.inFlashback = false
    self.inLoading = false

    self.fastTravelStart = nil

    self.startCallbacks = {}
    self.endCallbacks = {}
end

--- Registers game hooks. Must be called from onInit, not at load time:
--- CET only exposes `Observe` to mods after all init.lua files have run.
function Session:RegisterHooks()
    Observe("RadialWheelController", "OnIsInMenuChanged", function(_, isInMenu)
        self.inMenu = isInMenu and true or false
    end)

    Observe("BraindanceGameController", "OnIsActiveUpdated", function(_, active)
        self.inBraindance = active and true or false
    end)

    Observe("LoadingScreenProgressBarController", "SetProgress", function(_, progress)
        self.inLoading = (tonumber(progress) or 1) < 1.0
    end)

    -- Fast travel may not always go through the progress bar controller;
    -- track it explicitly so audio does not leak into the loading screen.
    Observe("FastTravelSystem", "OnToggleFastTravelAvailabilityOnMapRequest", function(_, request)
        if request and request.isEnabled then
            self.fastTravelStart = request.pointRecord
        end
    end)

    Observe("FastTravelSystem", "OnPerformFastTravelRequest", function(_, request)
        if not request or not request.pointData or not request.pointData.pointRecord then
            return
        end
        -- Same-point requests never show a loading screen.
        if tostring(self.fastTravelStart) ~= tostring(request.pointData.pointRecord) then
            self.inLoading = true
        end
    end)

    Observe("FastTravelSystem", "OnLoadingScreenFinished", function(_, finished)
        if finished then
            self.inLoading = false
        end
    end)
end

function Session:OnSessionStart(callback)
    table.insert(self.startCallbacks, callback)
end

function Session:OnSessionEnd(callback)
    table.insert(self.endCallbacks, callback)
end

local function runAll(callbacks)
    for _, callback in ipairs(callbacks) do
        local ok, err = pcall(callback)
        if not ok then
            print(("[Frequency] Error: session callback failed: %s"):format(tostring(err)))
        end
    end
end

local function isPlayerAttached()
    local ok, player = pcall(Game.GetPlayer)
    if not ok or player == nil then
        return false
    end
    local definedOk, defined = pcall(IsDefined, player)
    return definedOk and defined == true
end

--- True while the player is possessed by Johnny or a flashback sequence is
--- running. Polled: these states flip at scene transitions where CET
--- observers are not reliably delivered.
local function isJohnnySequence()
    local ok, player = pcall(Game.GetPlayer)
    if not ok or player == nil then
        return false
    end

    local replacerOk, replacer = pcall(function()
        return player:IsJohnnyReplacer()
    end)
    if replacerOk and replacer == true then
        return true
    end

    local factOk, fact = pcall(function()
        return Game.GetQuestsSystem():GetFactStr(Game.GetPlayerSystem():GetPossessedByJohnnyFactName())
    end)
    return factOk and fact == 1
end

--- Polled once per frame from the mod's onUpdate handler.
function Session:Update()
    local attached = isPlayerAttached()

    if attached and not self.inGame then
        self.inGame = true
        runAll(self.startCallbacks)
    elseif not attached and self.inGame then
        self.inGame = false
        runAll(self.endCallbacks)
    end

    self.inFlashback = attached and isJohnnySequence()
end

function Session:IsInGame()
    return self.inGame
end

function Session:IsInMenu()
    return self.inMenu
end

function Session:IsInBraindance()
    return self.inBraindance
end

function Session:IsInFlashback()
    return self.inFlashback
end

function Session:IsInLoading()
    return self.inLoading
end

--- True in every state where the game silences the world and custom audio
--- must follow suit: menus, braindances, Johnny sequences, loading screens.
function Session:ShouldMuteAudio()
    return self.inMenu or self.inBraindance or self.inFlashback or self.inLoading
end

--- Used right after a full CET mod reload, where no session transition
--- will fire even though a session is already running.
function Session:Refresh()
    self.inGame = isPlayerAttached()
end

return Session
