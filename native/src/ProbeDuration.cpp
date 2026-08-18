#include "ProbeDuration.hpp"

#include <algorithm>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <vector>

namespace Frequency
{

namespace
{

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

uint64_t FileSize(const std::string& aPath)
{
    std::error_code ec;
    const auto size = std::filesystem::file_size(aPath, ec);
    return ec ? 0 : size;
}

/// Reads `aCount` bytes at `aOffset`. Returns false on failure.
bool ReadAt(const std::string& aPath, uint64_t aOffset, uint64_t aCount, std::vector<uint8_t>& aOut)
{
    aOut.resize(static_cast<size_t>(aCount));
    std::ifstream stream(aPath, std::ios::binary);
    if (!stream.good())
    {
        return false;
    }
    stream.seekg(static_cast<std::streamoff>(aOffset), std::ios::beg);
    if (!stream.good())
    {
        return false;
    }
    stream.read(reinterpret_cast<char*>(aOut.data()), static_cast<std::streamsize>(aCount));
    if (!stream.good() && !stream.eof())
    {
        return false;
    }
    return true;
}

uint32_t WavDurationMs(const std::string& aPath, uint64_t aFileSize)
{
    // fmt and data chunks are near the file start; scan the first 1 MB.
    constexpr uint64_t kWindow = 1024 * 1024;
    std::vector<uint8_t> data;
    if (!ReadAt(aPath, 0, std::min<uint64_t>(kWindow, aFileSize), data) || data.size() < 44)
    {
        return 0;
    }
    if (std::memcmp(data.data(), "RIFF", 4) != 0 || std::memcmp(data.data() + 8, "WAVE", 4) != 0)
    {
        return 0;
    }

    uint32_t byteRate = 0;
    uint32_t dataSize = 0;

    size_t offset = 12;
    while (offset + 8 <= data.size())
    {
        const uint8_t* header = data.data() + offset;
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

    if (byteRate == 0)
    {
        return 0;
    }
    if (dataSize == 0)
    {
        // The data chunk lies beyond the scan window: estimate from the
        // total file size. Close enough for radio simulation purposes.
        dataSize = static_cast<uint32_t>(aFileSize - 44);
    }
    return static_cast<uint32_t>((static_cast<uint64_t>(dataSize) * 1000) / byteRate);
}

uint32_t FlacDurationMs(const std::string& aPath)
{
    // "fLaC" + first metadata block header + STREAMINFO fits in 64 bytes.
    std::vector<uint8_t> data;
    if (!ReadAt(aPath, 0, 64, data) || data.size() < 42 || std::memcmp(data.data(), "fLaC", 4) != 0)
    {
        return 0;
    }

    const uint8_t* header = data.data() + 4;
    const uint8_t type = header[0] & 0x7F;
    const uint32_t length = (static_cast<uint32_t>(header[1]) << 16) |
                            (static_cast<uint32_t>(header[2]) << 8) | header[3];

    if (type != 0 || length < 34 || data.size() < 4 + 4 + 34)
    {
        return 0;
    }

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

uint32_t OggDurationMs(const std::string& aPath, uint64_t aFileSize)
{
    // First page holds the Vorbis identification header; the last page
    // holds the final granule position.
    std::vector<uint8_t> head;
    if (!ReadAt(aPath, 0, 512, head) || head.size() < 28 || std::memcmp(head.data(), "OggS", 4) != 0)
    {
        return 0;
    }

    uint32_t sampleRate = 0;
    {
        const size_t offset = 27 + head[26];
        if (offset + 16 <= head.size() && head[offset] == 0x01 &&
            std::memcmp(head.data() + offset + 1, "vorbis", 6) == 0)
        {
            sampleRate = ReadU32LE(head.data() + offset + 12);
        }
    }
    if (sampleRate == 0)
    {
        return 0;
    }

    constexpr uint64_t kTail = 65536;
    std::vector<uint8_t> tail;
    const uint64_t tailOffset = aFileSize > kTail ? aFileSize - kTail : 0;
    if (!ReadAt(aPath, tailOffset, aFileSize - tailOffset, tail))
    {
        return 0;
    }

    uint64_t granule = 0;
    for (size_t i = tail.size() >= 14 ? tail.size() - 14 : 0; i > 0; --i)
    {
        if (std::memcmp(tail.data() + i, "OggS", 4) == 0)
        {
            granule = ReadU64LE(tail.data() + i + 6);
            break;
        }
    }

    if (granule == 0)
    {
        return 0;
    }
    return static_cast<uint32_t>((granule * 1000) / sampleRate);
}

uint32_t Mp3DurationMs(const std::string& aPath, uint64_t aFileSize)
{
    static const uint16_t kBitrateV1L3[16] = {0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0};
    static const uint16_t kBitrateV2L3[16] = {0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0};
    static const uint32_t kSampleRateV1[4] = {44100, 48000, 32000, 0};
    static const uint32_t kSampleRateV2[4] = {22050, 24000, 16000, 0};

    constexpr uint64_t kWindow = 65536;
    std::vector<uint8_t> data;
    if (!ReadAt(aPath, 0, std::min<uint64_t>(kWindow, aFileSize), data) || data.empty())
    {
        return 0;
    }

    size_t offset = 0;
    if (data.size() > 10 && std::memcmp(data.data(), "ID3", 3) == 0)
    {
        const uint32_t id3Size = ((data[6] & 0x7F) << 21) | ((data[7] & 0x7F) << 14) |
                                 ((data[8] & 0x7F) << 7) | (data[9] & 0x7F);
        offset = 10 + id3Size + ((data[5] & 0x10) ? 10 : 0);
    }

    if (offset + 4 > data.size())
    {
        return 0;
    }

    // Find the first MPEG frame header.
    size_t frame = offset;
    bool found = false;
    while (frame + 4 <= data.size() && frame < offset + kWindow)
    {
        if (data[frame] == 0xFF && (data[frame + 1] & 0xE0) == 0xE0 &&
            ((data[frame + 1] >> 1) & 0x03) == 1)
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

    const uint8_t* h = data.data() + frame;
    const uint8_t version = (h[1] >> 3) & 0x03; // 3 = MPEG1, 2 = MPEG2, 0 = MPEG2.5
    const uint8_t bitrateIdx = (h[2] >> 4) & 0x0F;
    const uint8_t srIdx = (h[2] >> 2) & 0x03;

    const uint16_t bitrate = (version == 3) ? kBitrateV1L3[bitrateIdx] : kBitrateV2L3[bitrateIdx];
    const uint32_t sampleRate = (version == 3) ? kSampleRateV1[srIdx] : kSampleRateV2[srIdx];
    if (bitrate == 0 || sampleRate == 0)
    {
        return 0;
    }

    // Xing/Info header: exact frame count for VBR files.
    const size_t scanEnd = std::min(frame + 4 + 120, data.size());
    for (size_t i = frame + 4; i + 12 <= scanEnd; ++i)
    {
        if (std::memcmp(data.data() + i, "Xing", 4) == 0 || std::memcmp(data.data() + i, "Info", 4) == 0)
        {
            const uint8_t flags = data[i + 7];
            if (flags & 0x01)
            {
                const uint32_t frames = ReadU32BE(data.data() + i + 8);
                const uint32_t samplesPerFrame = (version == 3) ? 1152 : 576;
                return static_cast<uint32_t>((static_cast<uint64_t>(frames) * samplesPerFrame * 1000) / sampleRate);
            }
            break;
        }
    }

    // Fallback: constant-bitrate estimate from the total file size.
    const uint64_t audioBytes = aFileSize > frame ? aFileSize - frame : 0;
    return static_cast<uint32_t>((audioBytes * 8 * 1000) / (bitrate * 1000));
}

} // anonymous namespace

uint32_t ProbeDurationMs(const std::string& aAbsolutePath)
{
    const uint64_t fileSize = FileSize(aAbsolutePath);
    if (fileSize == 0)
    {
        return 0;
    }

    // Identify the container by its magic bytes.
    std::vector<uint8_t> magic;
    if (!ReadAt(aAbsolutePath, 0, 12, magic) || magic.size() < 4)
    {
        return 0;
    }

    if (std::memcmp(magic.data(), "RIFF", 4) == 0)
    {
        return WavDurationMs(aAbsolutePath, fileSize);
    }
    if (std::memcmp(magic.data(), "fLaC", 4) == 0)
    {
        return FlacDurationMs(aAbsolutePath);
    }
    if (std::memcmp(magic.data(), "OggS", 4) == 0)
    {
        return OggDurationMs(aAbsolutePath, fileSize);
    }
    if (magic[0] == 0xFF || (magic.size() > 3 && std::memcmp(magic.data(), "ID3", 3) == 0))
    {
        return Mp3DurationMs(aAbsolutePath, fileSize);
    }
    return 0;
}

} // namespace Frequency
