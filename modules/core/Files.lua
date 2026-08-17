--[[
    Frequency - Files.lua

    Small file system helpers: existence checks, JSON read/write with error
    reporting, and folder listing for station directories.

    Path convention: paths starting with "plugins\" are game-root-relative
    and are handled by the native plugin (the only way to reach folders
    outside this mod, e.g. the legacy radioExt install - CET's sandboxed io
    rejects ".." escapes). Anything else is CET-mod-relative and uses the
    sandboxed io.

    Written from scratch for Frequency.
]]

local Class = require("modules/core/Class")

local Files = Class.define("Files")

local NATIVE_PREFIX = "plugins\\"

function Files:initialize(nativeBridge, logger)
    self.native = nativeBridge
    self.logger = logger
end

function Files:IsNativePath(path)
    return path:sub(1, #NATIVE_PREFIX) == NATIVE_PREFIX
end

--- Returns the native class, or nil when the plugin is not available.
function Files:Native()
    return self.native:Get()
end

function Files:Exists(path)
    if self:IsNativePath(path) then
        local native = self:Native()
        if native == nil then
            return false
        end
        local ok, exists = pcall(native.FileExists, path)
        return ok and exists == true
    end

    local handle = io.open(path, "r")
    if handle then
        io.close(handle)
        return true
    end
    return false
end

--- Reads a whole text file. Returns the content or nil + error.
function Files:ReadText(path)
    if self:IsNativePath(path) then
        local native = self:Native()
        if native == nil then
            return nil, "native plugin not available"
        end
        local ok, content = pcall(native.ReadText, path)
        if not ok then
            return nil, tostring(content)
        end
        if content == nil or content == "" then
            return nil, "file not found or empty"
        end
        return content
    end

    local handle = io.open(path, "r")
    if not handle then
        return nil, "file not found"
    end
    local content = handle:read("*a")
    handle:close()
    if not content then
        return nil, "file is empty"
    end
    return content
end

--- Reads and decodes a JSON file. Returns the decoded value or nil + error.
function Files:ReadJson(path)
    local content, readErr = self:ReadText(path)
    if content == nil then
        return nil, readErr
    end
    if content == "" then
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

    if self:IsNativePath(path) then
        local native = self:Native()
        if native == nil then
            self.logger:Warnf("Failed to write %s: native plugin not available", tostring(path))
            return false
        end
        local okWrite, written = pcall(native.WriteText, path, encoded)
        if not okWrite or written ~= true then
            self.logger:Warnf("Failed to write %s", tostring(path))
            return false
        end
        return true
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
    local native = self:Native()
    if native == nil then
        return {}
    end
    local ok, folders = pcall(native.GetFolders, relativePath)
    if not ok or folders == nil then
        return {}
    end
    table.sort(folders)
    return folders
end

--- Lists the files inside a folder. Native paths go through the plugin,
--- anything else through CET's sandboxed dir(). Returns a sorted array.
function Files:ListFiles(relativePath)
    local entries = {}

    if self:IsNativePath(relativePath) then
        local native = self:Native()
        if native == nil then
            return entries
        end
        local ok, files = pcall(native.GetFiles, relativePath)
        if not ok or files == nil then
            return entries
        end
        for _, name in ipairs(files) do
            table.insert(entries, name)
        end
    else
        local ok, listing = pcall(dir, relativePath)
        if not ok or listing == nil then
            return entries
        end
        for _, entry in pairs(listing) do
            table.insert(entries, entry.name)
        end
    end

    table.sort(entries)
    return entries
end

return Files
