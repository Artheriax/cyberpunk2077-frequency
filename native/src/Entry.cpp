/*
    Frequency - Entry.cpp

    RED4ext plugin entry points.
*/

#include "Plugin.hpp"

RED4EXT_C_EXPORT bool RED4EXT_CALL Main(RED4ext::v1::PluginHandle aHandle, RED4ext::v1::EMainReason aReason,
                                        const RED4ext::v1::Sdk* aSdk)
{
    switch (aReason)
    {
    case RED4ext::v1::EMainReason::Load:
    {
        return Frequency::Plugin::Get().OnLoad(aSdk, aHandle);
    }
    case RED4ext::v1::EMainReason::Unload:
    {
        Frequency::Plugin::Get().OnUnload();
        break;
    }
    }

    return true;
}

RED4EXT_C_EXPORT void RED4EXT_CALL Query(RED4ext::v1::PluginInfo* aInfo)
{
    aInfo->name = L"Frequency";
    aInfo->author = L"Artheriax";
    aInfo->version = RED4EXT_V1_SEMVER(2, 0, 0);
    aInfo->runtime = RED4EXT_V1_RUNTIME_VERSION_INDEPENDENT;
    aInfo->sdk = RED4EXT_V1_SDK_VERSION_CURRENT;
}

RED4EXT_C_EXPORT uint32_t RED4EXT_CALL Supports()
{
    return RED4EXT_API_VERSION_1;
}
