#ifndef FREQUENCY_PROBE_DURATION_HPP
#define FREQUENCY_PROBE_DURATION_HPP

#include <cstdint>
#include <string>

namespace Frequency
{

/// Measures the duration of a song file in milliseconds by parsing its
/// container header (wav, flac, ogg vorbis, mp3). Returns 0 when the
/// format is not supported or the file cannot be read.
uint32_t ProbeDurationMs(const std::string& aAbsolutePath);

} // namespace Frequency

#endif // FREQUENCY_PROBE_DURATION_HPP
