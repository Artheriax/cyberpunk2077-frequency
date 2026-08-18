#ifndef FREQUENCY_MANIFEST_HPP
#define FREQUENCY_MANIFEST_HPP

#include <cstdint>
#include <string>

namespace Frequency
{

/// Writes the baseline Audioware manifest for all song files found in the
/// CET station folders. Volume is baked as 1.0; the CET side regenerates
/// the manifest with the real station volumes once metadata is loaded.
///
/// This runs at plugin load, before Audioware parses manifests, so
/// freshly installed stations work on the very first launch.
void GenerateBaselineManifest();

} // namespace Frequency

#endif // FREQUENCY_MANIFEST_HPP
