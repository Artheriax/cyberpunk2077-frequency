--[[
    Frequency - ModConfig.lua

    Mod-level settings from config.json at the mod root. Everything has a
    sane default, the file is optional.

    {
        "importLegacyRadioExt": true   // also load stations from mods/radioExt/radios
    }

    Written from scratch for Frequency.
]]

local Class = require("modules/core/Class")

local ModConfig = Class.define("ModConfig")

ModConfig.FILE_PATH = "config.json"

function ModConfig:initialize(files, logger)
    self.files = files
    self.logger = logger
    self.importLegacyRadioExt = true
end

function ModConfig:Load()
    local raw = self.files:ReadJson(ModConfig.FILE_PATH)
    if raw == nil then
        return
    end
    if type(raw.importLegacyRadioExt) == "boolean" then
        self.importLegacyRadioExt = raw.importLegacyRadioExt
    end
end

return ModConfig
