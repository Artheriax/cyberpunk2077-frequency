--[[
    Frequency - Files.lua

    Small file system helpers: existence checks, JSON read/write with error
    reporting, and folder listing for station directories.

    Written from scratch for Frequency.
]]

local Class = require("modules/core/Class")

local Files = Class.define("Files")

function Files:initialize(nativeBridge, logger)
    self.native = nativeBridge
    self.logger = logger
end

function Files:Exists(path)
    local handle = io.open(path, "r")
    if handle then
        io.close(handle)
        return true
    end
    return false
end

--- Reads and decodes a JSON file. Returns the decoded value or nil + error.
function Files:ReadJson(path)
    local handle = io.open(path, "r")
    if not handle then
        return nil, "file not found"
    end
    local content = handle:read("*a")
    handle:close()

    if not content or content == "" then
        return nil, "file is empty"
    end

    local ok, decoded = pcall(json.decode, content)
    if not ok or decoded == nil then
        return nil, "invalid JSON: " .. tostring(decoded)
    end
    return decoded
end

--- Encodes and writes a JSON file. Returns true on success.
function Files:WriteJson(path, data)
    local ok, encoded = pcall(json.encode, data)
    if not ok then
        self.logger:Warnf("Failed to encode JSON for %s", tostring(path))
        return false
    end

    local handle = io.open(path, "w")
    if not handle then
        self.logger:Warnf("Failed to open %s for writing", tostring(path))
        return false
    end
    handle:write(encoded)
    handle:close()
    return true
end

--- Lists the subfolders of a directory, resolved relative to the game
--- executable directory by the native plugin. Returns a sorted array.
function Files:ListSubfolders(relativePath)
    local folders = self.native.GetFolders(relativePath)
    if not folders then
        return {}
    end
    table.sort(folders)
    return folders
end

--- Lists the files inside a folder that sits inside the CET mod directory.
function Files:ListFiles(relativePath)
    local entries = {}
    for _, entry in pairs(dir(relativePath)) do
        table.insert(entries, entry.name)
    end
    table.sort(entries)
    return entries
end

return Files
