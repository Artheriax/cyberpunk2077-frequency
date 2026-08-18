#include "Junction.hpp"

#include "Plugin.hpp"

#include <windows.h>

#include <vector>

namespace Frequency
{

bool CreateJunction(const std::wstring& aLink, const std::wstring& aTarget)
{
    std::error_code ec;
    std::filesystem::remove(aLink, ec);

    // `mklink /J` creates a directory junction, which needs no elevation
    // and no developer mode (unlike symlinks).
    std::wstring command = L"cmd /C mklink /J \"" + aLink + L"\" \"" + aTarget + L"\"";

    std::vector<wchar_t> buffer(command.begin(), command.end());
    buffer.push_back(L'\0');

    STARTUPINFOW startupInfo{};
    startupInfo.cb = sizeof(startupInfo);
    PROCESS_INFORMATION processInfo{};

    if (!CreateProcessW(nullptr, buffer.data(), nullptr, nullptr, FALSE, CREATE_NO_WINDOW, nullptr, nullptr,
                        &startupInfo, &processInfo))
    {
        return false;
    }

    WaitForSingleObject(processInfo.hProcess, INFINITE);
    DWORD exitCode = 0;
    GetExitCodeProcess(processInfo.hProcess, &exitCode);
    CloseHandle(processInfo.hThread);
    CloseHandle(processInfo.hProcess);

    if (exitCode != 0)
    {
        return false;
    }
    return std::filesystem::exists(aLink, ec);
}

void EnsureDepotJunctions()
{
    auto& plugin = Plugin::Get();

    const auto depot = plugin.ExeDirectory() / L"..\\..\\r6\\audioware\\Frequency";
    std::error_code ec;
    std::filesystem::create_directories(depot, ec);

    const auto radiosLink = depot / L"radios";
    const auto legacyLink = depot / L"legacy";

    if (!std::filesystem::exists(radiosLink, ec))
    {
        const auto target = plugin.ExeDirectory() / L"plugins\\cyber_engine_tweaks\\mods\\Frequency\\radios";
        if (!CreateJunction(radiosLink.wstring(), target.wstring()))
        {
            plugin.LogError("Failed to create the Frequency radios depot junction.");
        }
    }

    if (!std::filesystem::exists(legacyLink, ec))
    {
        const auto target = plugin.ExeDirectory() / L"plugins\\cyber_engine_tweaks\\mods\\radioExt\\radios";
        if (std::filesystem::exists(target, ec))
        {
            CreateJunction(legacyLink.wstring(), target.wstring());
        }
    }
}

} // namespace Frequency
