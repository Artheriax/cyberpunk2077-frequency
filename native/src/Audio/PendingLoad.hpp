#ifndef FREQUENCY_PENDING_LOAD_HPP
#define FREQUENCY_PENDING_LOAD_HPP

#include <cstdint>
#include <string>

#include <fmod.hpp>

namespace Frequency
{

/// Transient state of one channel while a sound streams in asynchronously
/// (FMOD_NONBLOCKING). Once the open state reports READY, the channel slot
/// starts playback and resets this struct.
struct PendingLoad
{
    FMOD::Sound* sound = nullptr;
    int32_t startPosMs = 0;
    float volume = 0.0f;
    float fadeSeconds = 0.0f;
    bool requested = false;
    std::string path;

    void Reset()
    {
        if (sound != nullptr)
        {
            sound->release();
            sound = nullptr;
        }
        startPosMs = 0;
        volume = 0.0f;
        fadeSeconds = 0.0f;
        requested = false;
        path.clear();
    }
};

} // namespace Frequency

#endif // FREQUENCY_PENDING_LOAD_HPP
