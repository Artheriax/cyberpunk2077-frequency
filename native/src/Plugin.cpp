#include "Plugin.hpp"

#include "Junction.hpp"
#include "Manifest.hpp"
#include "Scripting/NativeBindings.hpp"

namespace Frequency
{

Plugin& Plugin::Get()
{
    static Plugin instance;
    return instance;
}

std::filesystem::path Plugin::DetectExeDirectory()
{
    wchar_t buffer[MAX_PATH]{};
    GetModuleFileNameW(GetModuleHandle(nullptr), buffer, std::size(buffer));
    return std::filesystem::path(buffer).parent_path();
}

bool Plugin::OnLoad(const RED4ext::v1::Sdk* aSdk, RED4ext::v1::PluginHandle aHandle)
{
    m_sdk = aSdk;
    m_handle = aHandle;
    m_exeDir = DetectExeDirectory();

    // Audioware loads after this plugin (alphabetically), so the depot
    // junctions and the manifest must exist before it parses them.
    EnsureDepotJunctions();
    GenerateBaselineManifest();

    NativeBindings::ScheduleRegistration();
    return true;
}

void Plugin::OnUnload()
{
}

void Plugin::LogInfo(const char* aMessage) const
{
    m_sdk->logger->Info(m_handle, aMessage);
}

void Plugin::LogError(const char* aMessage) const
{
    m_sdk->logger->Error(m_handle, aMessage);
}

std::filesystem::path Plugin::ResolveGamePath(const char* aRelativePath) const
{
    return m_exeDir / std::filesystem::path(aRelativePath);
}

} // namespace Frequency
