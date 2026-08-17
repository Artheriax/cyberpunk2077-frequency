--[[
    Frequency - ModSettings.lua

    Registers the Frequency tab with the Native Settings UI mod
    (GetMod("nativeSettings")) when it is installed. The UI is entirely
    optional: everything exposed here also exists in the CET console API,
    and Frequency works fine without the mod.

    Written from scratch for Frequency.
]]

local Class = require("modules/core/Class")

local ModSettings = Class.define("ModSettings")

function ModSettings:initialize(context)
    -- context: { logger, registry }
    self.logger = context.logger
    self.registry = context.registry
    self.nativeSettings = nil
end

function ModSettings:IsAvailable()
    return self.nativeSettings ~= nil
end

--- Called from onInit: adds the tab and its widgets. Safe to call when
--- nativeSettings is not installed (it then just logs a debug message).
function ModSettings:Register()
    local ns = GetMod("nativeSettings")
    if ns == nil or type(ns.addTab) ~= "function" then
        self.logger:Debug("Native Settings UI not installed; settings tab skipped.")
        return
    end
    self.nativeSettings = ns

    local ok, err = pcall(function()
        ns.addTab("/frequency", "Frequency")

        -- Hot-reload: the same action as Frequency.Reload() in the console.
        ns.addButton(
            "/frequency",
            "Reload stations",
            "Re-scans every station folder and rebuilds the station list without restarting the game.",
            "Reload stations",
            45,
            function()
                self.registry:Reload()
            end
        )
    end)
    if not ok then
        self.nativeSettings = nil
        self.logger:Warnf("Failed to register the Native Settings UI tab: %s", tostring(err))
    end
end

return ModSettings
