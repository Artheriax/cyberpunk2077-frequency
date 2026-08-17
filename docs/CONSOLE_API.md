# Frequency console API

Everything is available from the CET console via the global `Frequency`
table, and to other CET mods via `GetMod("Frequency")` (same table).

```lua
Frequency.Help()   -- prints this list in-game
```

## Information

| Call | Returns | Description |
|------|---------|-------------|
| `Frequency.Version()` | string | Lua + native plugin versions. |
| `Frequency.Status()` | string[] | Station count, legacy import state, what's playing. |
| `Frequency.List()` | table[] | Every station: index, name, FM, group, song count, source. |
| `Frequency.Info(name)` | table \| nil | Full details for one station. |

## Hot reload

| Call | Description |
|------|-------------|
| `Frequency.Reload()` | Stops playback, re-reads every station folder from disk, rebuilds the station list. No game restart needed. |

Use it after adding/removing songs or editing a `metadata.json`.

## Station groups

| Call | Description |
|------|-------------|
| `Frequency.Groups()` | Lists all known groups and whether they are enabled. |
| `Frequency.EnableGroup(id)` | Enables a group (persisted in `groups.json`; call `Reload()` after). |
| `Frequency.DisableGroup(id)` | Disables a group (persisted; call `Reload()` after). |

A station belongs to a group when its metadata sets `"group": "someId"`.
Ungrouped stations are always enabled.

## Playback control

| Call | Description |
|------|-------------|
| `Frequency.Play(name)` | Force-plays a station on the vehicle/pocket radio channel. |
| `Frequency.StopVehicle()` | Stops custom playback on the vehicle/pocket channel. |

## Misc

| Call | Description |
|------|-------------|
| `Frequency.SetDebug(bool)` | Verbose `[Frequency] Debug:` logging. |

## Native class

The RED4ext scripting class (also named `Frequency`, as registered by
`Frequency.dll`) stays reachable after the API is installed:

```lua
Frequency.Native.GetVersion()
Frequency.Native.IsChannelActive(-1)
```

Most users never need this; it exists for companion mods that want direct
access to the audio backend.
