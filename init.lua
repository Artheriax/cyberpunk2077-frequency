--[[
    Frequency
    =========
    A Cyberpunk 2077 mod that adds fully custom radio stations (local files
    or web streams) to the vehicle radio, the pocket radio, and physical
    radios placed in the world.

    Ground-up rewrite by Artheriax. Not affiliated with, and containing no
    code from, the original radioExt mod.

    CET entry point: wires up the services, registers the game hooks, and
    exposes the console API via GetMod("Frequency") (served from the chunk's
    return value below).
]]

local Class = require("modules/core/Class")
local ModPaths = require("modules/core/ModPaths")

local Logger = require("modules/core/Logger")
local Scheduler = require("modules/core/Scheduler")
local Session = require("modules/core/Session")
local Files = require("modules/core/Files")
local GameAudioSettings = require("modules/core/GameAudioSettings")

local NativeBridge = require("modules/audio/NativeBridge")
local AudioEngine = require("modules/audio/AudioEngine")

local ModConfig = require("modules/config/ModConfig")
local GroupConfig = require("modules/config/GroupConfig")
local MetadataLoader = require("modules/config/MetadataLoader")
local ModSettings = require("modules/config/ModSettings")

local StationRegistry = require("modules/stations/StationRegistry")
local VehicleRadioManager = require("modules/vehicle/VehicleRadioManager")
local VehicleObservers = require("modules/vehicle/VehicleObservers")
local WorldRadioManager = require("modules/world/WorldRadioManager")
local WorldObservers = require("modules/world/WorldObservers")
local ConsoleApi = require("modules/api/ConsoleApi")

local FrequencyMod = Class.define("FrequencyMod")

function FrequencyMod:initialize()
    self.ready = false

    -- Services -----------------------------------------------------------
    self.logger = Logger()
    self.scheduler = Scheduler()
    self.session = Session()
    self.nativeBridge = NativeBridge(self.logger)
    self.files = Files(self.nativeBridge, self.logger)
    self.audioSettings = GameAudioSettings()
    self.audio = AudioEngine(self.nativeBridge, self.audioSettings, self.logger)

    self.modConfig = ModConfig(self.files, self.logger)
    self.groupConfig = GroupConfig(self.files, self.logger)
    self.metadataLoader = MetadataLoader(self.files, self.logger)

    self.registry = StationRegistry({
        logger = self.logger,
        files = self.files,
        audio = self.audio,
        scheduler = self.scheduler,
        metadataLoader = self.metadataLoader,
        groupConfig = self.groupConfig,
        modConfig = self.modConfig,
    })

    self.vehicleManager = VehicleRadioManager({
        logger = self.logger,
        scheduler = self.scheduler,
        registry = self.registry,
        session = self.session,
    })

    self.worldManager = WorldRadioManager({
        logger = self.logger,
        audio = self.audio,
        registry = self.registry,
    })

    self.vehicleObservers = VehicleObservers({
        logger = self.logger,
        scheduler = self.scheduler,
        registry = self.registry,
        vehicleManager = self.vehicleManager,
    })

    self.worldObservers = WorldObservers({
        logger = self.logger,
        registry = self.registry,
        worldManager = self.worldManager,
    })

    self.modSettings = ModSettings({
        logger = self.logger,
        registry = self.registry,
        groupConfig = self.groupConfig,
        modConfig = self.modConfig,
        worldManager = self.worldManager,
    })

    self.api = ConsoleApi({
        logger = self.logger,
        nativeBridge = self.nativeBridge,
        registry = self.registry,
        groupConfig = self.groupConfig,
        vehicleManager = self.vehicleManager,
        worldManager = self.worldManager,
        modSettings = self.modSettings,
    })

    self.trainSystem = nil
end

function FrequencyMod:RegisterEvents()
    registerForEvent("onInit", function()
        self:OnInit()
    end)

    registerForEvent("onShutdown", function()
        self:OnShutdown()
    end)

    registerForEvent("onUpdate", function(deltaTime)
        self:OnUpdate(deltaTime)
    end)
end

function FrequencyMod:OnInit()
    math.randomseed(os.clock())

    if not self.nativeBridge:Validate() then
        return
    end

    -- Re-pin the native reference now that CET has registered the native
    -- class global; it was not resolvable while init.lua was loading.
    self.api.Native = self.nativeBridge:Get()

    self.modConfig:Load()
    self.groupConfig:Load()

    self.registry:LoadAll()

    self.vehicleObservers:Register()
    self.worldObservers:Register()

    self.session:OnSessionStart(function()
        -- session started; nothing to preload, stations simulate on their own
    end)

    self.session:OnSessionEnd(function()
        self.registry:StopAllPlayback()
        self.worldManager:ReleaseAll()
    end)

    self.trainSystem = GetMod("trainSystem")
    self.session:RegisterHooks()
    self.session:Refresh() -- in case CET reloaded all mods mid-session

    -- Optional Native Settings UI tab (no-op when the mod is missing).
    self.modSettings:Register()

    -- Companion mods reach the API through GetMod("Frequency"), which CET
    -- serves from this chunk's return value. The sandboxed environment does
    -- not expose `_G`, so a console global cannot be published here.
    self.ready = true
    self.logger:Infof("Initialized with %d station(s). Type Frequency.Help() for console commands.", self.registry:Count())
end

function FrequencyMod:OnShutdown()
    if not self.ready then
        return
    end
    self.registry:StopAllPlayback()
    self.worldManager:ReleaseAll()
end

function FrequencyMod:OnUpdate(deltaTime)
    self.session:Update()

    if not self.ready then
        return
    end

    if self.session:IsInGame() and not self.session:IsInMenu() then
        self.scheduler:Update(deltaTime)
        self.vehicleManager:Update()
        self.worldManager:Update()
        self.vehicleManager:HandleTrainSystem(self.trainSystem)
    else
        self.vehicleManager:HandleMenu()
        self.worldManager:HandleMenu()
    end
end

local mod = FrequencyMod()
mod:RegisterEvents()
return mod.api
