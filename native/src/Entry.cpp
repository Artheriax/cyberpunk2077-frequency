/*
    Frequency - Entry.cpp

    RED4ext plugin entry points. Wires the Plugin singleton into the
    loader lifecycle and pumps the audio engine from the Running game state.
*/

#include "Audio/AudioEngine.hpp"
#include "Audio/ChannelBank.hpp"
#include "Plugin.hpp"

namespace
{

bool OnRunningEnter(RED4ext::CGameApplication*)
{
    return true;
}

bool OnRunningUpdate(RED4ext::CGameApplication*)
{
    auto& plugin = Frequency::Plugin::Get();
    plugin.Channels().TickAll();
    plugin.Engine().Update();
    return false;
}

bool OnRunningExit(RED4ext::CGameApplication*)
{
    Frequency::Plugin::Get().Channels().ShutdownAll();
    return true;
}

} // anonymous namespace

RED4EXT_C_EXPORT bool RED4EXT_CALL Main(RED4ext::v1::PluginHandle aHandle, RED4ext::v1::EMainReason aReason,
                                        const RED4ext::v1::Sdk* aSdk)
{
    switch (aReason)
    {
    case RED4ext::v1::EMainReason::Load:
    {
        auto& plugin = Frequency::Plugin::Get();
        if (!plugin.OnLoad(aSdk, aHandle))
        {
            return false;
        }

        RED4ext::v1::GameState runningState;
        runningState.OnEnter = &OnRunningEnter;
        runningState.OnUpdate = &OnRunningUpdate;
        runningState.OnExit = &OnRunningExit;
        aSdk->gameStates->Add(aHandle, RED4ext::EGameStateType::Running, &runningState);
        break;
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
    aInfo->version = RED4EXT_V1_SEMVER(1, 0, 0);
    aInfo->runtime = RED4EXT_V1_RUNTIME_VERSION_INDEPENDENT;
    aInfo->sdk = RED4EXT_V1_SDK_VERSION_CURRENT;
}

RED4EXT_C_EXPORT uint32_t RED4EXT_CALL Supports()
{
    return RED4EXT_API_VERSION_1;
}
