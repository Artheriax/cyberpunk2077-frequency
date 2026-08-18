#include "NativeBindings.hpp"

#include "../Manifest.hpp"
#include "../Plugin.hpp"
#include "../ProbeDuration.hpp"
#include "FrequencyScriptClass.hpp"

#include <RED4ext/RTTITypes.hpp>

#include <filesystem>
#include <fstream>
#include <sstream>

namespace Frequency
{

namespace
{
constexpr const char* kVersion = "2.0.0";

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

void HandleGetFiles(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame,
                    RED4ext::DynArray<RED4ext::CString>* aOut, int64_t)
{
    RED4ext::CString path;
    RED4ext::GetParameter(aFrame, &path);

    auto target = Plugin::Get().ResolveGamePath(path.c_str());

    RED4ext::DynArray<RED4ext::CString> files;
    std::error_code ec;
    if (std::filesystem::is_directory(target, ec))
    {
        for (const auto& entry : std::filesystem::directory_iterator(target, ec))
        {
            if (!entry.is_directory())
            {
                files.PushBack(entry.path().filename().string());
            }
        }
    }

    if (aOut)
    {
        RED4ext::CRTTISystem::Get()->GetType("array:String")->Assign(aOut, &files);
    }
    aFrame->code++;
}

void HandleFileExists(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, bool* aOut, int64_t)
{
    RED4ext::CString path;
    RED4ext::GetParameter(aFrame, &path);

    auto target = Plugin::Get().ResolveGamePath(path.c_str());
    std::error_code ec;
    const bool exists = std::filesystem::is_regular_file(target, ec);

    if (aOut)
    {
        RED4ext::CRTTISystem::Get()->GetType("Bool")->Assign(aOut, &exists);
    }
    aFrame->code++;
}

void HandleReadText(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, RED4ext::CString* aOut, int64_t)
{
    RED4ext::CString path;
    RED4ext::GetParameter(aFrame, &path);

    auto target = Plugin::Get().ResolveGamePath(path.c_str());

    RED4ext::CString content;
    std::ifstream stream(target, std::ios::binary);
    if (stream.good())
    {
        std::ostringstream buffer;
        buffer << stream.rdbuf();
        content = buffer.str().c_str();
    }

    if (aOut)
    {
        RED4ext::CRTTISystem::Get()->GetType("String")->Assign(aOut, &content);
    }
    aFrame->code++;
}

void HandleWriteText(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, bool* aOut, int64_t)
{
    RED4ext::CString path;
    RED4ext::CString text;
    RED4ext::GetParameter(aFrame, &path);
    RED4ext::GetParameter(aFrame, &text);

    auto target = Plugin::Get().ResolveGamePath(path.c_str());

    bool ok = false;
    std::ofstream stream(target, std::ios::binary | std::ios::trunc);
    if (stream.good())
    {
        stream.write(text.c_str(), static_cast<std::streamsize>(text.Length()));
        ok = stream.good();
    }

    if (aOut)
    {
        RED4ext::CRTTISystem::Get()->GetType("Bool")->Assign(aOut, &ok);
    }
    aFrame->code++;
}

void HandleProbeDuration(RED4ext::IScriptable*, RED4ext::CStackFrame* aFrame, int32_t* aOut, int64_t)
{
    RED4ext::CString path;
    RED4ext::GetParameter(aFrame, &path);

    auto target = Plugin::Get().ResolveGamePath(path.c_str());
    const auto length = static_cast<int32_t>(Frequency::ProbeDurationMs(target.string()));

    if (aOut)
    {
        RED4ext::CRTTISystem::Get()->GetType("Int32")->Assign(aOut, &length);
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
    RegisterIoFunctions();
}

void NativeBindings::RegisterInfoFunctions()
{
    auto getVersion = MakeStatic("GetVersion", &HandleGetVersion);
    getVersion->SetReturnType("String");

    auto probeDuration = MakeStatic("ProbeDuration", &HandleProbeDuration);
    probeDuration->AddParam("String", "path");
    probeDuration->SetReturnType("Int32");

    g_frequencyClass.RegisterFunction(getVersion);
    g_frequencyClass.RegisterFunction(probeDuration);
}

void NativeBindings::RegisterIoFunctions()
{
    auto getFolders = MakeStatic("GetFolders", &HandleGetFolders);
    getFolders->AddParam("String", "path");
    getFolders->SetReturnType("array:String");

    auto getFiles = MakeStatic("GetFiles", &HandleGetFiles);
    getFiles->AddParam("String", "path");
    getFiles->SetReturnType("array:String");

    auto fileExists = MakeStatic("FileExists", &HandleFileExists);
    fileExists->AddParam("String", "path");
    fileExists->SetReturnType("Bool");

    auto readText = MakeStatic("ReadText", &HandleReadText);
    readText->AddParam("String", "path");
    readText->SetReturnType("String");

    auto writeText = MakeStatic("WriteText", &HandleWriteText);
    writeText->AddParam("String", "path");
    writeText->AddParam("String", "text");
    writeText->SetReturnType("Bool");

    g_frequencyClass.RegisterFunction(getFolders);
    g_frequencyClass.RegisterFunction(getFiles);
    g_frequencyClass.RegisterFunction(fileExists);
    g_frequencyClass.RegisterFunction(readText);
    g_frequencyClass.RegisterFunction(writeText);
}

} // namespace Frequency
