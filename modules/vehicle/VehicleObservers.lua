--[[
    Frequency - VehicleObservers.lua

    Registers every game hook related to the vehicle and pocket radio:
    injecting custom stations into the radio list, intercepting station
    selection, keeping the UI (track name, equalizer icon, notification)
    in sync, and handling enter/exit transitions.

    Written from scratch for Frequency.
]]

local Class = require("modules/core/Class")

local VehicleObservers = Class.define("VehicleObservers")

local NO_STATION_KEY = "LocKey#705"

local function splitString(input, delimiter)
    local result = {}
    for match in (input .. delimiter):gmatch("(.-)" .. delimiter) do
        table.insert(result, match)
    end
    return result
end

--- Extracts a sortable FM number from a station's display name.
local function fmFromDisplayName(displayName)
    local normalized = displayName:gsub(",", ".")
    local parts = splitString(normalized, " ")
    local fm = tonumber(parts[1]) or tonumber(parts[#parts]) or 0
    if displayName == "Enable Aux Radio" then
        fm = 0
    end
    return fm
end

function VehicleObservers:initialize(context)
    -- context: { logger, scheduler, registry, vehicleManager }
    self.logger = context.logger
    self.scheduler = context.scheduler
    self.registry = context.registry
    self.vehicleManager = context.vehicleManager
end

--- Display-friendly track name for the currently playing vehicle station.
local function trackDisplayName(activeData)
    if activeData.trackName and activeData.trackName ~= "" then
        return activeData.trackName
    end
    if type(activeData.track) ~= "string" or activeData.track == "" then
        return activeData.station or ""
    end
    if activeData.isStream then
        return activeData.track
    end
    local fileName = activeData.track:match("([^\\]+)$") or activeData.track
    return (fileName:match("(.+)%..+$")) or fileName
end

--- Index of the next station for the cycle-through-stations hotkey.
function VehicleObservers:GetNextStationIndex(currentStation)
    if currentStation < 14 and currentStation ~= -1 then
        currentStation = RadioStationDataProvider.GetRadioStationUIIndex(currentStation)
    end

    local stations = VehiclesManagerDataHelper.GetRadioStations(GetPlayer())
    local position = 0
    for index, entry in pairs(stations) do
        if entry.record:Index() == currentStation then
            position = index
        end
    end

    local nextPosition = position + 1
    if nextPosition > #stations then
        nextPosition = 2
    end

    local nextStation = stations[nextPosition].record:Index()
    if nextStation < 14 then
        nextStation = EnumInt(RadioStationDataProvider.GetRadioStationByUIIndex(nextStation))
    end
    return nextStation
end

-- ---------------------------------------------------------------------------
-- Hook registration
-- ---------------------------------------------------------------------------

function VehicleObservers:Register()
    self:HookStationList()
    self:HookPocketRadioEvents()
    self:HookSelection()
    self:HookToggle()
    self:HookCycleHotkey()
    self:HookEnterExit()
    self:HookUiWidgets()
    self:HookVolumeSettings()
end

--- Injects custom stations, sorted by FM number, into the radio popup list.
function VehicleObservers:HookStationList()
    local registry = self.registry

    Override("VehiclesManagerDataHelper", "GetRadioStations;GameObject", function(player, wrapped)
        local stations = wrapped(player)
        stations[1] = nil -- remove the NoStation placeholder for sorting

        local sortable = {}
        for _, entry in pairs(stations) do
            local displayName = GetLocalizedText(entry.record:DisplayName())
            table.insert(sortable, { data = entry, fm = fmFromDisplayName(displayName) })
        end

        for _, station in ipairs(registry:All()) do
            local record = TweakDBInterface.GetRadioStationRecord(station:GetRecordId())
            if record then
                table.insert(sortable, { data = RadioListItemData.new({ record = record }), fm = tonumber(station:GetFm()) or 0 })
            else
                registry.logger:Warnf("TweakDB record %s missing for station \"%s\".", tostring(station:GetRecordId()), station:GetName())
            end
        end

        table.sort(sortable, function(a, b)
            return (a.fm or 0) < (b.fm or 0)
        end)

        local result = {}
        result[1] = RadioListItemData.new({ record = TweakDBInterface.GetRadioStationRecord("RadioStation.NoStation") })
        for _, entry in ipairs(sortable) do
            table.insert(result, entry.data)
        end
        return result
    end)
end

--- Pocket radio -> vehicle radio interaction.
function VehicleObservers:HookPocketRadioEvents()
    local scheduler = self.scheduler
    local vehicleManager = self.vehicleManager

    -- Custom stations: kill the vehicle receiver and route to the pocket radio.
    Override("QuickSlotsManager", "SendRadioEvent", function(this, toggle, setStation, station, wrapped)
        if station > 13 then
            local mounted = GetMountedVehicle(GetPlayer())
            if mounted then
                this.Player:QueueEventForEntityID(this.PlayerVehicleID,
                    VehicleRadioEvent.new({ toggle = false, setStation = false, station = -1 }))
            end
            if not mounted or GetPlayer():GetPocketRadio().settings:GetSyncToCarRadio() then
                this.Player:QueueEvent(VehicleRadioEvent.new({ toggle = toggle, setStation = setStation, station = station }))
            end

            scheduler:After(0.1, function()
                local vehicle = GetMountedVehicle(GetPlayer())
                if vehicle then
                    vehicle:GetVehicleComponent().radioState = true
                    vehicle:GetBlackboard():SetBool(GetAllBlackboardDefs().Vehicle.VehRadioState, true)
                end
            end)
        else
            wrapped(toggle, setStation, station)
        end
    end)

    -- Pocket radio picks up custom playback when leaving the car.
    Override("VehicleObject", "WasRadioReceiverPlaying", function(_, wrapped)
        if vehicleManager:GetActiveStationData() then
            return true
        end
        return wrapped()
    end)

    Override("VehicleObject", "GetCurrentRadioIndex", function(_, wrapped)
        local active = vehicleManager:GetActiveStationData()
        if active then
            return active.index
        end
        return wrapped()
    end)

    -- The engine keeps trying to restore the last vanilla station; pin the
    -- custom index instead when one is active.
    Override("PocketRadio", "HandleVehicleRadioStationChanged", function(this, evt, wrapped)
        if this.settings:GetSyncToCarRadio() then
            local active = vehicleManager:GetActiveStationData()
            if active then
                evt.radioIndex = active.index
            end
        end
        wrapped(evt)
    end)

    -- Radio hotkey support: custom playback counts as "radio on".
    Override("PocketRadio", "IsActive", function(_, wrapped)
        if vehicleManager:GetActiveStationData() then
            return true
        end
        return wrapped()
    end)

    Observe("PocketRadio", "TurnOn", function(this)
        local station = self.registry:GetByIndex(this.station)
        if not GetMountedVehicle(GetPlayer()) and station then
            self.vehicleManager:SwitchTo(station)
        elseif not station then
            self.vehicleManager:DisableCustomRadio()
        end
    end)

    ObserveAfter("PocketRadio", "TurnOff", function()
        if GetMountedVehicle(GetPlayer()) then
            return
        end
        if self.vehicleManager:GetActiveStationData() then
            self.vehicleManager:DisableCustomRadio()
        end
    end)

    ObserveAfter("PocketRadio", "HandleVehicleUnmounted", function(this)
        self.scheduler:NextFrame(function()
            self.vehicleManager:RefreshVehicleVolume()
        end)

        if (not this.settings:GetSyncToCarRadio()) and (not GetPlayer():GetPocketRadio().isOn) then
            this:TurnOff(true)
        end
    end)
end

--- Station picked in the radio popup list.
function VehicleObservers:HookSelection()
    local vehicleManager = self.vehicleManager
    local registry = self.registry
    local scheduler = self.scheduler

    Override("VehicleRadioPopupGameController", "Activate", function(this, wrapped)
        local name = this.selectedItem:GetStationData().record:DisplayName()
        local station = registry:GetByName(name)

        if station then
            vehicleManager:SwitchTo(station)
            GetPlayer():GetQuickSlotsManager():SendRadioEvent(true, true, station:GetIndex())
            scheduler:After(0.1, function()
                Game.GetUISystem():QueueEvent(VehicleRadioSongChanged.new())
            end)
        else
            if name == NO_STATION_KEY and GetMountedVehicle(GetPlayer()) then
                GetMountedVehicle(GetPlayer()):GetBlackboard()
                    :SetName(GetAllBlackboardDefs().Vehicle.VehRadioStationName, GetLocalizedText(name))
            end
            vehicleManager:DisableCustomRadio()
            wrapped()
        end
    end)
end

--- Radio on/off toggle while sitting in a vehicle.
function VehicleObservers:HookToggle()
    local vehicleManager = self.vehicleManager
    local registry = self.registry
    local scheduler = self.scheduler

    Override("VehicleComponent", "OnRadioToggleEvent", function(this, evt, wrapped)
        if vehicleManager:GetActiveStationData() then
            vehicleManager:DisableCustomRadio()
            this.vehicleBlackboard:SetBool(GetAllBlackboardDefs().Vehicle.VehRadioState, false)
            this:GetVehicle():ToggleRadioReceiver(false)
            return
        end

        local vehicle = GetMountedVehicle(GetPlayer())
        if not vehicle then
            return wrapped(evt)
        end

        local name = vehicle:GetBlackboard():GetName(GetAllBlackboardDefs().Vehicle.VehRadioStationName)
        if GetLocalizedTextByKey(name) ~= "" then
            name = GetLocalizedTextByKey(name)
        else
            name = name.value
        end

        local station = registry:GetByName(name)
        if station then
            vehicleManager:SwitchTo(station)
            scheduler:After(0.1, function()
                Game.GetUISystem():QueueEvent(VehicleRadioSongChanged.new())
            end)
        else
            wrapped(evt)
        end
    end)
end

--- Cycle-through-stations hotkey (on foot) and vanilla next-station input.
function VehicleObservers:HookCycleHotkey()
    local vehicleManager = self.vehicleManager

    Override("PocketRadio", "HandleRadioToggleEvent", function(this, evt, wrapped)
        if not this.settings:GetCycleButtonPress() then
            return wrapped(evt)
        end

        local nextStation = self:GetNextStationIndex(this.station)
        this.selectedStation = nextStation
        this.station = this.selectedStation
        if this.isOn then
            Game.GetUISystem():QueueEvent(UIVehicleRadioCycleEvent.new())
        end
        this:TurnOn(true)
    end)

    Observe("VehicleObject", "NextRadioReceiverStation", function()
        vehicleManager:DisableCustomRadio()
    end)
end

--- Entering a vehicle while a custom station plays on the pocket radio.
function VehicleObservers:HookEnterExit()
    local vehicleManager = self.vehicleManager
    local registry = self.registry
    local scheduler = self.scheduler

    Observe("EnteringEvents", "OnEnter", function()
        local active = vehicleManager:GetActiveStationData()
        if active then
            local station = registry:GetByIndex(active.index)
            scheduler:After(0.1, function()
                GetPlayer():GetQuickSlotsManager():SendRadioEvent(true, true, active.index)
                Game.GetUISystem():QueueEvent(VehicleRadioSongChanged.new())
                if station then
                    vehicleManager:SwitchTo(station)
                end
            end)
            scheduler:After(0.5, function()
                local vehicle = GetMountedVehicle(GetPlayer())
                if vehicle then
                    vehicle:GetBlackboard():SetName(GetAllBlackboardDefs().Vehicle.VehRadioStationName, active.station)
                    vehicle:GetBlackboard():SetBool(GetAllBlackboardDefs().Vehicle.VehRadioState, true)
                end
            end)
            vehicleManager:RefreshVehicleVolume()
        else
            scheduler:After(0.5, function()
                local player = GetPlayer()
                if not player then
                    return
                end
                if player:GetPocketRadio().isOn then
                    local vehicle = GetMountedVehicle(player)
                    if vehicle then
                        vehicle:GetBlackboard():SetName(GetAllBlackboardDefs().Vehicle.VehRadioStationName,
                            player:GetPocketRadio():GetStationName())
                    end
                end
            end)
        end
    end)
end

--- UI polish: selected list entry, equalizer icon, track name, notification.
function VehicleObservers:HookUiWidgets()
    local vehicleManager = self.vehicleManager

    ObserveAfter("VehicleRadioPopupGameController", "SetupData", function(this)
        local active = vehicleManager:GetActiveStationData()
        if not active then
            return
        end
        for i = 0, this.dataSource:GetArraySize() - 1 do
            local record = this.dataSource:GetItem(i).record
            if IsDefined(record) and record:Index() == active.index then
                this.startupIndex = i
                this.currentRadioId = active.index
            end
        end
    end)

    ObserveAfter("RadioStationListItemController", "UpdateEquializer", function(this)
        local active = vehicleManager:GetActiveStationData()
        if not active then
            return
        end
        local isPlaying = this.stationData.record:DisplayName() == active.station
        this.equilizerIcon:SetVisible(isPlaying)
        this.codeTLicon:SetVisible(not isPlaying)
    end)

    ObserveAfter("VehicleRadioPopupGameController", "SetTrackName", function(this)
        local active = vehicleManager:GetActiveStationData()
        if not active then
            return
        end
        this.trackName:SetText(trackDisplayName(active))
        this.trackName:SetVisible(true)
    end)

    ObserveAfter("VehicleSummonWidgetGameController", "TryShowVehicleRadioNotification", function(this)
        local active = vehicleManager:GetActiveStationData()
        if not active then
            return
        end

        this:PlayAnimation("OnSongChanged", inkAnimOptions.new(), "OnTimeOut")
        local dpadAction = DPADActionPerformed.new()
        dpadAction.action = EHotkey.DPAD_RIGHT
        dpadAction.state = EUIActionState.COMPLETED
        this:QueueEvent(dpadAction)

        this.rootWidget:SetVisible(true)
        inkWidgetRef.SetVisible(this.subText, true)
        inkWidgetRef.SetVisible(this.radioStationName, true)
        inkTextRef.SetText(this.radioStationName, active.station)
        inkTextRef.SetText(this.subText, trackDisplayName(active))
    end)
end

--- Changing the game's radio volume sliders updates playing stations.
function VehicleObservers:HookVolumeSettings()
    Observe("RadioVolumeSettingsController", "ChangeValue", function()
        self.vehicleManager:RefreshVehicleVolume()
    end)
end

return VehicleObservers
