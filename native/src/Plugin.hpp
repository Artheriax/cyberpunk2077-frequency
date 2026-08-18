#ifndef FREQUENCY_PLUGIN_HPP
#define FREQUENCY_PLUGIN_HPP

#include <RED4ext/RED4ext.hpp>
#include <filesystem>

namespace Frequency
{

/// Central plugin object: owns the RED4ext handles and the game executable
/// path. Lives for the whole plugin lifetime.
class Plugin
{
public:
    static Plugin& Get();

    Plugin(const Plugin&) = delete;
    Plugin& operator=(const Plugin&) = delete;

    bool OnLoad(const RED4ext::v1::Sdk* aSdk, RED4ext::v1::PluginHandle aHandle);
    void OnUnload();

    const RED4ext::v1::Sdk* Sdk() const { return m_sdk; }
    RED4ext::v1::PluginHandle Handle() const { return m_handle; }
    const std::filesystem::path& ExeDirectory() const { return m_exeDir; }

    void LogInfo(const char* aMessage) const;
    void LogError(const char* aMessage) const;

    /// Resolves a bin/x64-relative path (as passed from CET) to absolute.
    std::filesystem::path ResolveGamePath(const char* aRelativePath) const;

private:
    Plugin() = default;

    static std::filesystem::path DetectExeDirectory();

    const RED4ext::v1::Sdk* m_sdk = nullptr;
    RED4ext::v1::PluginHandle m_handle = nullptr;
    std::filesystem::path m_exeDir;
};

} // namespace Frequency

#endif // FREQUENCY_PLUGIN_HPP
