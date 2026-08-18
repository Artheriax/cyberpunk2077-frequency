--[[
    Frequency - VehicleRadioManager.lua

    Owns the vehicle / pocket radio channel (-1): switching between custom
    stations, handing playback over between car and pocket radio, and making
    sure a station that should be playing actually is.

    Written from scratch for Frequency.
]]

local Class = require("modules/core/Class")

local VehicleRadioManager = Class.define("VehicleRadioManager")

function VehicleRadioManager:initialize(context)
    -- context: { logger, scheduler, registry, session, audio }
    self.logger = context.logger
    self.scheduler = context.scheduler
    self.registry = context.registry
    self.session = context.session
    self.audio = context.audio

    self.mutedInMenu = false
end

-- ---------------------------------------------------------------------------
-- Switching
-- ---------------------------------------------------------------------------

function VehicleRadioManager:SwitchTo(station)
    if station:IsActiveOn(-1) then
        return
    end
    self:DisableCustomRadio()

    local vehicle = GetMountedVehicle(GetPlayer())
    if vehicle then
        vehicle:GetBlackboard():SetBool(GetAllBlackboardDefs().Vehicle.VehRadioState, true)
        vehicle:GetBlackboard():SetName(GetAllBlackboardDefs().Vehicle.VehRadioStationName, station:GetName())
    end

    station:Activate(-1)
end

function VehicleRadioManager:DisableCustomRadio()
    for _, station in ipairs(self.registry:All()) do
        station:Deactivate(-1)
    end

    local vehicle = GetMountedVehicle(GetPlayer())
    if vehicle then
        vehicle:GetBlackboard():SetBool(GetAllBlackboardDefs().Vehicle.VehRadioState, false)
    end
end

function VehicleRadioManager:GetActiveStationData()
    return self.registry:GetActiveVehicleStation()
end

-- ---------------------------------------------------------------------------
-- Frame update / menu handling
-- ---------------------------------------------------------------------------

function VehicleRadioManager:Update()
    self.mutedInMenu = false

    local player = GetPlayer()
    if not player then
        return
    end

    local vehicle = GetMountedVehicle(player)
    if vehicle then
        if not vehicle:IsEngineTurnedOn() then
            self.audio:UpdateVehicleVolume()
            return
        end

        local nameResult = vehicle:GetBlackboard():GetName(GetAllBlackboardDefs().Vehicle.VehRadioStationName)
        local name = nameResult and nameResult.value
        local station = name and self.registry:GetByName(name) or nil

        if station
            and not station:IsActiveOn(-1)
            and vehicle:GetBlackboard():GetBool(GetAllBlackboardDefs().Vehicle.VehRadioState) == true then
            station:Activate(-1, false)
            player:GetQuickSlotsManager():SendRadioEvent(true, true, station:GetIndex())
            self.logger:Debug("Vehicle radio was supposed to be playing but was not - restarted it.")
        end

        self.audio:UpdateVehicleVolume()
    elseif player:GetPocketRadio().isOn then
        local station = self.registry:GetByIndex(player:GetPocketRadio().station)
        if station and not station:IsActiveOn(-1) then
            player:GetQuickSlotsManager():SendRadioEvent(true, true, station:GetIndex())
            self.logger:Debug("Pocket radio was supposed to be playing but was not - restarted it.")
        end

        self.audio:UpdateVehicleVolume()
    end
end

--- Called every frame while a menu is open: custom audio must not leak
--- into the pause menu.
function VehicleRadioManager:HandleMenu()
    if self.mutedInMenu then
        return
    end

    local player = GetPlayer()
    if player then
        local station = self.registry:GetByIndex(player:GetPocketRadio().station)

        local vehicle = GetMountedVehicle(player)
        if vehicle then
            local nameResult = vehicle:GetBlackboard():GetName(GetAllBlackboardDefs().Vehicle.VehRadioStationName)
            if nameResult and nameResult.value then
                station = self.registry:GetByName(nameResult.value) or station
            end
        end

        if station then
            station.channels[-1] = true -- force the flag so Deactivate() actually runs
            station:Deactivate(-1)
        end
    end

    self.mutedInMenu = true
end

--- Re-applies the context volume on every station using the vehicle channel.
function VehicleRadioManager:RefreshVehicleVolume()
    for _, station in ipairs(self.registry:All()) do
        if station:IsActiveOn(-1) then
            station:UpdateVolume(-1)
        end
    end
end

--- Compatibility with the Train System mod: mute the vehicle channel while
--- riding a train.
function VehicleRadioManager:HandleTrainSystem(trainSystem)
    if not trainSystem or not trainSystem.stationSys then
        return
    end

    local train = trainSystem.stationSys.activeTrain
    if train and train.playerMounted then
        local vehicle = GetMountedVehicle(GetPlayer())
        if not vehicle then
            return
        end
        for _, station in ipairs(self.registry:All()) do
            if station:IsActiveOn(-1) then
                vehicle:ToggleRadioReceiver(false)
            end
        end
    end
end

return VehicleRadioManager
