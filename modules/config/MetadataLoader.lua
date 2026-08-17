--[[
    Frequency - MetadataLoader.lua

    Detects which metadata schema a station folder uses, normalizes it into
    the internal station config model, and (for legacy v1 files) writes back
    fields that had to be repaired so the file stays complete.

    Written from scratch for Frequency.
]]

local Class = require("modules/core/Class")
local SchemaV1 = require("modules/config/SchemaV1")
local SchemaV2 = require("modules/config/SchemaV2")

local MetadataLoader = Class.define("MetadataLoader")

function MetadataLoader:initialize(files, logger)
    self.files = files
    self.logger = logger
    self.handlers = { SchemaV2(logger), SchemaV1(logger) } -- v2 first, v1 is the fallback
end

function MetadataLoader:FindHandler(raw)
    for _, handler in ipairs(self.handlers) do
        if handler.Matches(raw) then
            return handler
        end
    end
    return nil
end

--- Loads and normalizes the metadata.json of one station folder.
--- @param metadataPath string CET-mod-relative path to the metadata file
--- @param folderName string station folder name (for log messages)
--- @return table|nil normalized config, string|nil error
function MetadataLoader:Load(metadataPath, folderName)
    local raw, readErr = self.files:ReadJson(metadataPath)
    if raw == nil then
        return nil, ("could not read metadata.json (%s)"):format(tostring(readErr))
    end

    local handler = self:FindHandler(raw)
    if handler == nil then
        local version = raw.schemaVersion
        return nil, ("unsupported schemaVersion %s (supported: 1 and 2)"):format(tostring(version))
    end

    local ok, normalized, repaired = pcall(function()
        return handler:Normalize(raw, folderName)
    end)
    if not ok then
        return nil, ("failed to parse metadata: %s"):format(tostring(normalized))
    end

    if handler.VERSION == 1 and handler:FillMissing(raw, normalized) then
        self.files:WriteJson(metadataPath, raw)
    elseif repaired then
        self.logger:Debugf("Metadata of \"%s\" needed repairs in memory only.", folderName)
    end

    return normalized, nil
end

return MetadataLoader
