#ifndef FREQUENCY_AUDIO_ENGINE_HPP
#define FREQUENCY_AUDIO_ENGINE_HPP

#include <fmod.hpp>
#include <cstdint>
#include <string>

#include <RED4ext/RED4ext.hpp>
#include <RED4ext/Scripting/Natives/Generated/Vector4.hpp>

namespace Frequency
{

/// Thin RAII wrapper around the FMOD system object. Handles init, the
/// per-frame update, listener transform, global 3D settings, and the
/// one-off length probe used to measure song files.
class AudioEngine
{
public:
    static constexpr int32_t kChannelCount = 64;

    AudioEngine() = default;
    ~AudioEngine() = default;

    AudioEngine(const AudioEngine&) = delete;
    AudioEngine& operator=(const AudioEngine&) = delete;

    bool Initialize();
    void Shutdown();

    void Update();

    FMOD::System* System() const { return m_system; }

    /// Measures a sound file in milliseconds. Returns 0 on failure.
    uint32_t ProbeLengthMs(const std::string& aAbsolutePath) const;

    void SetListener(const FMOD_VECTOR& aPos, const FMOD_VECTOR& aForward, const FMOD_VECTOR& aUp);
    void SetFalloff(float aFalloff);

    void LogFmodError(FMOD_RESULT aResult, const char* aContext) const;

    /// Converts a RED4ext Vector4 into FMOD coordinates (left -> right handed).
    static FMOD_VECTOR ToFmodVector(const RED4ext::Vector4& aVec);

private:
    FMOD::System* m_system = nullptr;
};

} // namespace Frequency

#endif // FREQUENCY_AUDIO_ENGINE_HPP
