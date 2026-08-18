#include "Manifest.hpp"

#include "Plugin.hpp"

#include <algorithm>
#include <cctype>
#include <fstream>
#include <set>
#include <string>

namespace Frequency
{

namespace
{

const std::set<std::string> kSongExtensions = {
    ".mp3", ".mp2", ".flac", ".ogg", ".wav", ".wax", ".wma", ".opus", ".aiff", ".aif", ".aifc",
};

bool IsSongFile(const std::string& aName)
{
    const auto pos = aName.find_last_of('.');
    if (pos == std::string::npos)
    {
        return false;
    }
    std::string ext = aName.substr(pos);
    std::transform(ext.begin(), ext.end(), ext.begin(),
                   [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    return kSongExtensions.contains(ext);
}

/// Mirrors `SoundId.FromPath` in modules/audio/SoundId.lua exactly.
std::string SoundId(const std::string& aDepotRelativePath)
{
    std::string id = "freq_";
    for (const char c : aDepotRelativePath)
    {
        const auto uc = static_cast<unsigned char>(c);
        if (std::isalnum(uc))
        {
            id.push_back(static_cast<char>(std::tolower(uc)));
        }
        else
        {
            id.push_back('_');
        }
    }
    return id;
}

std::string YamlQuote(const std::string& aText)
{
    std::string out = "\"";
    for (const char c : aText)
    {
        if (c == '\\' || c == '"')
        {
            out.push_back('\\');
        }
        out.push_back(c);
    }
    out.push_back('"');
    return out;
}

void AppendStationSongs(const std::filesystem::path& aStationDir, const std::string& aManifestFolder,
                        std::string& aYaml, std::set<std::string>& aIds)
{
    std::error_code ec;
    for (const auto& entry : std::filesystem::directory_iterator(aStationDir, ec))
    {
        if (!entry.is_regular_file(ec) || !IsSongFile(entry.path().filename().string()))
        {
            continue;
        }

        const std::string fileName = entry.path().filename().string();
        const std::string stationId = aStationDir.filename().string();
        const std::string relative = aManifestFolder + "/" + stationId + "/" + fileName;
        const std::string id = SoundId(relative);
        if (!aIds.insert(id).second)
        {
            continue; // duplicate id; the first entry wins
        }

        aYaml += "  " + id + ":\n";
        aYaml += "    file: " + YamlQuote(relative) + "\n";
        aYaml += "    captions: []\n";
        aYaml += "    settings:\n";
        aYaml += "      volume: 1.0\n";
    }
}

void ScanRoot(const std::filesystem::path& aRoot, const std::string& aManifestFolder, std::string& aYaml,
              std::set<std::string>& aIds)
{
    std::error_code ec;
    if (!std::filesystem::is_directory(aRoot, ec))
    {
        return;
    }
    for (const auto& entry : std::filesystem::directory_iterator(aRoot, ec))
    {
        if (entry.is_directory(ec))
        {
            AppendStationSongs(entry.path(), aManifestFolder, aYaml, aIds);
        }
    }
}

} // anonymous namespace

void GenerateBaselineManifest()
{
    auto& plugin = Plugin::Get();

    const auto exeDir = plugin.ExeDirectory();
    const auto ownRoot = exeDir / L"plugins\\cyber_engine_tweaks\\mods\\Frequency\\radios";
    const auto legacyRoot = exeDir / L"plugins\\cyber_engine_tweaks\\mods\\radioExt\\radios";

    std::set<std::string> ids;
    std::string yaml = "version: 1.0.0\njingles:\n";

    ScanRoot(ownRoot, "radios", yaml, ids);
    ScanRoot(legacyRoot, "legacy", yaml, ids);

    const auto manifestPath = exeDir / L"..\\..\\r6\\audioware\\Frequency\\audios.yml";
    std::error_code ec;
    std::filesystem::create_directories(manifestPath.parent_path(), ec);

    std::ofstream stream(manifestPath, std::ios::binary | std::ios::trunc);
    if (stream.good())
    {
        stream << yaml;
    }
    else
    {
        plugin.LogError("Failed to write the Audioware baseline manifest.");
    }
}

} // namespace Frequency
