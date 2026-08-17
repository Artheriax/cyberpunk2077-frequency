#ifndef FREQUENCY_CHANNEL_BANK_HPP
#define FREQUENCY_CHANNEL_BANK_HPP

#include "ChannelSlot.hpp"

#include <memory>
#include <string>
#include <unordered_map>
#include <vector>

namespace Frequency
{

class AudioEngine;

/// Owns every playback channel. Translates Lua channel ids (where -1 is the
/// vehicle radio) into slot indices, tracks per-path failure counts so a
/// dead stream URL is not retried forever, and pumps async loads each frame.
class ChannelBank
{
public:
    static constexpr int32_t kMaxLoadAttempts = 3;

    explicit ChannelBank(AudioEngine& aEngine);

    ChannelBank(const ChannelBank&) = delete;
    ChannelBank& operator=(const ChannelBank&) = delete;

    /// Maps a Lua channel id to a slot index. -1 (vehicle) becomes slot 0.
    static int32_t NormalizeId(int32_t aChannelId);

    void Play(int32_t aChannelId, const std::string& aPathOrUrl, int32_t aStartPosMs, float aVolume, float aFade);
    void Stop(int32_t aChannelId);
    void SetVolume(int32_t aChannelId, float aVolume);
    void SetChannelPosition(int32_t aChannelId, const FMOD_VECTOR& aPos);
    void SetMinMaxDistance(float aMin, float aMax);

    bool IsChannelActive(int32_t aChannelId) const;

    void TickAll();
    void ShutdownAll();

    int32_t Count() const;

private:
    AudioEngine& m_engine;
    std::vector<std::unique_ptr<ChannelSlot>> m_slots;
    std::unordered_map<std::string, uint32_t> m_loadFailures;
};

} // namespace Frequency

#endif // FREQUENCY_CHANNEL_BANK_HPP
