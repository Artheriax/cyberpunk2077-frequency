#ifndef FREQUENCY_JUNCTION_HPP
#define FREQUENCY_JUNCTION_HPP

#include <filesystem>
#include <string>

namespace Frequency
{

/// Creates a directory junction at `aLink` pointing to `aTarget` (both
/// absolute). Junctions do not require elevation. Returns false when the
/// junction could not be created.
bool CreateJunction(const std::wstring& aLink, const std::wstring& aTarget);

/// Creates the two depot junctions used by the Audioware manifest:
///   <game>\r6\audioware\Frequency\radios  -> CET Frequency radios folder
///   <game>\r6\audioware\Frequency\legacy  -> CET radioExt radios folder
/// Safe to call every load; existing junctions are left alone.
void EnsureDepotJunctions();

} // namespace Frequency

#endif // FREQUENCY_JUNCTION_HPP
