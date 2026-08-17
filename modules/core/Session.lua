--[[
    Frequency - Session.lua

    Tracks whether the player is currently inside a loaded game session and
    whether a game menu is open. Other systems subscribe through
    OnSessionStart / OnSessionEnd instead of touching game internals.

    Written from scratch for Frequency.
]]

local Class = require("modules/core/Class")

local Session = Class.define("Session")

function Session:initialize()
    self.inGame = false
    self.inMenu = false

    self.startCallbacks = {}
    self.endCallbacks = {}
end

--- Registers game hooks. Must be called from onInit, not at load time:
--- CET only exposes `Observe` to mods after all init.lua files have run.
function Session:RegisterHooks()
    Observe("RadialWheelController", "OnIsInMenuChanged", function(_, isInMenu)
        self.inMenu = isInMenu and true or false
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
end

function Session:IsInGame()
    return self.inGame
end

function Session:IsInMenu()
    return self.inMenu
end

--- Used right after a full CET mod reload, where no session transition
--- will fire even though a session is already running.
function Session:Refresh()
    self.inGame = isPlayerAttached()
end

return Session
