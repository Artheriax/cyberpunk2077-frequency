#include "NativeBindings.hpp"

#include "../Audio/AudioEngine.hpp"
#include "../Audio/ChannelBank.hpp"
#include "../Plugin.hpp"
#include "FrequencyScriptClass.hpp"

#include <RED4ext/RTTITypes.hpp>

#include <algorithm>
#include <filesystem>

namespace Frequency
{

namespace
{
constexpr const char* kVersion = "1.0.0";

// ---------------------------------------------------------------------------
// Function handlers
// ---------------------------------------------------------------------------

void HandleGetVersion(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, RED4ext::CString* aOut, int64_t)
{
    RED4ext::CString version = kVersion;
    if (aOut)
    {
        RED4ext::CRTTISystem::Get()->GetType("String")->Assign(aOut, &version);
    }
    aFrame->code++;
}

void HandleGetNumChannels(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, int32_t* aOut, int64_t)
{
    auto count = Plugin::Get().Channels().Count();
    if (aOut)
    {
        RED4ext::CRTTISystem::Get()->GetType("Int32")->Assign(aOut, &count);
    }
    aFrame->code++;
}

void HandleGetFolders(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame,
                      RED4ext::DynArray<RED4ext::CString>* aOut, int64_t)
{
    RED4ext::CString path;
    RED4ext::GetParameter(aFrame, &path);

    auto target = Plugin::Get().ResolveGamePath(path.c_str());

    RED4ext::DynArray<RED4ext::CString> folders;
    std::error_code ec;
    if (std::filesystem::is_directory(target, ec))
    {
        for (const auto& entry : std::filesystem::directory_iterator(target, ec))
        {
            if (entry.is_directory())
            {
                folders.PushBack(entry.path().filename().string());
            }
        }
    }

    if (aOut)
    {
        RED4ext::CRTTISystem::Get()->GetType("array:String")->Assign(aOut, &folders);
    }
    aFrame->code++;
}

void HandleGetSongLength(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, int32_t* aOut, int64_t)
{
    RED4ext::CString path;
    RED4ext::GetParameter(aFrame, &path);

    auto target = Plugin::Get().ResolveGamePath(path.c_str());
    auto length = static_cast<int32_t>(Plugin::Get().Engine().ProbeLengthMs(target.string()));

    if (aOut)
    {
        RED4ext::CRTTISystem::Get()->GetType("Int32")->Assign(aOut, &length);
    }
    aFrame->code++;
}

void HandlePlay(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, float*, int64_t)
{
    int32_t channelId;
    RED4ext::CString path;
    int32_t startPos;
    float volume;
    float fade;
    RED4ext::GetParameter(aFrame, &channelId);
    RED4ext::GetParameter(aFrame, &path);
    RED4ext::GetParameter(aFrame, &startPos);
    RED4ext::GetParameter(aFrame, &volume);
    RED4ext::GetParameter(aFrame, &fade);

    Plugin::Get().Channels().Play(channelId, path.c_str(), startPos, volume, fade);
    aFrame->code++;
}

void HandleStop(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, float*, int64_t)
{
    int32_t channelId;
    RED4ext::GetParameter(aFrame, &channelId);

    Plugin::Get().Channels().Stop(channelId);
    aFrame->code++;
}

void HandleSetVolume(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, float*, int64_t)
{
    int32_t channelId;
    float volume;
    RED4ext::GetParameter(aFrame, &channelId);
    RED4ext::GetParameter(aFrame, &volume);

    Plugin::Get().Channels().SetVolume(channelId, std::max(0.0f, volume));
    aFrame->code++;
}

void HandleSetListener(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, float*, int64_t)
{
    RED4ext::Vector4 pos;
    RED4ext::Vector4 forward;
    RED4ext::Vector4 up;
    RED4ext::GetParameter(aFrame, &pos);
    RED4ext::GetParameter(aFrame, &forward);
    RED4ext::GetParameter(aFrame, &up);

    Plugin::Get().Engine().SetListener(AudioEngine::ToFmodVector(pos), AudioEngine::ToFmodVector(forward),
                                       AudioEngine::ToFmodVector(up));
    aFrame->code++;
}

void HandleSetChannelPos(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, float*, int64_t)
{
    int32_t channelId;
    RED4ext::Vector4 pos;
    RED4ext::GetParameter(aFrame, &channelId);
    RED4ext::GetParameter(aFrame, &pos);

    Plugin::Get().Channels().SetChannelPosition(channelId, AudioEngine::ToFmodVector(pos));
    aFrame->code++;
}

void HandleSet3DFalloff(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, float*, int64_t)
{
    float falloff;
    RED4ext::GetParameter(aFrame, &falloff);

    Plugin::Get().Engine().SetFalloff(falloff);
    aFrame->code++;
}

void HandleSetMinMax(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, float*, int64_t)
{
    float minDistance;
    float maxDistance;
    RED4ext::GetParameter(aFrame, &minDistance);
    RED4ext::GetParameter(aFrame, &maxDistance);

    Plugin::Get().Channels().SetMinMaxDistance(minDistance, maxDistance);
    aFrame->code++;
}

void HandleIsChannelActive(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, bool* aOut, int64_t)
{
    int32_t channelId;
    RED4ext::GetParameter(aFrame, &channelId);

    bool active = Plugin::Get().Channels().IsChannelActive(channelId);
    if (aOut)
    {
        RED4ext::CRTTISystem::Get()->GetType("Bool")->Assign(aOut, &active);
    }
    aFrame->code++;
}

template <typename THandler>
RED4ext::CClassStaticFunction* MakeStatic(const char* aShortName, THandler aHandler)
{
    return RED4ext::CClassStaticFunction::Create(&g_frequencyClass, aShortName, aShortName, aHandler,
                                                 {.isNative = true, .isStatic = true});
}

} // anonymous namespace

// ---------------------------------------------------------------------------
// Registration
// ---------------------------------------------------------------------------

void NativeBindings::ScheduleRegistration()
{
    auto rtti = RED4ext::CRTTISystem::Get();
    rtti->AddRegisterCallback(&NativeBindings::RegisterTypes);
    rtti->AddPostRegisterCallback(&NativeBindings::PostRegisterTypes);
}

void NativeBindings::RegisterTypes()
{
    RED4ext::CNamePool::Add("Frequency");

    g_frequencyClass.flags = {.isNative = true};
    RED4ext::CRTTISystem::Get()->RegisterType(&g_frequencyClass);
}

void NativeBindings::PostRegisterTypes()
{
    g_frequencyClass.parent = RED4ext::CRTTISystem::Get()->GetClass("IScriptable");

    RegisterInfoFunctions();
    RegisterAudioFunctions();
}

void NativeBindings::RegisterInfoFunctions()
{
    auto getVersion = MakeStatic("GetVersion", &HandleGetVersion);
    getVersion->SetReturnType("String");

    auto getNumChannels = MakeStatic("GetNumChannels", &HandleGetNumChannels);
    getNumChannels->SetReturnType("Int32");

    auto getFolders = MakeStatic("GetFolders", &HandleGetFolders);
    getFolders->AddParam("String", "path");
    getFolders->SetReturnType("array:String");

    auto getSongLength = MakeStatic("GetSongLength", &HandleGetSongLength);
    getSongLength->AddParam("String", "path");
    getSongLength->SetReturnType("Int32");

    auto isChannelActive = MakeStatic("IsChannelActive", &HandleIsChannelActive);
    isChannelActive->AddParam("Int32", "channelID");
    isChannelActive->SetReturnType("Bool");

    g_frequencyClass.RegisterFunction(getVersion);
    g_frequencyClass.RegisterFunction(getNumChannels);
    g_frequencyClass.RegisterFunction(getFolders);
    g_frequencyClass.RegisterFunction(getSongLength);
    g_frequencyClass.RegisterFunction(isChannelActive);
}

void NativeBindings::RegisterAudioFunctions()
{
    auto play = MakeStatic("Play", &HandlePlay);
    play->AddParam("Int32", "channelID");
    play->AddParam("String", "path");
    play->AddParam("Int32", "startPos"); // -1 opens the path as a web stream
    play->AddParam("Float", "volume");
    play->AddParam("Float", "fade");

    auto stop = MakeStatic("Stop", &HandleStop);
    stop->AddParam("Int32", "channelID");

    auto setVolume = MakeStatic("SetVolume", &HandleSetVolume);
    setVolume->AddParam("Int32", "channelID");
    setVolume->AddParam("Float", "volume");

    auto setListener = MakeStatic("SetListener", &HandleSetListener);
    setListener->AddParam("Vector4", "pos");
    setListener->AddParam("Vector4", "forward");
    setListener->AddParam("Vector4", "up");

    auto setChannelPos = MakeStatic("SetChannelPos", &HandleSetChannelPos);
    setChannelPos->AddParam("Int32", "channelID");
    setChannelPos->AddParam("Vector4", "pos");

    auto setFalloff = MakeStatic("Set3DFalloff", &HandleSet3DFalloff);
    setFalloff->AddParam("Float", "falloff");

    auto setMinMax = MakeStatic("SetMinMax", &HandleSetMinMax);
    setMinMax->AddParam("Float", "min");
    setMinMax->AddParam("Float", "max");

    g_frequencyClass.RegisterFunction(play);
    g_frequencyClass.RegisterFunction(stop);
    g_frequencyClass.RegisterFunction(setVolume);
    g_frequencyClass.RegisterFunction(setListener);
    g_frequencyClass.RegisterFunction(setChannelPos);
    g_frequencyClass.RegisterFunction(setFalloff);
    g_frequencyClass.RegisterFunction(setMinMax);
}

} // namespace Frequency
