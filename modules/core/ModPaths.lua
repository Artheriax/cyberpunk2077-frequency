--[[
    Frequency - ModPaths.lua

    Central definition of every path the mod uses, so renaming or moving
    folders only ever happens here.

    Layout inside the game directory:
      bin/x64/plugins/cyber_engine_tweaks/mods/Frequency/   <- CET side
      red4ext/plugins/Frequency/Frequency.dll + fmod.dll    <- native side

    Written from scratch for Frequency.
]]

local ModPaths = {
    -- Name of the CET mod folder. Everything user-facing hangs off this.
    ModFolder = "Frequency",

    -- Folder (inside the CET mod dir) holding one subfolder per station.
    RadiosFolder = "radios",

    -- Legacy radioExt radios folder, imported automatically when present
    -- and enabled in config.json (drop-in compatibility).
    LegacyModFolder = "radioExt",
}

-- Native calls resolve relative paths against the game's bin/x64 directory,
-- where the CET mods folder lives under plugins/cyber_engine_tweaks/mods.
function ModPaths.NativeRelative(pathInsideMod)
    return "plugins\\cyber_engine_tweaks\\mods\\" .. ModPaths.ModFolder .. "\\" .. pathInsideMod
end

function ModPaths.NativeRelativeLegacy(pathInsideLegacyMod)
    return "plugins\\cyber_engine_tweaks\\mods\\" .. ModPaths.LegacyModFolder .. "\\" .. pathInsideLegacyMod
end

function ModPaths.StationFolder(stationId)
    return ModPaths.RadiosFolder .. "/" .. stationId
end

function ModPaths.MetadataFile(stationId)
    return ModPaths.StationFolder(stationId) .. "/metadata.json"
end

return ModPaths
