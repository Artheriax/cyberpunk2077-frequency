--[[
    Frequency - Scheduler.lua

    Lightweight frame-based timer system. Replaces any third party cron
    helper: timers are registered with a delay or an interval and pumped once
    per frame from the mod's onUpdate handler.

    Written from scratch for Frequency.
]]

local Class = require("modules/core/Class")

local Scheduler = Class.define("Scheduler")

function Scheduler:initialize()
    self.timers = {}
    self.nextId = 1
end

--- Runs `callback` once after `delay` seconds. Returns a timer id.
function Scheduler:After(delay, callback)
    local id = self.nextId
    self.nextId = id + 1
    self.timers[id] = {
        remaining = math.max(delay or 0, 0),
        interval = nil,
        callback = callback,
    }
    return id
end

--- Runs `callback` every `interval` seconds until cancelled. Returns a timer id.
function Scheduler:Every(interval, callback)
    local id = self.nextId
    self.nextId = id + 1
    self.timers[id] = {
        remaining = math.max(interval or 0, 0.001),
        interval = math.max(interval or 0, 0.001),
        callback = callback,
    }
    return id
end

--- Runs `callback` on the next frame.
function Scheduler:NextFrame(callback)
    return self:After(0, callback)
end

function Scheduler:Cancel(id)
    self.timers[id] = nil
end

function Scheduler:CancelAll()
    self.timers = {}
end

function Scheduler:Update(deltaTime)
    local dt = deltaTime or 0
    local fire = {}

    for id, timer in pairs(self.timers) do
        timer.remaining = timer.remaining - dt
        if timer.remaining <= 0 then
            table.insert(fire, id)
        end
    end

    for _, id in ipairs(fire) do
        local timer = self.timers[id]
        if timer then
            if timer.interval then
                timer.remaining = timer.remaining + timer.interval
                if timer.remaining < 0 then
                    timer.remaining = timer.interval
                end
            else
                self.timers[id] = nil
            end

            local ok, err = pcall(timer.callback)
            if not ok then
                print(("[Frequency] Error: scheduled task failed: %s"):format(tostring(err)))
            end
        end
    end
end

return Scheduler
