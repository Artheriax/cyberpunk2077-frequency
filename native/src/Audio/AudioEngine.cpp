#include "AudioEngine.hpp"

#include "../Plugin.hpp"
#include <fmod_errors.h>

namespace Frequency
{

namespace
{
constexpr float kDefaultFalloff = 0.325f;
}

bool AudioEngine::Initialize()
{
    auto& plugin = Plugin::Get();

    auto createResult = FMOD::System_Create(&m_system);
    plugin.Sdk()->logger->InfoF(plugin.Handle(), "FMOD::System_Create: %s", FMOD_ErrorString(createResult));
    if (createResult != FMOD_OK || m_system == nullptr)
    {
        return false;
    }

    auto initResult = m_system->init(kChannelCount, FMOD_INIT_3D_RIGHTHANDED, nullptr);
    plugin.Sdk()->logger->InfoF(plugin.Handle(), "FMOD::System::init: %s", FMOD_ErrorString(initResult));
    if (initResult != FMOD_OK)
    {
        return false;
    }

    m_system->set3DSettings(1.0f, 1.0f, kDefaultFalloff);
    return true;
}

void AudioEngine::Shutdown()
{
    if (m_system == nullptr)
    {
        return;
    }
    m_system->close();
    m_system->release();
    m_system = nullptr;
}

void AudioEngine::Update()
{
    if (m_system)
    {
        m_system->update();
    }
}

uint32_t AudioEngine::ProbeLengthMs(const std::string& aAbsolutePath) const
{
    if (m_system == nullptr)
    {
        return 0;
    }

    FMOD::Sound* sound = nullptr;
    auto createResult = m_system->createSound(aAbsolutePath.c_str(), FMOD_CREATESTREAM, nullptr, &sound);
    if (createResult != FMOD_OK || sound == nullptr)
    {
        Plugin::Get().Sdk()->logger->ErrorF(Plugin::Get().Handle(),
            "FMOD::System::createSound (probe): %s. Path: %s",
            FMOD_ErrorString(createResult), aAbsolutePath.c_str());
        return 0;
    }

    uint32_t length = 0;
    auto lengthResult = sound->getLength(&length, FMOD_TIMEUNIT_MS);
    if (lengthResult != FMOD_OK)
    {
        Plugin::Get().Sdk()->logger->ErrorF(Plugin::Get().Handle(),
            "FMOD::Sound::getLength: %s. Path: %s",
            FMOD_ErrorString(lengthResult), aAbsolutePath.c_str());
    }

    sound->release();
    return length;
}

void AudioEngine::SetListener(const FMOD_VECTOR& aPos, const FMOD_VECTOR& aForward, const FMOD_VECTOR& aUp)
{
    if (m_system == nullptr)
    {
        return;
    }
    FMOD_VECTOR velocity{};
    LogFmodError(m_system->set3DListenerAttributes(0, &aPos, &velocity, &aForward, &aUp),
                 "set3DListenerAttributes");
}

void AudioEngine::SetFalloff(float aFalloff)
{
    if (m_system == nullptr)
    {
        return;
    }
    LogFmodError(m_system->set3DSettings(1.0f, 1.0f, aFalloff), "set3DSettings");
}

void AudioEngine::LogFmodError(FMOD_RESULT aResult, const char* aContext) const
{
    if (aResult != FMOD_OK)
    {
        Plugin::Get().Sdk()->logger->ErrorF(Plugin::Get().Handle(), "%s: %s", aContext, FMOD_ErrorString(aResult));
    }
}

FMOD_VECTOR AudioEngine::ToFmodVector(const RED4ext::Vector4& aVec)
{
    auto vector4Class = RED4ext::CRTTISystem::Get()->GetClass("Vector4");
    auto xProp = vector4Class->GetProperty("X");
    auto yProp = vector4Class->GetProperty("Y");
    auto zProp = vector4Class->GetProperty("Z");

    auto& mutableVec = const_cast<RED4ext::Vector4&>(aVec);

    FMOD_VECTOR result;
    result.x = -xProp->GetValue<float>(&mutableVec);
    result.y = zProp->GetValue<float>(&mutableVec);
    result.z = yProp->GetValue<float>(&mutableVec);
    return result;
}

} // namespace Frequency
