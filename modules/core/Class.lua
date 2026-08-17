--[[
    Frequency - Class.lua

    Minimal class system used by the whole mod. Supports single inheritance,
    constructors via `MyClass(...)` and `MyClass:new(...)`, and `isa` checks.

    Written from scratch for Frequency.
]]

local function instantiate(cls, ...)
    local instance = setmetatable({}, cls)
    if cls.initialize then
        cls.initialize(instance, ...)
    end
    return instance
end

--- Creates a new class table.
--- @param name string Human readable class name (used by tostring / logging).
--- @param base table|nil Optional base class for single inheritance.
local function defineClass(name, base)
    local cls = {}
    cls.__name = name
    cls.__index = cls
    cls.__base = base

    -- Constructor, callable as ClassName(...) or ClassName:new(...)
    cls.new = function(...)
        return instantiate(cls, ...)
    end

    -- Method lookup walks the inheritance chain.
    local meta = {
        __call = function(c, ...)
            return instantiate(c, ...)
        end,
        __tostring = function(c)
            return c.__name
        end,
    }
    if base then
        meta.__index = base
    end
    setmetatable(cls, meta)

    --- Returns true if this class is `other` or descends from it.
    function cls:extends(other)
        local current = self
        while current do
            if current == other then
                return true
            end
            current = rawget(current, "__base")
        end
        return false
    end

    return cls
end

--- Runtime type check: obj:isa(SomeClass)
--- @param obj table
--- @param cls table
local function isa(obj, cls)
    if type(obj) ~= "table" then
        return false
    end
    local mt = getmetatable(obj)
    while mt do
        if mt == cls then
            return true
        end
        mt = rawget(mt, "__base")
    end
    return false
end

return {
    define = defineClass,
    isa = isa,
}
