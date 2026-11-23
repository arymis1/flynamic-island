# Flynamic Island

Flynamic Island puts now-playing artwork and playback controls at the top of your Mac’s screen. Choose an edition based on your player and Mac.

| Edition | Folder & download | Processor | Players | CPU/RAM stats |
| --- | --- | --- | --- | --- |
| Music only | [mac-music-only](mac-music-only)<br>[Download DMG on Drive](https://drive.google.com/file/d/13cvpgZbwxjsyUvCEzO9qxehmhOHajvrQ/view) | Apple silicon | Apple Music, Spotify desktop | No |
| Music + System Stats | [mac-music-system-stats](mac-music-system-stats)<br>[Download combined DMG](https://github.com/arymis1/flynamic-island/releases/download/mac-combined-1.4/Flynamic-Island-Combined.dmg) | Apple silicon | Apple Music, Spotify desktop, YouTube Music in Chrome | Yes, two-finger swipe |
| Intel Mac | [mac-intel](mac-intel)<br>[Download DMG on Drive](https://drive.google.com/file/d/1rxc1DkYaafZZ37GbAXiMdj2ldSehNJL2/view) | Intel x86_64 | Apple Music, Spotify desktop | Yes, two-finger swipe |

## Downloads

Choose one of the three editions above. The [combined preview](https://github.com/arymis1/flynamic-island/releases/tag/mac-combined-1.4) adds YouTube Music to Music + System Stats. Open the waveform menu and choose **Player → YouTube Music in Chrome** to enable it. The [download guide](docs/downloads.md) has installation steps and earlier installers.

All editions require macOS 14 or later. Optional system audio analysis requires macOS 14.2 or later and system audio permission. See [privacy and permissions](docs/privacy.md) for which builds use it. The installers are ad-hoc signed, and macOS may show a first-launch warning. [Installation steps](docs/downloads.md)

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

- The Intel edition uses the original Music + System Stats code and the layout for Macs without a notch. Intel checks ran through Rosetta. A physical Intel Mac remains untested.
- YouTube Music in the combined edition requires Chrome Automation permission and **View → Developer → Allow JavaScript from Apple Events** in Chrome. The waveform menu lets you choose **Player → Automatic** or pick a connected player.
- Apple Music supports Favorites. Spotify's desktop scripting interface does not expose adding to Liked Songs.
- Paused music keeps flat dots. Artwork, album colors, playback controls, sound output selection and hover animations are preserved from the relevant edition.
- Stats read macOS counters directly; Activity Monitor does not need to be open. Memory graph height shows usage, while its color follows system memory pressure.
- Lock-screen work is paused. Historical helper files retained in source are not part of the normal build scripts. There is no Internet-speed page.

See [verification](docs/verification.md), [privacy](docs/privacy.md), and [third-party notices](THIRD_PARTY_NOTICES.md). Third-party notices cover the files they identify. The original application code has no license granted here.
