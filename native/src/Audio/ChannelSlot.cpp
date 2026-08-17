#include "ChannelSlot.hpp"

#include "../Plugin.hpp"
#include "AudioEngine.hpp"
#include "../FmodUtils.hpp"
#include <fmod_studio_errors.h>

#include <algorithm>

namespace Frequency
{

ChannelSlot::ChannelSlot(AudioEngine& aEngine, int32_t aSlotIndex)
    : m_engine(aEngine)
    , m_slotIndex(aSlotIndex)
{
}

void ChannelSlot::RequestPlay(const std::string& aResolvedPath, int32_t aStartPosMs, float aVolume,
                              float aFadeSeconds, bool aIsStream)
{
    auto& plugin = Plugin::Get();
    plugin.Sdk()->logger->InfoF(plugin.Handle(), "Play(slot %i, \"%s\", %i, %.2f, %.2f)",
                                m_slotIndex, aResolvedPath.c_str(), aStartPosMs, aVolume, aFadeSeconds);

    if (m_pending.requested)
    {
        return; // already loading on this slot
    }

    // A new request replaces any half-loaded sound.
    m_pending.Reset();

    FMOD_MODE mode = (m_slotIndex == 0) ? FMOD_DEFAULT : FMOD_3D;
    RED4EXT_UNUSED_PARAMETER(aIsStream);

    auto result = m_engine.System()->createStream(aResolvedPath.c_str(), mode | FMOD_NONBLOCKING, nullptr,
                                                  &m_pending.sound);
    if (result != FMOD_OK)
    {
        plugin.Sdk()->logger->ErrorF(plugin.Handle(), "FMOD::System::createStream: %s", FMOD_ErrorString(result));
        TrackFailure(aResolvedPath);
        m_pending.Reset();
        return;
    }

    m_pending.startPosMs = aStartPosMs;
    m_pending.volume = aVolume;
    m_pending.fadeSeconds = aFadeSeconds;
    m_pending.path = aResolvedPath;
    m_pending.requested = true;
}

void ChannelSlot::Stop()
{
    m_pending.requested = false;

    if (m_channel != nullptr)
    {
        auto result = m_channel->stop();
        if (result != FMOD_OK && !IsHandoffError(result))
        {
            m_engine.LogFmodError(result, "Channel::stop");
        }
        m_channel = nullptr;
    }
}

void ChannelSlot::SetVolume(float aVolume)
{
    if (m_channel == nullptr)
    {
        return;
    }
    if (!IsChannelHandleValid(m_channel))
    {
        DropStaleChannel();
        return;
    }
    m_engine.LogFmodError(m_channel->setVolume(std::max(0.0f, aVolume)), "Channel::setVolume");
}

void ChannelSlot::SetPosition(const FMOD_VECTOR& aPos)
{
    if (m_channel == nullptr)
    {
        return;
    }
    if (!IsChannelHandleValid(m_channel))
    {
        DropStaleChannel();
        return;
    }

    auto result = m_channel->set3DAttributes(&aPos, nullptr);
    if (result != FMOD_OK && !IsHandoffError(result))
    {
        m_engine.LogFmodError(result, "Channel::set3DAttributes");
    }
}

void ChannelSlot::SetMinMaxDistance(float aMin, float aMax)
{
    if (m_channel == nullptr)
    {
        return;
    }
    if (!IsChannelHandleValid(m_channel))
    {
        DropStaleChannel();
        return;
    }

    auto result = m_channel->set3DMinMaxDistance(aMin, aMax);
    if (result != FMOD_OK && !IsHandoffError(result))
    {
        m_engine.LogFmodError(result, "Channel::set3DMinMaxDistance");
    }
}

bool ChannelSlot::IsActive() const
{
    if (m_channel == nullptr)
    {
        return m_pending.requested;
    }
    return IsChannelHandleValid(m_channel);
}

bool ChannelSlot::HasFailedFor(const std::string& aPath) const
{
    return m_pending.path == aPath;
}

void ChannelSlot::Shutdown()
{
    Stop();
    m_pending.Reset();
}

void ChannelSlot::Tick()
{
    if (m_pending.sound == nullptr || !m_pending.requested)
    {
        return;
    }

    FMOD_OPENSTATE state;
    auto result = m_pending.sound->getOpenState(&state, nullptr, nullptr, nullptr);
    if (result != FMOD_OK)
    {
        m_engine.LogFmodError(result, "Sound::getOpenState");
        m_pending.requested = false;
        return;
    }

    if (state == FMOD_OPENSTATE_READY)
    {
        m_pending.requested = false;
        StartLoadedSound();
    }
    else if (state == FMOD_OPENSTATE_ERROR)
    {
        Plugin::Get().Sdk()->logger->ErrorF(Plugin::Get().Handle(),
            "Failed to load sound on slot %i (path: %s).", m_slotIndex, m_pending.path.c_str());
        TrackFailure(m_pending.path);
        m_pending.Reset();
    }
}

void ChannelSlot::SetFailureTracker(std::unordered_map<std::string, uint32_t>* aTracker)
{
    m_failures = aTracker;
}

void ChannelSlot::TrackFailure(const std::string& aPath)
{
    if (m_failures != nullptr && !aPath.empty())
    {
        ++(*m_failures)[aPath];
    }
}

void ChannelSlot::StartLoadedSound()
{
    m_engine.LogFmodError(m_pending.sound->setMode(FMOD_3D_INVERSETAPEREDROLLOFF), "Sound::setMode");
    m_engine.LogFmodError(m_pending.sound->set3DMinMaxDistance(1.0f, 10.0f), "Sound::set3DMinMaxDistance");

    uint32_t lengthMs = 0;
    m_engine.LogFmodError(m_pending.sound->getLength(&lengthMs, FMOD_TIMEUNIT_MS), "Sound::getLength");

    auto startPos = static_cast<uint32_t>(std::clamp<int32_t>(m_pending.startPosMs, 0,
                                                              static_cast<int32_t>(lengthMs)));
    auto volume = std::max(0.0f, m_pending.volume);

    if (m_channel != nullptr)
    {
        auto stopResult = m_channel->stop();
        if (stopResult != FMOD_OK && !IsHandoffError(stopResult))
        {
            m_engine.LogFmodError(stopResult, "Channel::stop (previous)");
        }
        m_channel = nullptr;
    }

    auto playResult = m_engine.System()->playSound(m_pending.sound, nullptr, false, &m_channel);
    if (playResult != FMOD_OK || m_channel == nullptr)
    {
        m_engine.LogFmodError(playResult, "System::playSound");
        m_pending.Reset();
        return;
    }

    if (!IsChannelHandleValid(m_channel))
    {
        // FMOD reused the slot immediately; nothing else to do.
        m_channel = nullptr;
        return;
    }

    m_engine.LogFmodError(m_channel->setPosition(startPos, FMOD_TIMEUNIT_MS), "Channel::setPosition");
    m_engine.LogFmodError(m_channel->setVolume(volume), "Channel::setVolume");
    ApplyFadeIn(m_pending.fadeSeconds);
}

void ChannelSlot::ApplyFadeIn(float aDuration)
{
    if (m_channel == nullptr || !IsChannelHandleValid(m_channel))
    {
        return;
    }

    auto pauseResult = m_channel->setPaused(true);
    if (pauseResult != FMOD_OK && !IsHandoffError(pauseResult))
    {
        m_engine.LogFmodError(pauseResult, "Channel::setPaused(true)");
    }

    uint64_t dspClock = 0;
    int rate = 0;

    FMOD::System* system = nullptr;
    m_engine.LogFmodError(m_channel->getSystemObject(&system), "Channel::getSystemObject");
    if (system == nullptr)
    {
        return;
    }

    m_engine.LogFmodError(system->getSoftwareFormat(&rate, nullptr, nullptr), "System::getSoftwareFormat");
    m_engine.LogFmodError(m_channel->getDSPClock(nullptr, &dspClock), "Channel::getDSPClock");
    m_engine.LogFmodError(m_channel->addFadePoint(dspClock, 0.0f), "Channel::addFadePoint(0)");
    m_engine.LogFmodError(m_channel->addFadePoint(dspClock + static_cast<uint64_t>(rate * aDuration), 1.0f),
                          "Channel::addFadePoint(1)");

    auto unpauseResult = m_channel->setPaused(false);
    if (unpauseResult != FMOD_OK && !IsHandoffError(unpauseResult))
    {
        m_engine.LogFmodError(unpauseResult, "Channel::setPaused(false)");
    }
}

void ChannelSlot::DropStaleChannel()
{
    m_channel = nullptr;
}

} // namespace Frequency
