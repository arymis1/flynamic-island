# Flynamic Island

A small Mac music companion that lives near the top of the screen. This public repository keeps the four Mac editions together.

| Edition | Folder | Processor | Players | CPU/RAM stats |
| --- | --- | --- | --- | --- |
| Music only | [mac-music-only](mac-music-only) | Apple silicon | Apple Music, Spotify desktop | No |
| Music + System Stats | [mac-music-system-stats](mac-music-system-stats) | Apple silicon | Apple Music, Spotify desktop | Yes, two-finger swipe |
| Browser music | [mac-browser](mac-browser) | Apple silicon | YouTube Music in Chrome | Yes, two-finger swipe |
| Intel Mac | [mac-intel](mac-intel) | Intel x86_64 | Apple Music, Spotify desktop | Yes, two-finger swipe |

## Downloads

The first GitHub Release preserves the four existing installers, rather than silently replacing them with new builds. Installers are Release assets, not files in the source tree. [Edition details and existing Drive links](docs/downloads.md) identify the right download.

**This repository and its Releases are private.** Friends need repository access to use GitHub downloads. Existing Drive links remain available for friends who do not have repository access.

All four editions require macOS 14 or newer; live audio bars require macOS 14.2 or newer and system audio permission. Intel compatibility checks ran through Rosetta, but a physical Intel Mac was not tested here. Current builds are ad-hoc signed and not Apple-notarized; macOS may require **System Settings → Privacy & Security → Open Anyway** after the first blocked launch.

## Build

On a Mac with Xcode command-line tools, run the edition's build script:

```sh
cd mac-music-system-stats
./build.sh
```

The app is created in that edition's directory. Building does not install, launch, or replace the running app. The Intel script targets `x86_64`; the other three target `arm64`. The same explicit target is used for Swift and Objective-C.

For a clean installer containing only the app:

```sh
python3 tools/package.py --app 'mac-music-system-stats/FLYnamic Island.app' --output release/FLYnamic-Island.dmg
```

## Development notes

- Music + Stats and Intel use the same application source snapshot. Intel Macs use the existing layout for a screen without a notch.
- Browser music is a separate YouTube Music/Chrome edition. It requires Chrome Automation permission and **View → Developer → Allow JavaScript from Apple Events**. It is not a general browser-player integration.
- Apple Music supports Favorites. Spotify's desktop scripting interface does not expose adding to Liked Songs.
- Paused music keeps flat dots. Artwork, album colors, playback controls, sound output selection and hover animations are preserved from the relevant edition.
- Stats read macOS counters directly; Activity Monitor does not need to be open. Memory graph height shows usage, while its color follows system memory pressure.
- Lock-screen work is paused. Historical helper files retained in source are not part of the normal build scripts. There is no Internet-speed page.

See [verification](docs/verification.md), [privacy](docs/privacy.md), and [third-party notices](THIRD_PARTY_NOTICES.md). No license for the original application code is granted by this private backup; retained third-party notices apply to their respective files.
