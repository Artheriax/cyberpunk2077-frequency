--[[
    Frequency - Logger.lua

    Leveled logging with a fixed "[Frequency]" prefix. Debug output is gated
    behind a toggle that can be flipped at runtime from the CET console
    (Frequency.SetDebug(true)).

    Written from scratch for Frequency.
]]

local Class = require("modules/core/Class")

local Logger = Class.define("Logger")

Logger.Level = {
    Error = 0,
    Warning = 1,
    Info = 2,
    Debug = 3,
}

local LEVEL_TAG = {
    [0] = "Error",
    [1] = "Warning",
    [2] = "Info",
    [3] = "Debug",
}

function Logger:initialize()
    self.debugEnabled = false
end

function Logger:SetDebug(enabled)
    self.debugEnabled = enabled and true or false
end

function Logger:IsDebugEnabled()
    return self.debugEnabled
end

function Logger:Write(level, message)
    if level == Logger.Level.Debug and not self.debugEnabled then
        return
    end
    print(("[Frequency] %s: %s"):format(LEVEL_TAG[level] or "Info", tostring(message)))
end

function Logger:Error(message)
    self:Write(Logger.Level.Error, message)
end

function Logger:Warn(message)
    self:Write(Logger.Level.Warning, message)
end

function Logger:Info(message)
    self:Write(Logger.Level.Info, message)
end

function Logger:Debug(message)
    self:Write(Logger.Level.Debug, message)
end

--- printf-style convenience wrappers.
function Logger:Errorf(fmt, ...) self:Error(fmt:format(...)) end
function Logger:Warnf(fmt, ...) self:Warn(fmt:format(...)) end
function Logger:Infof(fmt, ...) self:Info(fmt:format(...)) end
function Logger:Debugf(fmt, ...) self:Debug(fmt:format(...)) end

return Logger
