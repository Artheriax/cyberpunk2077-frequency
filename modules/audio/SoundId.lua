--[[
    Frequency - SoundId.lua

    Deterministic mapping from a song's depot-relative path to its
    Audioware manifest sound id. The native plugin's baseline manifest
    generator (native/src/Manifest.cpp) and this module must agree
    exactly.

    Written from scratch for Frequency.
]]

local SoundId = {}

SoundId.PREFIX = "freq"

local function hash8(text)
    local h = 5381
    for i = 1, #text do
        h = (h * 33 + text:byte(i)) % 4294967296
    end
    return string.format("%x", h)
end

function SoundId.FromPath(depotRelativePath)
    local id = SoundId.PREFIX .. "_" .. depotRelativePath:gsub("[^%w]+", "_"):lower()
    if #id > 240 then
        id = id:sub(1, 224) .. "_" .. hash8(id)
    end
    return id
end

return SoundId
