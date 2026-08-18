--[[
    Frequency - ModSettings.lua

    Registers the Frequency tab with the Native Settings UI mod
    (GetMod("nativeSettings")) when it is installed. The UI is entirely
    optional: everything exposed here also exists in the CET console API,
    and Frequency works fine without the mod.

    Tab contents:
      - "Reload stations" button (hot reload without leaving the menu)
      - "Import legacy radioExt stations" switch (persisted in config.json)
      - "Debug logging" switch
      - "Station groups" subcategory: one switch per known group, so whole
        station packs can be enabled/disabled from the menu (persisted in
        groups.json, applies immediately)
      - Custom restore-defaults action for the tab

    Written from scratch for Frequency.
]]

local Class = require("modules/core/Class")

local ModSettings = Class.define("ModSettings")

local TAB = "/frequency"
local GROUPS_SUB = TAB .. "/groups"

function ModSettings:initialize(context)
    -- context: { logger, registry, groupConfig, modConfig, worldManager }
    self.logger = context.logger
    self.registry = context.registry
    self.groupConfig = context.groupConfig
    self.modConfig = context.modConfig
    self.worldManager = context.worldManager
    self.ns = nil
end

function ModSettings:IsAvailable()
    return self.ns ~= nil
end

--- Full station reload, same as Frequency.Reload() in the console, then
--- re-syncs the group widgets (a reload can add or remove groups).
function ModSettings:Reload()
    self.worldManager:ReleaseAll()
    self.registry:Reload()
    self:RefreshGroups()
    self.logger:Infof("Reloaded %d station(s) from the settings menu.", self.registry:Count())
end

--- Removes and re-creates one switch per known group, so the menu always
--- mirrors groups.json. Safe to call while the tab is open or closed.
function ModSettings:RefreshGroups()
    if not self:IsAvailable() then
        return
    end

    local ok, err = pcall(function()
        if self.ns.pathExists(GROUPS_SUB) then
            self.ns.removeSubcategory(GROUPS_SUB)
        end

        local names = {}
        for name in pairs(self.groupConfig:All()) do
            table.insert(names, name)
        end
        if #names == 0 then
            return -- nothing to show; the subcategory stays removed
        end
        table.sort(names)

        self.ns.addSubcategory(GROUPS_SUB, "Station groups")

        for _, name in ipairs(names) do
            local data = self.groupConfig:All()[name]
            self.ns.addSwitch(
                GROUPS_SUB,
                data.displayName or name,
                ("Toggle the whole station pack \"%s\" on or off. Applies immediately."):format(name),
                data.enabled,
                true,
                function(state)
                    self.groupConfig:SetEnabled(name, state)
                    self:Reload()
                end
            )
        end
    end)
    if not ok then
        self.logger:Warnf("Failed to refresh the group widgets in the settings menu: %s", tostring(err))
    end
end

--- Called from onInit: adds the tab and its widgets. Safe to call when
--- nativeSettings is not installed (it then just logs a debug message).
function ModSettings:Register()
    local ns = GetMod("nativeSettings")
    if ns == nil or type(ns.addTab) ~= "function" then
        self.logger:Debug("Native Settings UI not installed; settings tab skipped.")
        return
    end
    self.ns = ns

    local ok, err = pcall(function()
        ns.addTab(TAB, "Frequency")

        -- Hot-reload: the same action as Frequency.Reload() in the console.
        ns.addButton(
            TAB,
            "Reload stations",
            "Re-scans every station folder and rebuilds the station list without restarting the game.",
            "Reload stations",
            45,
            function()
                self:Reload()
            end
        )

        ns.addSwitch(
            TAB,
            "Import legacy radioExt stations",
            "Also load station folders from the radioExt mod folder. Re-scans the stations when toggled.",
            self.modConfig.importLegacyRadioExt,
            true,
            function(state)
                self.modConfig.importLegacyRadioExt = state
                self.modConfig:Save()
                self:Reload()
            end
        )

        ns.addSwitch(
            TAB,
            "World radio support",
            "Opt-in: let physical in-world radios play custom stations. Off by default so quest radios stay fully vanilla. Takes effect after restarting the game.",
            self.modConfig.supportWorldRadios,
            false,
            function(state)
                self.modConfig.supportWorldRadios = state
                self.modConfig:Save()
            end
        )

        ns.addSwitch(
            TAB,
            "Debug logging",
            "Prints verbose [Frequency] Debug: messages to the CET console.",
            self.logger:IsDebugEnabled(),
            false,
            function(state)
                self.logger:SetDebug(state)
            end
        )

        self:RefreshGroups()

        -- Override the vanilla "Restore defaults" action for this tab.
        ns.registerRestoreDefaultsCallback(TAB, true, function()
            self.groupConfig:EnableAll()
            self.modConfig.importLegacyRadioExt = true
            self.modConfig.supportWorldRadios = false
            self.modConfig:Save()
            self.logger:SetDebug(false)
            self:Reload()
        end)
    end)
    if not ok then
        self.ns = nil
        self.logger:Warnf("Failed to register the Native Settings UI tab: %s", tostring(err))
    end
end

return ModSettings
