# Building Frequency

The CET (Lua) side needs no build step — copy it into the game folder and
it runs. Only the native plugin `Frequency.dll` has to be compiled.

## Prerequisites (Windows)

1. **Visual Studio 2022** with the "Desktop development with C++" workload.
2. **CMake** 3.21 or newer.
3. **RED4ext SDK** — clone https://github.com/WopsS/RED4ext.SDK
   (recursively) somewhere, e.g. `C:/BuildDeps/red4ext-sdk`.
4. **FMOD Studio API (Windows)** — install the FMOD Studio API from
   https://www.fmod.com/download (a free account is required). The Core API
   usually lands in
   `C:/Program Files (x86)/FMOD SoundSystem/FMOD Studio API Windows/api/core`.

## Configure & build

```bat
cd native
cmake -B build -G "Visual Studio 17 2022" -A x64 ^
    -DRED4EXT_SDK_DIR="C:/BuildDeps/red4ext-sdk" ^
    -DFMOD_ROOT="C:/Program Files (x86)/FMOD SoundSystem/FMOD Studio API Windows/api/core"
cmake --build build --config Release
```

The build produces `Frequency.dll` and copies `fmod.dll` next to it.

## Install layout

```
Cyberpunk 2077/
├── bin/x64/plugins/cyber_engine_tweaks/mods/Frequency/
│   ├── init.lua
│   ├── modules/...
│   ├── config.json, groups.json, metadata.*.template.json
│   └── radios/...
└── red4ext/plugins/Frequency/
    ├── Frequency.dll
    └── fmod.dll
```

`tools/package.py` assembles a release zip with exactly this layout:

```bat
python tools/package.py path\to\native\build\Release
```

## Source map (native)

| File | Responsibility |
|------|----------------|
| `src/Entry.cpp` | RED4ext exports (`Main`, `Query`, `Supports`), game state hooks |
| `src/Plugin.hpp/.cpp` | Plugin singleton: SDK handles, paths, lifecycle |
| `src/Audio/AudioEngine.hpp/.cpp` | FMOD system wrapper (init, listener, length probe) |
| `src/Audio/ChannelBank.hpp/.cpp` | All channels, id normalization, failure tracking |
| `src/Audio/ChannelSlot.hpp/.cpp` | One channel: async load, playback, fades, 3D position |
| `src/Audio/PendingLoad.hpp` | Async-load state struct |
| `src/Scripting/FrequencyScriptClass.hpp` | The native `Frequency` CET class |
| `src/Scripting/NativeBindings.hpp/.cpp` | RTTI function registration and handlers |
| `src/FmodUtils.hpp` | FMOD error classification helpers |
