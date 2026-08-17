#ifndef FREQUENCY_CHANNEL_SLOT_HPP
#define FREQUENCY_CHANNEL_SLOT_HPP

#include "PendingLoad.hpp"

#include <fmod.hpp>
#include <cstdint>
#include <unordered_map>

namespace Frequency
{

class AudioEngine;

/// One playback channel: the FMOD channel handle plus the pending-load
/// state for the sound that is currently streaming in.
///
/// Slot 0 is the vehicle/pocket radio (2D). Slots 1..N are physical radios
/// positioned in the world (3D).
class ChannelSlot
{
public:
    explicit ChannelSlot(AudioEngine& aEngine, int32_t aSlotIndex);

    ChannelSlot(const ChannelSlot&) = delete;
    ChannelSlot& operator=(const ChannelSlot&) = delete;

    /// Queues a new sound for playback. `aIsStream` selects raw path
    /// handling (URL) instead of game-relative file resolution.
    void RequestPlay(const std::string& aResolvedPath, int32_t aStartPosMs, float aVolume, float aFadeSeconds,
                     bool aIsStream);

    void Stop();
    void SetVolume(float aVolume);
    void SetPosition(const FMOD_VECTOR& aPos);
    void SetMinMaxDistance(float aMin, float aMax);

    /// Polls the async load state; starts playback once the sound is ready.
    void Tick();

    bool IsActive() const;
    bool HasFailedFor(const std::string& aPath) const;

    void Shutdown();

    /// Per-path load failure counters, shared with the owning ChannelBank.
    void SetFailureTracker(std::unordered_map<std::string, uint32_t>* aTracker);

private:
    void StartLoadedSound();
    void ApplyFadeIn(float aDuration);
    void DropStaleChannel();
    void TrackFailure(const std::string& aPath);

    AudioEngine& m_engine;
    int32_t m_slotIndex;
    FMOD::Channel* m_channel = nullptr;
    PendingLoad m_pending;
    std::unordered_map<std::string, uint32_t>* m_failures = nullptr;
};

} // namespace Frequency

#endif // FREQUENCY_CHANNEL_SLOT_HPP
