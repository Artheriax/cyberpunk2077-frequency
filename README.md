# Frequency

A Cyberpunk 2077 mod that lets you add custom radio stations — from local
audio files or web streams — to the vehicle radio, the pocket radio, and
physical radios placed around Night City.

Frequency is a ground-up rewrite by Artheriax. It contains **no borrowed
code from the original radioExt mod** — radioExt served only as the
**inspiration for the idea**. Frequency does, however, **support radioExt
radios**: it speaks the same station metadata format so existing radioExt
station packs keep working out of the box (drop-in compatibility).

## Features

- Unlimited custom radio stations with custom icons
- Local files (`.mp3`, `.wav`, `.ogg`, `.flac`, `.mp2`, `.wax`, `.wma`,
  `.opus`, `.aiff`) or web streams as sources
- Works in vehicles, on the pocket radio, and on physical in-world radios
- **Drop-in compatible** with existing radioExt station packs (schema v1)
- **New metadata schema v2** with station groups and song titles
- **Hot reload** — re-scan your stations without restarting the game
- **Station groups** — enable or disable whole packs at once
- **CET console API** for scripting and companion mods
- **Native Settings UI** support — reload stations right from the game's
  Mods settings menu (optional)

## Installation

1. Install the latest [Cyber Engine Tweaks](https://github.com/yamashi/CyberEngineTweaks).
2. Install the latest [RED4ext](https://github.com/WopsS/RED4ext).
3. Copy the contents of the release archive into your game folder
   (the one containing `bin` and `r6`). This places:
   - `bin/x64/plugins/cyber_engine_tweaks/mods/Frequency/` — the CET side
   - `red4ext/plugins/Frequency/Frequency.dll` and `fmod.dll` — the native side

Optional: [Native Settings UI](https://www.nexusmods.com/cyberpunk2077/mods/3518)
adds a Frequency settings tab to the game's Mods menu.

## Creating a station

Each station is a folder inside `mods/Frequency/radios/` containing a
`metadata.json` plus its song files:

```
Frequency/
└── radios/
    └── myStation/
        ├── metadata.json
        ├── song one.mp3
        └── song two.flac
```

Start from `metadata.v2.template.json` (recommended) or
`metadata.v1.template.json` (legacy format) and adjust the values.
Full field reference: [docs/METADATA.md](docs/METADATA.md).

Existing radioExt packs work unchanged — either drop their folders into
`mods/Frequency/radios/`, or leave them in place: Frequency automatically
imports stations from `mods/radioExt/radios/` when a legacy install is
present (configurable via `config.json`). You must not have both mods
installed at the same time.

## Hot reload

Changed songs or metadata while the game is running? Open the CET console:

```lua
Frequency.Reload()
```

All stations are stopped, re-scanned from disk, and rebuilt — no restart
required.

Prefer a button? Install
[Native Settings UI](https://www.nexusmods.com/cyberpunk2077/mods/3518)
(optional): Frequency then adds a **Frequency** tab with a
**Reload stations** button to the game's *Settings → Mods* menu.

## Station groups

Station packs can tag their stations with a `group` id in metadata. Users
can then toggle whole packs from the CET console:

```lua
Frequency.Groups()
Frequency.DisableGroup("somePack")
Frequency.Reload()
```

Group state persists in `groups.json`.

## Console API

`Frequency.Help()` lists every command. Highlights: `Status()`, `List()`,
`Info(name)`, `Play(name)`, `StopVehicle()`, `SetDebug(bool)`.
Companion mods can use the same table via `GetMod("Frequency")`.
Full reference: [docs/CONSOLE_API.md](docs/CONSOLE_API.md).

## Building the native plugin

`Frequency.dll` must be compiled on Windows (MSVC, RED4ext SDK, FMOD Core
API). See [docs/BUILDING.md](docs/BUILDING.md).

## Troubleshooting

The mod prints `[Frequency] Error/Warning: ...` messages to the CET console
for most problems.

- **"Native plugin missing"** — `Frequency.dll`/`fmod.dll` are not in
  `red4ext/plugins/Frequency/`, or your RED4ext is outdated.
- **"version mismatch"** — the DLL and the Lua files come from different
  releases. Do a clean reinstall.
- **"Skipped station folder ..."** — the console message tells you exactly
  what is wrong (missing/invalid `metadata.json`, disabled group, ...).
- **A station shows up but plays nothing** — it has no song files and is
  not configured as a stream.

## Credits

- Uses [FMOD](https://www.fmod.com/) by Firelight Technologies.
- Frequency is an independent rewrite — no code from
  [radioExt](https://github.com/justarandomguyintheinternet/CP77_radioExt)
  was borrowed, only the idea was taken as inspiration.
  radioExt station packs are supported for drop-in compatibility.
