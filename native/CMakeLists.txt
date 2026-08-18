cmake_minimum_required(VERSION 3.21)
project(Frequency VERSION 2.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ---------------------------------------------------------------------------
# Dependencies (override on the command line if your paths differ):
#   -DRED4EXT_SDK_DIR=C:/path/to/red4ext-sdk
# ---------------------------------------------------------------------------
set(RED4EXT_SDK_DIR "C:/BuildDeps/red4ext-sdk" CACHE PATH "Path to the RED4ext SDK")

add_subdirectory("${RED4EXT_SDK_DIR}" "${CMAKE_BINARY_DIR}/red4ext-sdk")

# ---------------------------------------------------------------------------
# Frequency.dll
# ---------------------------------------------------------------------------
add_library(frequency SHARED
    src/Entry.cpp
    src/Plugin.cpp
    src/Junction.cpp
    src/Manifest.cpp
    src/ProbeDuration.cpp
    src/Scripting/NativeBindings.cpp
)

target_include_directories(frequency PRIVATE src)

target_link_libraries(frequency PRIVATE
    RED4ext::SDK
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
