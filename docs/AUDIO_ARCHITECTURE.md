# Frequency — Game-Native Audio Backend (Wwise) Research

Status: milestone 2 implemented (Audioware backend for file stations +
FMOD removed). Untested in-game. Branch: `wwise`.

## Problem

Frequency currently plays all station audio through its own FMOD system
(`native/src/Audio/*`), while the game runs its audio on Wwise. The two
engines are independent, so custom audio:

- ignores the game's mix (ducking, occlusion, reverb zones)
- must manually mirror volume sliders and mute states (see
  `modules/audio/AudioEngine.lua`, `modules/core/Session.lua`)
- can conflict with other mods that touch audio (LTBF report)

## Investigated routes

### 1. Vanilla radio pipeline (wem + cooked_metadata + eventsmetadata) — NOT viable

How vanilla stations actually work (wiki: "Audio in TweakDB"):

- `RadioStation.*` TweakDB records carry `displayName`, `icon`, `index`.
- The `index` is a position in the `radioStations` array of the
  `radio_stations_config` entry inside the game-wide
  `cooked_metadata.audio_metadata` file; each entry chains into another
  cooked_metadata entry holding track event names + blips.
- Track names live in `radio_tracks_metadata` (also cooked_metadata);
  the actual sounds are Wwise events from `eventsmetadata.json`, playing
  `.wem` files streamed from `.archive` files.

To add a station natively we would have to extend **three giant singleton
game files**. That is a conflict machine and cannot be a drop-in
framework for arbitrary user songs. This is why every custom-radio
framework takes the custom-playback route.

### 2. Calling Wwise directly from a RED4ext plugin — NOT viable

Wwise is statically linked into the game. No public API or reverse
engineering exists (checked: psiberx's GitHub has no audio branch, no
audio repos; RED4ext has no audio API). Months of pattern-scanning, and
unmaintainable.

### 3. Audioware — THE route

[Audioware](https://github.com/cyb3rpsych0s1s/audioware) (Nexus 12001,
by Roms1383) is a **Rust RED4ext native plugin** that plays custom audio
(`.wav/.ogg/.mp3/.flac`) through the game's own audio system, without
REDmod. Current version 1.9.9, patch 2.31 compatible.

Requirements: Codeware 1.11.1+, TweakXL 1.10.2+ (+ RED4ext/redscript
implicitly). **License: none declared in the repo — all rights reserved.
We must NOT vendor any of its code; it becomes a mod dependency, and
Roms1383 gets credits (and ideally a heads-up/OK).**

#### Why it fits perfectly

- Sounds are declared in a YAML manifest; playback goes through the
  game's AudioSystem (Wwise) — mixer, ducking, occlusion for free.
- **Radio routing exists natively**: manifest `playlist` sounds route to
  the engine's *radioport* track, `jingles` to the *car_radio* track.
  The engine listens to the game's `RadioportVolume` / `CarRadioVolume`
  / `MusicVolume` / `MasterVolume` settings vars and applies them itself
  (see `crates/audioware/reds/Listener.reds`,
  `crates/audioware/src/engine/mod.rs`). Our manual volume mirroring
  becomes redundant for file stations.
- The README states the scripting API can be used "from **CET or
  Redscript**" — the bridge question is settled (spike still needed to
  pin exact CET call syntax).

#### Playback API (from docs + `reds/Ext.reds`)

- Vanilla-style (fire-and-forget): `GameInstance.GetAudioSystem(game).Play(n"name")`
- Emitter style: `AudioSystemExt.Play(eventName, entityID, emitterName, line, ext<AudioSettingsExt>)`,
  `RegisterEmitter(entityID, tagName, opt emitterName, opt emitterSettings)`,
  `PlayOnEmitter` / `StopOnEmitter` / `UnregisterEmitter`.
  Emitters must be Entity/GameObject-derived; **V cannot be an emitter
  (V is the listener)**.
- **Playback handles (1.7.0+)**: `DynamicSoundEvent.Create(name, ext)`
  then `QueueEvent` — supports `SetVolume`, `SetPlaybackRate`,
  `SetPanning`, `Position()`, `Stop`, `Pause`, `Resume`, `ResumeAt`,
  `SeekTo`, `SeekBy`. Once stopped, a handle cannot be restarted.
  `DynamicEmitterEvent` (1.7.6+) does the same for emitter sounds.
  `SeekTo` gives us mid-song join (the radio simulation feature).
- Manifest per-sound settings: `volume`, `loop`, `region: {starts, ends}`,
  `start_position`, `playback_rate`, `panning`, `fade_in_tween`,
  `usage: on-demand | in-memory | streaming` (music defaults to streaming).

#### Limitations to plan around

- **Radio track routing (verified empirically, round 1-2 spikes)**:
  `sfx:` → SFX slider, `music:` → Music slider, `jingles:` → car_radio
  track (**Car Radio slider**). The `playlist:` section (→ radioport
  track) is deserialized but **not registered yet** (`bank/src/lib.rs`
  registers sfx/onos/voices/music/jingles only). Plan: ship station
  songs under `jingles` until Audioware implements `playlist`, then
  move to `playlist` for the Radioport slider. Ping Roms1383 about
  playlist ETA.
- **No runtime sound registration**: every sound id is registered at
  startup from YAML manifests. Frequency's hot reload can still rebuild
  stations/playlists, but *adding new song files* requires a restart
  (or manifest regeneration + reload). Document as a trade-off.
- **No network streams**: files must live in the mod depot folder.
  Web stream stations are skipped with a warning (FMOD is removed
  entirely, so streams are gone from Frequency).
- No `duration` key in manifests — keep probing file durations ourselves
  (native header parsing) for the station simulation.
- The `playlist`/`jingles` manifest sections exist in the schema, but
  code comments say "until proper implementations ... are added" —
  the auto-advancing playlist behavior may be incomplete; worst case we
  drive song-to-song transitions ourselves with `DynamicSoundEvent`
  handles (Stop + Create + QueueEvent), which the handles fully support.

## Architecture plan

### Bridge

Frequency's logic is CET Lua. Per Audioware's README the API is usable
from CET directly. Verification spike:

1. From CET: resolve `Game.GetAudioSystemExt(gameInstance)` (or the
   Codeware static `GameInstance.GetAudioSystem`) via RTTI, then call
   `Play` with a manifest sound id. Confirm volume sliders affect it.
2. If CET path fails: call Audioware's registered RTTI natives from
   Frequency.dll (`CRTTISystem::Get()->GetClass("AudioSystemExt")` etc.).
3. Last resort: move playback logic to a thin redscript layer.

### Backend: Audioware only (FMOD removed)

All playback goes through Audioware. FMOD is removed entirely from the
codebase and from the release (`fmod.dll` gone). This also removes web
stream support — Audioware plays files only, and its manifest system
cannot express URLs.

Stream stations: schema v1/v2 keep parsing `streamInfo` / `stream` for
drop-in compatibility, but stations with `isStream == true` are skipped
at load time with a clear warning instead of breaking the station list.
If stream support is ever wanted again, it returns as a separate opt-in
plugin, not part of the core audio path.

### Per-layer changes

- `modules/audio/AudioEngine.lua` — rewritten as an Audioware facade:
  - vehicle channel: `DynamicSoundEvent` (2D sound handle with `SeekTo`
    for mid-song join, `Stop`, `SetVolume`)
  - world radios: registered emitters + `DynamicEmitterEvent`
  - song lengths: new native `ProbeDuration` (audio header parsing)
    replaces FMOD `GetSongLength`
- `modules/stations/Station.lua` — simulation logic unchanged;
  `PlayCurrentOn` maps to the new facade; stream stations skipped in
  `StationRegistry` with a warning.
- `modules/world/RadioEmitter.lua` — `RegisterEmitter` on the radio
  entity + `PlayOnEmitter`; position/occlusion handled by the game.
- `modules/core/Session.lua` and volume mirroring — deleted: Audioware
  rides the game's audio engine, so menus/braindance/loading muting and
  the volume sliders apply automatically.
- `native/` — the entire FMOD audio engine is deleted
  (`Audio/AudioEngine*`, `Audio/ChannelBank*`, `Audio/ChannelSlot*`,
  `Audio/PendingLoad.hpp`, `FmodUtils.hpp`, the FMOD part of
  `CMakeLists.txt`, shipped `fmod.dll`). The plugin keeps file IO,
  probing, and (only if needed) an Audioware RTTI bridge.
- Packager/docs — Audioware + Codeware + TweakXL become install
  requirements; manifest generation for station songs (one `audios.yml`
  per station, or one Frequency manifest with `playlist` per station
  folder).

### Milestones

1. ~~Spike: play an Audioware sound from CET Lua; verify sliders/ducking~~
   (done: all routes OK; sfx→SFX, music→Music, jingles→Car Radio)
2. ~~Backend facade + file-station playback on the vehicle channel~~
   (done: `modules/audio/{AudioEngine,SoundId,Manifest}.lua`,
   `native/src/{Junction,Manifest,ProbeDuration}.cpp`, FMOD deleted,
   stream stations skipped; needs an in-game test)
3. World radios as emitters (DynamicEmitterEvent).
4. Mid-song join via `DynamicSoundEvent` handles (`SeekTo`) from CET.
5. Docs/credits update (Roms1383/Audioware), Nexus requirements.

## Sources

- Wiki: "Audio files", "Audio in TweakDB", "Audio Modding: Redmod",
  "Custom Sounds & Custom Emitters with Audioware"
  (https://wiki.redmodding.org)
- Audioware book: https://cyb3rpsych0s1s.github.io/audioware
- Audioware repo: https://github.com/cyb3rpsych0s1s/audioware
