#include "ChannelBank.hpp"

#include "../Plugin.hpp"
#include "AudioEngine.hpp"

#include <algorithm>

namespace Frequency
{

ChannelBank::ChannelBank(AudioEngine& aEngine)
    : m_engine(aEngine)
{
    m_slots.reserve(AudioEngine::kChannelCount + 1);
    for (int32_t i = 0; i <= AudioEngine::kChannelCount; ++i)
    {
        auto slot = std::make_unique<ChannelSlot>(aEngine, i);
        slot->SetFailureTracker(&m_loadFailures);
        m_slots.push_back(std::move(slot));
    }
}

int32_t ChannelBank::NormalizeId(int32_t aChannelId)
{
    if (aChannelId == -1)
    {
        return 0;
    }
    return std::clamp(aChannelId, 0, AudioEngine::kChannelCount);
}

void ChannelBank::Play(int32_t aChannelId, const std::string& aPathOrUrl, int32_t aStartPosMs, float aVolume,
                       float aFade)
{
    auto& plugin = Plugin::Get();

    const bool isStream = (aStartPosMs == -1);
    std::string resolved = isStream
        ? aPathOrUrl
        : plugin.ResolveGamePath(aPathOrUrl.c_str()).string();

    auto failures = m_loadFailures.find(resolved);
    if (failures != m_loadFailures.end() && failures->second >= kMaxLoadAttempts)
    {
        plugin.Sdk()->logger->ErrorF(plugin.Handle(),
            "Resource %s exceeded the maximum number of load attempts.", resolved.c_str());
        return;
    }

    m_slots[NormalizeId(aChannelId)]->RequestPlay(resolved, aStartPosMs, aVolume, aFade, isStream);
}

void ChannelBank::Stop(int32_t aChannelId)
{
    m_slots[NormalizeId(aChannelId)]->Stop();
}

void ChannelBank::SetVolume(int32_t aChannelId, float aVolume)
{
    m_slots[NormalizeId(aChannelId)]->SetVolume(aVolume);
}

void ChannelBank::SetChannelPosition(int32_t aChannelId, const FMOD_VECTOR& aPos)
{
    m_slots[NormalizeId(aChannelId)]->SetPosition(aPos);
}

void ChannelBank::SetMinMaxDistance(float aMin, float aMax)
{
    for (auto& slot : m_slots)
    {
        slot->SetMinMaxDistance(aMin, aMax);
    }
}

bool ChannelBank::IsChannelActive(int32_t aChannelId) const
{
    return m_slots[NormalizeId(aChannelId)]->IsActive();
}

void ChannelBank::TickAll()
{
    for (auto& slot : m_slots)
    {
        slot->Tick();
    }
}

void ChannelBank::ShutdownAll()
{
    for (auto& slot : m_slots)
    {
        slot->Shutdown();
    }
    m_loadFailures.clear();
}

int32_t ChannelBank::Count() const
{
    return AudioEngine::kChannelCount;
}

} // namespace Frequency
