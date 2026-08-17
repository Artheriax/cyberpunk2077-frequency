--[[
    Frequency - WorldObservers.lua

    Game hooks for physical in-world radios: extends the station cursor past
    the vanilla stations, starts/stops custom playback when a device picks a
    custom station, and draws the station logo/name on radio screens.

    Written from scratch for Frequency.
]]

local Class = require("modules/core/Class")
local Station = require("modules/stations/Station")

local WorldObservers = Class.define("WorldObservers")

-- Vanilla stations occupy indices 0..13; custom stations start at 14.
local VANILLA_LAST = Station.VANILLA_STATION_COUNT
local CUSTOM_FIRST = VANILLA_LAST + 1
local VANILLA_FIRST_UI = 4 -- first selectable vanilla station in the UI order

local DEFAULT_ATLAS = "base\\gameplay\\gui\\common\\icons\\radiostations_icons.inkatlas"

function WorldObservers:initialize(context)
    -- context: { logger, registry, worldManager }
    self.logger = context.logger
    self.registry = context.registry
    self.worldManager = context.worldManager
end

--- Device notification plumbing shared by the next/previous hooks.
local function notifyDevice(controller, evt)
    local notifier = ActionNotifier.new()
    notifier:SetNone()
    if controller:IsDisabled() or controller:IsUnpowered() or not controller:IsON() then
        return EntityNotificationType.DoNotNotifyEntity
    end
    controller:Notify(notifier, evt)
    return EntityNotificationType.SendThisEventToEntity
end

function WorldObservers:Register()
    self:HookStationCursor()
    self:HookDeviceSetup()
    self:HookPlayback()
    self:HookScreens()
end

--- Next/previous station buttons on physical radios, extended past the
--- vanilla range into the custom stations.
function WorldObservers:HookStationCursor()
    local registry = self.registry

    Override("RadioControllerPS", "OnNextStation", function(this, evt, wrapped)
        if this.activeStation > VANILLA_LAST then
            this.previousStation = this.activeStation
            this.activeStation = this.activeStation + 1
            if this.activeStation > VANILLA_LAST + registry:Count() then
                this.activeStation = VANILLA_LAST - 1
                return wrapped(evt)
            end
            return notifyDevice(this, evt)
        end

        if RadioStationDataProvider.GetRadioStationUIIndex(this.activeStation) > (VANILLA_LAST - 1) then
            this.previousStation = this.activeStation
            if registry:Count() > 0 then
                this.activeStation = CUSTOM_FIRST
                return notifyDevice(this, evt)
            end
            this.activeStation = VANILLA_LAST - 1
            return wrapped(evt)
        end

        return wrapped(evt)
    end)

    Override("RadioControllerPS", "OnPreviousStation", function(this, evt, wrapped)
        if this.activeStation > VANILLA_LAST then
            this.previousStation = this.activeStation
            this.activeStation = this.activeStation - 1
            if this.activeStation < CUSTOM_FIRST then
                this.activeStation = VANILLA_FIRST_UI
                return wrapped(evt)
            end
            return notifyDevice(this, evt)
        end

        if this.activeStation == VANILLA_FIRST_UI then
            this.previousStation = this.activeStation
            if registry:Count() > 0 then
                this.activeStation = VANILLA_LAST + registry:Count()
            else
                this.activeStation = VANILLA_LAST
            end
            return notifyDevice(this, evt)
        end

        return wrapped(evt)
    end)
end

--- Device setup: report the extended station count and pick a starting
--- station from the combined vanilla + custom range.
function WorldObservers:HookDeviceSetup()
    local registry = self.registry

    Override("RadioControllerPS", "GameAttached", function(this)
        this.amountOfStations = CUSTOM_FIRST + registry:Count()
        this.activeChannelName = RadioStationDataProvider.GetChannelName(this:GetActiveRadioStation())
        this:TryInitializeInteractiveState()
    end)

    Override("RadioControllerPS", "SetDefaultRadioStation", function(this)
        if not this.radioSetup.randomizeStartingStation then
            this.activeStation = this.radioSetup.startingStation
            return
        end
        local upper = math.max(VANILLA_LAST + registry:Count(), VANILLA_LAST)
        this.activeStation = math.random(0, upper)
    end)
end

--- Starting and stopping playback on physical devices.
function WorldObservers:HookPlayback()
    local registry = self.registry
    local worldManager = self.worldManager

    Observe("Radio", "PlayGivenStation", function(this)
        local active = this:GetDevicePS():GetActiveStationIndex()

        if active > VANILLA_LAST then
            local station = registry:GetAtPosition(active - VANILLA_LAST)
            if not station then
                -- Save state pointing at a station that no longer exists.
                worldManager:Release(this)
                return
            end

            GameObject.AudioSwitch(this, "radio_station", "station_none", "radio")
            local emitter = worldManager:FindEmitter(this)
            if emitter then
                emitter:SwitchTo(station)
            else
                worldManager:Acquire(station, this)
            end
        else
            worldManager:Release(this)
        end
    end)

    Observe("Radio", "TurnOffDevice", function(this) worldManager:Release(this) end)
    Observe("Radio", "CutPower", function(this) worldManager:Release(this) end)
    Observe("Radio", "DeactivateDevice", function(this) worldManager:Release(this) end)
    ObserveBefore("Radio", "OnDetach", function(this) worldManager:Release(this) end)
end

--- Station logo and name on the screens of physical radios.
function WorldObservers:HookScreens()
    local registry = self.registry

    Override("RadioInkGameController", "SetupStationLogo", function(this, wrapped)
        local active = this:GetOwner():GetDevicePS():GetActiveStationIndex()

        if active > VANILLA_LAST then
            local station = registry:GetAtPosition(active - VANILLA_LAST)
            if not station then
                inkImageRef.SetAtlasResource(this.stationLogoWidget, ResRef.FromName(DEFAULT_ATLAS))
                wrapped()
                return
            end

            local iconRecord = TweakDBInterface.GetUIIconRecord(station.iconRecord)
            inkImageRef.SetAtlasResource(this.stationLogoWidget, iconRecord:AtlasResourcePath())
            inkImageRef.SetTexturePart(this.stationLogoWidget, iconRecord:AtlasPartName())
        else
            inkImageRef.SetAtlasResource(this.stationLogoWidget, ResRef.FromName(DEFAULT_ATLAS))
            wrapped()
        end
    end)

    ObserveAfter("RadioInkGameController", "TurnOn", function(this)
        local active = this:GetOwner():GetDevicePS():GetActiveStationIndex()
        if active < CUSTOM_FIRST then
            return
        end
        local station = registry:GetAtPosition(active - VANILLA_LAST)
        if station then
            inkTextRef.SetText(this.stationNameWidget, station:GetName())
        end
    end)
end

return WorldObservers
