--[[
    Frequency - ModConfig.lua

    Mod-level settings from config.json at the mod root. Everything has a
    sane default, the file is optional.

    {
        "importLegacyRadioExt": true,  // also load stations from mods/radioExt/radios
        "supportWorldRadios": false,   // opt-in: physical in-world radios
                                       // (not implemented in this branch)
        "audioGain": 0.4               // global station loudness multiplier
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
    self.supportWorldRadios = false
    self.audioGain = 0.4
end

function ModConfig:Load()
    local raw = self.files:ReadJson(ModConfig.FILE_PATH)
    if raw == nil then
        return
    end
    if type(raw.importLegacyRadioExt) == "boolean" then
        self.importLegacyRadioExt = raw.importLegacyRadioExt
    end
    if type(raw.supportWorldRadios) == "boolean" then
        self.supportWorldRadios = raw.supportWorldRadios
    end
    if type(raw.audioGain) == "number" then
        self.audioGain = raw.audioGain
    end
end

--- Persists the current settings back to config.json, keeping any unknown
--- keys a user may have added.
function ModConfig:Save()
    local raw = self.files:ReadJson(ModConfig.FILE_PATH) or {}
    raw.importLegacyRadioExt = self.importLegacyRadioExt and true or false
    raw.supportWorldRadios = self.supportWorldRadios and true or false
    raw.audioGain = self.audioGain
    return self.files:WriteJson(ModConfig.FILE_PATH, raw)
end

return ModConfig
