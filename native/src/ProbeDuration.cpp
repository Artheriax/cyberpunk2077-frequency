#include "ProbeDuration.hpp"

#include <algorithm>
#include <cstring>
#include <fstream>
#include <iterator>
#include <vector>

namespace Frequency
{

namespace
{

bool ReadWholeFile(const std::string& aPath, std::vector<uint8_t>& aOut)
{
    std::ifstream stream(aPath, std::ios::binary);
    if (!stream.good())
    {
        return false;
    }
    aOut.assign(std::istreambuf_iterator<char>(stream), std::istreambuf_iterator<char>());
    return !aOut.empty();
}

uint32_t ReadU32LE(const uint8_t* aPtr)
{
    return static_cast<uint32_t>(aPtr[0]) | (static_cast<uint32_t>(aPtr[1]) << 8) |
           (static_cast<uint32_t>(aPtr[2]) << 16) | (static_cast<uint32_t>(aPtr[3]) << 24);
}

uint32_t ReadU32BE(const uint8_t* aPtr)
{
    return (static_cast<uint32_t>(aPtr[0]) << 24) | (static_cast<uint32_t>(aPtr[1]) << 16) |
           (static_cast<uint32_t>(aPtr[2]) << 8) | static_cast<uint32_t>(aPtr[3]);
}

uint64_t ReadU64LE(const uint8_t* aPtr)
{
    return static_cast<uint64_t>(ReadU32LE(aPtr)) | (static_cast<uint64_t>(ReadU32LE(aPtr + 4)) << 32);
}

uint32_t WavDurationMs(const std::vector<uint8_t>& aData)
{
    if (aData.size() < 44 || std::memcmp(aData.data(), "RIFF", 4) != 0 ||
        std::memcmp(aData.data() + 8, "WAVE", 4) != 0)
    {
        return 0;
    }

    uint32_t byteRate = 0;
    uint32_t dataSize = 0;

    size_t offset = 12;
    while (offset + 8 <= aData.size())
    {
        const uint8_t* header = aData.data() + offset;
        const uint32_t chunkSize = ReadU32LE(header + 4);

        if (std::memcmp(header, "fmt ", 4) == 0 && chunkSize >= 8)
        {
            byteRate = ReadU32LE(header + 8 + 4); // nAvgBytesPerSec
        }
        else if (std::memcmp(header, "data", 4) == 0)
        {
            dataSize = chunkSize;
        }

        offset += 8 + chunkSize + (chunkSize & 1);
    }

    if (byteRate == 0 || dataSize == 0)
    {
        return 0;
    }
    return static_cast<uint32_t>((static_cast<uint64_t>(dataSize) * 1000) / byteRate);
}

uint32_t FlacDurationMs(const std::vector<uint8_t>& aData)
{
    if (aData.size() < 42 || std::memcmp(aData.data(), "fLaC", 4) != 0)
    {
        return 0;
    }

    size_t offset = 4;
    while (offset + 4 <= aData.size())
    {
        const uint8_t* header = aData.data() + offset;
        const bool last = (header[0] & 0x80) != 0;
        const uint8_t type = header[0] & 0x7F;
        const uint32_t length = (static_cast<uint32_t>(header[1]) << 16) |
                                (static_cast<uint32_t>(header[2]) << 8) | header[3];

        if (type == 0 && length >= 34 && offset + 4 + 34 <= aData.size())
        {
            const uint8_t* info = header + 4;
            const uint32_t sampleRate = (static_cast<uint32_t>(info[10]) << 12) |
                                        (static_cast<uint32_t>(info[11]) << 4) | (info[12] >> 4);
            const uint64_t totalSamples =
                (static_cast<uint64_t>(info[13] & 0x0F) << 32) | ReadU32BE(info + 14);

            if (sampleRate == 0)
            {
                return 0;
            }
            return static_cast<uint32_t>((totalSamples * 1000) / sampleRate);
        }

        if (last)
        {
            break;
        }
        offset += 4 + length;
    }
    return 0;
}

uint32_t OggDurationMs(const std::vector<uint8_t>& aData)
{
    if (aData.size() < 64 || std::memcmp(aData.data(), "OggS", 4) != 0)
    {
        return 0;
    }

    // Sample rate from the Vorbis identification header in the first page.
    uint32_t sampleRate = 0;
    {
        size_t offset = 27 + aData[26];
        if (offset + 16 <= aData.size() && aData[offset] == 0x01 &&
            std::memcmp(aData.data() + offset + 1, "vorbis", 6) == 0)
        {
            sampleRate = ReadU32LE(aData.data() + offset + 12);
        }
    }
    if (sampleRate == 0)
    {
        return 0;
    }

    // Granule position of the last page = total samples per channel.
    uint64_t granule = 0;
    const size_t searchStart = aData.size() > 65536 ? aData.size() - 65536 : 0;
    for (size_t i = aData.size() >= 14 ? aData.size() - 14 : 0; i >= searchStart; --i)
    {
        if (std::memcmp(aData.data() + i, "OggS", 4) == 0)
        {
            granule = ReadU64LE(aData.data() + i + 6);
            break;
        }
        if (i == 0)
        {
            break;
        }
    }

    if (granule == 0)
    {
        return 0;
    }
    return static_cast<uint32_t>((granule * 1000) / sampleRate);
}

uint32_t Mp3DurationMs(const std::vector<uint8_t>& aData)
{
    static const uint16_t kBitrateV1L3[16] = {0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0};
    static const uint16_t kBitrateV2L3[16] = {0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0};
    static const uint32_t kSampleRateV1[4] = {44100, 48000, 32000, 0};
    static const uint32_t kSampleRateV2[4] = {22050, 24000, 16000, 0};

    size_t offset = 0;
    if (aData.size() > 10 && std::memcmp(aData.data(), "ID3", 3) == 0)
    {
        const uint32_t id3Size = ((aData[6] & 0x7F) << 21) | ((aData[7] & 0x7F) << 14) |
                                 ((aData[8] & 0x7F) << 7) | (aData[9] & 0x7F);
        offset = 10 + id3Size + ((aData[5] & 0x10) ? 10 : 0);
    }

    if (offset + 4 > aData.size())
    {
        return 0;
    }

    // Find the first MPEG frame header.
    size_t frame = offset;
    bool found = false;
    while (frame + 4 <= aData.size() && frame < offset + 65536)
    {
        if (aData[frame] == 0xFF && (aData[frame + 1] & 0xE0) == 0xE0 &&
            ((aData[frame + 1] >> 1) & 0x03) == 1)
        {
            found = true;
            break;
        }
        ++frame;
    }
    if (!found)
    {
        return 0;
    }

    const uint8_t* h = aData.data() + frame;
    const uint8_t version = (h[1] >> 3) & 0x03; // 3 = MPEG1, 2 = MPEG2, 0 = MPEG2.5
    const uint8_t bitrateIdx = (h[2] >> 4) & 0x0F;
    const uint8_t srIdx = (h[2] >> 2) & 0x03;
    const bool padding = (h[2] >> 1) & 0x01;

    const uint16_t bitrate = (version == 3) ? kBitrateV1L3[bitrateIdx] : kBitrateV2L3[bitrateIdx];
    const uint32_t sampleRate = (version == 3) ? kSampleRateV1[srIdx] : kSampleRateV2[srIdx];
    if (bitrate == 0 || sampleRate == 0)
    {
        return 0;
    }

    // Xing/Info header: exact frame count for VBR files.
    const size_t scanEnd = std::min(frame + 4 + 120, aData.size());
    for (size_t i = frame + 4; i + 12 <= scanEnd; ++i)
    {
        if (std::memcmp(aData.data() + i, "Xing", 4) == 0 || std::memcmp(aData.data() + i, "Info", 4) == 0)
        {
            const uint8_t flags = aData[i + 7];
            if (flags & 0x01)
            {
                const uint32_t frames = ReadU32BE(aData.data() + i + 8);
                const uint32_t samplesPerFrame = (version == 3) ? 1152 : 576;
                return static_cast<uint32_t>((static_cast<uint64_t>(frames) * samplesPerFrame * 1000) / sampleRate);
            }
            break;
        }
    }

    // Fallback: constant-bitrate estimate from the total file size.
    const uint64_t audioBytes = aData.size() - frame;
    return static_cast<uint32_t>((audioBytes * 8 * 1000) / (bitrate * 1000));
}

} // anonymous namespace

uint32_t ProbeDurationMs(const std::string& aAbsolutePath)
{
    std::vector<uint8_t> data;
    if (!ReadWholeFile(aAbsolutePath, data) || data.empty())
    {
        return 0;
    }

    if (std::memcmp(data.data(), "RIFF", 4) == 0)
    {
        return WavDurationMs(data);
    }
    if (std::memcmp(data.data(), "fLaC", 4) == 0)
    {
        return FlacDurationMs(data);
    }
    if (std::memcmp(data.data(), "OggS", 4) == 0)
    {
        return OggDurationMs(data);
    }
    if (data[0] == 0xFF || (data.size() > 3 && std::memcmp(data.data(), "ID3", 3) == 0))
    {
        return Mp3DurationMs(data);
    }
    return 0;
}

} // namespace Frequency
