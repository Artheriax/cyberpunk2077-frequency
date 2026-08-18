# Building Frequency

The CET (Lua) side needs no build step — copy it into the game folder and
it runs. Only the native plugin `Frequency.dll` has to be compiled.

## Prerequisites (Windows)

1. **Visual Studio 2022** with the "Desktop development with C++" workload.
2. **CMake** 3.21 or newer.
3. **RED4ext SDK** — clone https://github.com/WopsS/RED4ext.SDK
   (recursively) somewhere, e.g. `C:/BuildDeps/red4ext-sdk`.

The plugin no longer needs FMOD — station audio plays through
[Audioware](https://github.com/cyb3rpsych0s1s/audioware), which routes
custom sounds through the game's own audio engine.

## Configure & build

```bat
cd native
cmake -B build -G "Visual Studio 17 2022" -A x64 ^
    -DRED4EXT_SDK_DIR="C:/BuildDeps/red4ext-sdk"
cmake --build build --config Release
```

The build produces `Frequency.dll` in `native/build/Release`.

## Install layout

```
Cyberpunk 2077/
├── bin/x64/plugins/cyber_engine_tweaks/mods/Frequency/
│   ├── init.lua
│   ├── modules/...
│   ├── config.json, groups.json, metadata.*.template.json
│   └── radios/...
├── red4ext/plugins/Frequency/
│   └── Frequency.dll
└── r6/audioware/Frequency/            <- generated at runtime:
    ├── audios.yml                       (baseline written by the plugin,
    ├── radios/                          rewritten by the CET side)
    └── legacy/                          (directory junctions)
```

`tools/package.py` assembles a release zip with exactly this layout:

```bat
python tools/package.py path\to\native\build\Release
```

## Source map (native)

| File | Responsibility |
|------|----------------|
| `src/Entry.cpp` | RED4ext exports (`Main`, `Query`, `Supports`) |
| `src/Plugin.hpp/.cpp` | Plugin singleton: SDK handles, paths, lifecycle |
| `src/Junction.hpp/.cpp` | Audioware depot junctions (radios/legacy folders) |
| `src/Manifest.hpp/.cpp` | Baseline Audioware manifest generation at plugin load |
| `src/ProbeDuration.hpp/.cpp` | Song duration probing (wav/flac/ogg/mp3 headers) |
| `src/Scripting/FrequencyScriptClass.hpp` | The native `Frequency` CET class |
| `src/Scripting/NativeBindings.hpp/.cpp` | RTTI function registration and handlers |
