#ifndef FREQUENCY_FMOD_UTILS_HPP
#define FREQUENCY_FMOD_UTILS_HPP

#include <fmod.hpp>
#include <fmod_errors.h>
#include <cstring>

namespace Frequency
{

/// Returns true for the expected "channel handoff" failures: FMOD reuses
/// channel slots internally, so a cached FMOD::Channel* can go stale between
/// frames. Those are not real errors and must not spam the log.
///
/// Error code names differ between FMOD SDK generations, so guarded codes
/// are combined with a message-text fallback.
inline bool IsHandoffError(FMOD_RESULT aResult)
{
    if (aResult == FMOD_OK)
    {
        return false;
    }

#ifdef FMOD_ERR_INVALID_HANDLE
    if (aResult == FMOD_ERR_INVALID_HANDLE) return true;
#endif
#ifdef FMOD_ERR_CHANNEL_REUSE
    if (aResult == FMOD_ERR_CHANNEL_REUSE) return true;
#endif
#ifdef FMOD_ERR_CHANNEL_STOLEN
    if (aResult == FMOD_ERR_CHANNEL_STOLEN) return true;
#endif

    const char* text = FMOD_ErrorString(aResult);
    if (text != nullptr)
    {
        return std::strstr(text, "reused") != nullptr
            || std::strstr(text, "Invalid handle") != nullptr
            || std::strstr(text, "invalid handle") != nullptr;
    }
    return false;
}

/// Probes a cached channel handle for validity without disturbing playback.
inline bool IsChannelHandleValid(FMOD::Channel* aChannel)
{
    if (aChannel == nullptr)
    {
        return false;
    }
    bool playing = false;
    return aChannel->isPlaying(&playing) == FMOD_OK;
}

} // namespace Frequency

#endif // FREQUENCY_FMOD_UTILS_HPP
