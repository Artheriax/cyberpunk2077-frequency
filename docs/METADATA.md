# Frequency metadata reference

Every station folder contains a `metadata.json`. Frequency understands two
schema versions:

| Version | Detected by | Purpose |
|---------|-------------|---------|
| **v1** (legacy) | no `schemaVersion` field | radioExt-compatible format; existing packs work unchanged |
| **v2** (Frequency) | `"schemaVersion": 2` | new format with groups, song titles and a cleaner stream section |

Use a text editor with JSON syntax highlighting — most broken stations are
just invalid JSON (missing commas, unescaped backslashes).

## Schema v2 (recommended)

```json
{
    "schemaVersion": 2,
    "displayName": "88.7 Neon Nights",
    "fm": 88.7,
    "volume": 1.0,
    "group": "myPack",
    "icon": "UIIcon.RadioHipHop",
    "customIcon": {
        "useCustom": true,
        "inkAtlasPath": "base\\gameplay\\gui\\my_atlas.inkatlas",
        "inkAtlasPart": "my_part"
    },
    "stream": {
        "url": "https://example.com/stream.mp3"
    },
    "order": ["intro.mp3", "daily_mix.mp3"],
    "songTitles": {
        "intro.mp3": "Neon Nights Intro"
    }
}
```

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `schemaVersion` | number | Must be `2`. |
| `displayName` | string | Name shown in the radio list. |
| `fm` | number | Sort position in the radio list. Should match any FM number inside `displayName`. |
| `volume` | number | Overall volume multiplier. Normalize your songs first, then match vanilla loudness with this. |
| `group` | string | Optional station group id. Stations sharing an id can be enabled/disabled together via the console API. |
| `icon` | string | Any `UIIcon.` record name, or `"default"`. |
| `customIcon.useCustom` | bool | `true` to use a custom atlas instead of `icon`. |
| `customIcon.inkAtlasPath` | string | Path to the `.inkatlas` (double backslashes). |
| `customIcon.inkAtlasPart` | string | Texture part inside the atlas. |
| `stream.url` | string | When non-empty, the station is a web stream and song files are ignored. |
| `order` | string[] | Optional fixed play order for the listed files; all other songs shuffle around them. |
| `songTitles` | object | Optional map of file name to display title for the "now playing" UI. |

## Schema v1 (legacy, drop-in compatible)

```json
{
    "displayName": "69.9 My Station",
    "fm": 69.9,
    "volume": 1.0,
    "icon": "UIIcon.RadioHipHop",
    "customIcon": {
        "useCustom": false,
        "inkAtlasPath": "",
        "inkAtlasPart": ""
    },
    "streamInfo": {
        "isStream": false,
        "streamURL": ""
    },
    "order": []
}
```

Field meanings match the table above, with two differences:

- Streams are configured via `streamInfo.isStream` + `streamInfo.streamURL`
  instead of the `stream` section.
- There is no `group`/`songTitles`. (A `group` field is still read if
  present — Frequency extension, ignored by radioExt.)

v1 files with missing fields are completed automatically on load and
written back to disk, keeping them valid v1 files.

## Notes

- Supported audio: `.mp3`, `.mp2`, `.flac`, `.ogg`, `.wav`, `.wax`,
  `.wma`, `.opus`, `.aiff`, `.aif`, `.aifc`.
- Song file names become track names in-game (v1), unless overridden via
  `songTitles` (v2).
- Custom icons: create an `.inkatlas` with
  [WolvenKit](https://github.com/WolvenKit/WolvenKit); the clothing-icon
  tutorials on the Cyberpunk 2077 modding wiki apply one-to-one.
