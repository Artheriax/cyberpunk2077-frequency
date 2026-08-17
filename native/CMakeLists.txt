cmake_minimum_required(VERSION 3.21)
project(Frequency VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ---------------------------------------------------------------------------
# Dependencies (override on the command line if your paths differ):
#   -DRED4EXT_SDK_DIR=C:/path/to/red4ext-sdk
#   -DFMOD_ROOT="C:/Program Files (x86)/FMOD SoundSystem/FMOD Studio API Windows/api/core"
# ---------------------------------------------------------------------------
set(RED4EXT_SDK_DIR "C:/BuildDeps/red4ext-sdk" CACHE PATH "Path to the RED4ext SDK")
set(FMOD_ROOT "C:/Program Files (x86)/FMOD SoundSystem/FMOD Studio API Windows/api/core" CACHE PATH "Path to the FMOD Core API")

add_subdirectory("${RED4EXT_SDK_DIR}" "${CMAKE_BINARY_DIR}/red4ext-sdk")

add_library(FMOD::Core SHARED IMPORTED)
set_target_properties(FMOD::Core PROPERTIES
    IMPORTED_LOCATION            "${FMOD_ROOT}/lib/x64/fmod.dll"
    IMPORTED_IMPLIB              "${FMOD_ROOT}/lib/x64/fmod_vc.lib"
    INTERFACE_INCLUDE_DIRECTORIES "${FMOD_ROOT}/inc"
)

# ---------------------------------------------------------------------------
# Frequency.dll
# ---------------------------------------------------------------------------
add_library(frequency SHARED
    src/Entry.cpp
    src/Plugin.cpp
    src/Audio/AudioEngine.cpp
    src/Audio/ChannelBank.cpp
    src/Audio/ChannelSlot.cpp
    src/Scripting/NativeBindings.cpp
)

target_include_directories(frequency PRIVATE src)

target_link_libraries(frequency PRIVATE
    RED4ext::SDK
    FMOD::Core
)

target_compile_definitions(frequency PRIVATE
    WIN32_LEAN_AND_MEAN
    NOMINMAX
)

set_target_properties(frequency PROPERTIES
    OUTPUT_NAME "Frequency"
    PREFIX ""
    SUFFIX ".dll"
)

# Ship fmod.dll next to Frequency.dll.
add_custom_command(TARGET frequency POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${FMOD_ROOT}/lib/x64/fmod.dll"
        "$<TARGET_FILE_DIR:frequency>"
    COMMENT "Copying fmod.dll to the output directory"
)
