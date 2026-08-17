--[[
    Frequency - GroupConfig.lua

    Station groups let pack authors tag stations with a shared "group" id
    and let users enable or disable whole packs at once. Group state lives
    in groups.json at the mod root and can be changed at runtime through the
    console API (Frequency.EnableGroup / Frequency.DisableGroup + Reload).

    Written from scratch for Frequency.
]]

local Class = require("modules/core/Class")

local GroupConfig = Class.define("GroupConfig")

GroupConfig.FILE_PATH = "groups.json"

function GroupConfig:initialize(files, logger)
    self.files = files
    self.logger = logger
    self.groups = {}
end

function GroupConfig:Load()
    local raw = self.files:ReadJson(GroupConfig.FILE_PATH)
    if raw == nil or type(raw.groups) ~= "table" then
        self.groups = {}
        return
    end

    self.groups = {}
    for name, data in pairs(raw.groups) do
        if type(name) == "string" and type(data) == "table" then
            self.groups[name] = {
                enabled = data.enabled ~= false, -- default: enabled
                displayName = type(data.displayName) == "string" and data.displayName or name,
            }
        end
    end
end

function GroupConfig:Save()
    local raw = { groups = {} }
    for name, data in pairs(self.groups) do
        raw.groups[name] = { enabled = data.enabled, displayName = data.displayName }
    end
    return self.files:WriteJson(GroupConfig.FILE_PATH, raw)
end

--- Registers a group id seen on a station. Unknown groups default to enabled.
function GroupConfig:Register(name)
    if name == nil or name == "" then
        return
    end
    if self.groups[name] == nil then
        self.groups[name] = { enabled = true, displayName = name }
    end
end

function GroupConfig:IsEnabled(name)
    if name == nil or name == "" then
        return true -- ungrouped stations are always enabled
    end
    local entry = self.groups[name]
    return entry == nil or entry.enabled
end

function GroupConfig:SetEnabled(name, enabled)
    self:Register(name)
    self.groups[name].enabled = enabled and true or false
    self:Save()
end

function GroupConfig:All()
    return self.groups
end

return GroupConfig
