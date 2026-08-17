--[[
    Frequency - NativeBridge.lua

    Resolves and wraps the native RED4ext scripting class `Frequency`
    (registered by Frequency.dll). The reference is captured lazily and
    defensively: after the console API shadows the global `Frequency` table,
    the native class is still reachable through this module.

    Written from scratch for Frequency.
]]

local Class = require("modules/core/Class")

local NativeBridge = Class.define("NativeBridge")

NativeBridge.MIN_NATIVE_VERSION = "1.1.0"

function NativeBridge:initialize(logger)
    self.logger = logger
    self.native = nil
end

--- Compares dotted version strings ("1.0.10" >= "1.0.9").
function NativeBridge.VersionAtLeast(actual, required)
    if actual == nil then
        return false
    end
    local function parse(v)
        local parts = {}
        for n in tostring(v):gmatch("(%d+)") do
            table.insert(parts, tonumber(n) or 0)
        end
        return parts
    end
    local a, r = parse(actual), parse(required)
    for i = 1, math.max(#a, #r) do
        local av, rv = a[i] or 0, r[i] or 0
        if av > rv then return true end
        if av < rv then return false end
    end
    return true
end

--- Grabs the native class from the environment. CET registers RTTI native
--- classes (including `Frequency` from Frequency.dll) into the sandbox
--- globals by the time onInit fires; before that the lookup yields nil.
--- `_G` is not exposed to mods by CET's sandbox, so a defensive env lookup
--- is used instead of rawget(_G, ...).
local function resolveNativeGlobal()
    local ok, g = pcall(function()
        return Frequency
    end)
    if not ok then
        return nil
    end
    if type(g) == "table" and rawget(g, "__isFrequencyApi") == true then
        return rawget(g, "Native")
    end
    return g
end

--- Returns the native class, or nil if Frequency.dll is not loaded.
function NativeBridge:Get()
    if self.native == nil then
        self.native = resolveNativeGlobal()
    end
    return self.native
end

--- Validates that the native plugin is present and new enough.
--- Returns true when the Lua side may proceed with initialization.
function NativeBridge:Validate()
    local native = self:Get()
    if native == nil then
        self.logger:Error("Native plugin missing. Make sure Frequency.dll and fmod.dll are installed in red4ext/plugins/Frequency.")
        return false
    end

    local ok, version = pcall(function()
        return native.GetVersion()
    end)
    if not ok then
        self.logger:Error("Native plugin present but not callable. Reinstall Frequency.dll.")
        return false
    end

    if not NativeBridge.VersionAtLeast(version, NativeBridge.MIN_NATIVE_VERSION) then
        self.logger:Errorf("Native plugin version mismatch: found %s, need %s or newer. Use the DLL that ships with this release.",
            tostring(version), NativeBridge.MIN_NATIVE_VERSION)
        return false
    end

    self.logger:Infof("Native plugin ready (version %s).", tostring(version))
    return true
end

return NativeBridge
