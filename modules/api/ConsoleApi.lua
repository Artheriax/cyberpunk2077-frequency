--[[
    Frequency - ConsoleApi.lua

    Public API of the mod, reachable from the CET console and from other
    CET mods:

        Frequency.Version()
        Frequency.Status()
        Frequency.List()
        Frequency.Info("station name")
        Frequency.Reload()                  -- hot-reload all stations
        Frequency.Groups()
        Frequency.EnableGroup("packId")
        Frequency.DisableGroup("packId")
        Frequency.Play("station name")      -- force-play on the radio channel
        Frequency.StopVehicle()
        Frequency.SetDebug(true)

    The API table is served through `GetMod("Frequency")` (CET sandboxed
    mods cannot publish console globals). The native RED4ext class remains
    available as `Frequency.Native` on that table.

    Written from scratch for Frequency.
]]

local Class = require("modules/core/Class")

local ConsoleApi = Class.define("ConsoleApi")

function ConsoleApi:initialize(context)
    -- context: { logger, nativeBridge, registry, groupConfig, vehicleManager, worldManager, modSettings, modConfig }
    self.logger = context.logger
    self.nativeBridge = context.nativeBridge
    self.registry = context.registry
    self.groupConfig = context.groupConfig
    self.vehicleManager = context.vehicleManager
    self.worldManager = context.worldManager
    self.modSettings = context.modSettings or nil
    self.modConfig = context.modConfig or nil

    -- Markers used by NativeBridge to recover the native class after the
    -- global `Frequency` name is rebound to this API table.
    self.__isFrequencyApi = true
    self.Native = self.nativeBridge:Get()
end

-- ---------------------------------------------------------------------------
-- Information
-- ---------------------------------------------------------------------------

function ConsoleApi:Version()
    local native = self.nativeBridge:Get()
    local nativeVersion = native and native.GetVersion() or "not loaded"
    local text = ("Frequency (CET) + native %s"):format(tostring(nativeVersion))
    print(text)
    return text
end

function ConsoleApi:Status()
    local active = self.registry:GetActiveVehicleStation()
    local lines = {
        ("Stations loaded: %d"):format(self.registry:Count()),
        ("Legacy radioExt import: %s"):format(self.registry.legacyImportUsed and "yes" or "no"),
        ("World radio support: %s"):format(self.modConfig and self.modConfig.supportWorldRadios and "on" or "off"),
        ("Vehicle radio: %s"):format(active and ("\"" .. active.station .. "\" - " .. active.trackName) or "off"),
    }
    for _, line in ipairs(lines) do
        print("[Frequency] " .. line)
    end
    return lines
end

function ConsoleApi:List()
    local result = {}
    for _, station in ipairs(self.registry:All()) do
        local entry = {
            index = station:GetIndex(),
            name = station:GetName(),
            fm = station:GetFm(),
            group = station:GetGroup(),
            stream = station:IsStream(),
            songs = station:GetSongCount(),
            source = station.source,
        }
        table.insert(result, entry)
        print(("[Frequency] [%d] %s (FM %s, %s, %d song(s), group: %s%s)"):format(
            entry.index, entry.name, tostring(entry.fm),
            entry.stream and "stream" or "files", entry.songs,
            entry.group ~= "" and entry.group or "-",
            entry.source == "legacy" and ", legacy" or ""))
    end
    return result
end

function ConsoleApi:Info(name)
    local station = self.registry:GetByName(name)
    if not station then
        print(("[Frequency] No station named \"%s\"."):format(tostring(name)))
        return nil
    end

    local info = {
        name = station:GetName(),
        fm = station:GetFm(),
        index = station:GetIndex(),
        group = station:GetGroup(),
        stream = station:IsStream(),
        url = station:IsStream() and station:GetStreamUrl() or nil,
        songs = station:GetSongCount(),
        currentTrack = station:GetCurrentTrackName(),
        record = station:GetRecordId(),
        schema = station.config.schemaVersion,
    }
    for key, value in pairs(info) do
        print(("[Frequency]   %s: %s"):format(key, tostring(value)))
    end
    return info
end

-- ---------------------------------------------------------------------------
-- Hot reload
-- ---------------------------------------------------------------------------

function ConsoleApi:Reload()
    self.worldManager:ReleaseAll()
    self.registry:Reload()
    if self.modSettings then
        self.modSettings:RefreshGroups()
    end
    return self.registry:Count()
end

-- ---------------------------------------------------------------------------
-- Groups
-- ---------------------------------------------------------------------------

function ConsoleApi:Groups()
    local groups = self.groupConfig:All()
    for name, data in pairs(groups) do
        print(("[Frequency]   %s (%s): %s"):format(name, data.displayName, data.enabled and "enabled" or "disabled"))
    end
    return groups
end

function ConsoleApi:EnableGroup(name)
    self.groupConfig:SetEnabled(name, true)
    print(("[Frequency] Group \"%s\" enabled. Call Frequency.Reload() to apply."):format(tostring(name)))
    return true
end

function ConsoleApi:DisableGroup(name)
    self.groupConfig:SetEnabled(name, false)
    print(("[Frequency] Group \"%s\" disabled. Call Frequency.Reload() to apply."):format(tostring(name)))
    return true
end

-- ---------------------------------------------------------------------------
-- Playback control (debug / companion mods)
-- ---------------------------------------------------------------------------

function ConsoleApi:Play(name)
    local station = self.registry:GetByName(name)
    if not station then
        print(("[Frequency] No station named \"%s\"."):format(tostring(name)))
        return false
    end
    self.vehicleManager:SwitchTo(station)
    return true
end

function ConsoleApi:StopVehicle()
    self.vehicleManager:DisableCustomRadio()
    return true
end

function ConsoleApi:SetDebug(enabled)
    self.logger:SetDebug(enabled)
    print(("[Frequency] Debug logging %s."):format(enabled and "enabled" or "disabled"))
    return true
end

function ConsoleApi:Help()
    print("[Frequency] Available commands:")
    print("[Frequency]   Frequency.Version()                 - show versions")
    print("[Frequency]   Frequency.Status()                  - session overview")
    print("[Frequency]   Frequency.List()                    - list all stations")
    print("[Frequency]   Frequency.Info(\"name\")              - station details")
    print("[Frequency]   Frequency.Reload()                  - hot-reload stations from disk")
    print("[Frequency]   Frequency.Groups()                  - list station groups")
    print("[Frequency]   Frequency.EnableGroup(\"id\")         - enable a group (then Reload)")
    print("[Frequency]   Frequency.DisableGroup(\"id\")        - disable a group (then Reload)")
    print("[Frequency]   Frequency.Play(\"name\")              - force-play a station")
    print("[Frequency]   Frequency.StopVehicle()             - stop the vehicle radio")
    print("[Frequency]   Frequency.SetDebug(true|false)      - toggle debug logging")
end

return ConsoleApi
