#include "Plugin.hpp"

#include "Audio/AudioEngine.hpp"
#include "Audio/ChannelBank.hpp"
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

    m_engine = std::make_unique<AudioEngine>();
    if (!m_engine->Initialize())
    {
        LogError("Failed to initialize the audio engine.");
        return false;
    }

    m_channels = std::make_unique<ChannelBank>(*m_engine);

    NativeBindings::ScheduleRegistration();
    return true;
}

void Plugin::OnUnload()
{
    if (m_channels)
    {
        m_channels->ShutdownAll();
    }
    if (m_engine)
    {
        m_engine->Shutdown();
    }
    m_channels.reset();
    m_engine.reset();
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
