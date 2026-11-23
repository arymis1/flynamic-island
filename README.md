# Flynamic Island

Now-playing artwork and music controls at the top of your Mac’s screen.

| Edition | Mac | Players | CPU/RAM | Download |
| --- | --- | --- | --- | --- |
| [Music Only](mac-music-only) | Apple silicon | Apple Music, Spotify | No | [DMG](https://github.com/arymis1/flynamic-island/releases/download/mac-editions-2026-11-23-build37/Flynamic-Island-Music-Only.dmg) |
| [Music + Stats](mac-music-system-stats) | Apple silicon | Apple Music, Spotify, YouTube Music in Chrome | Yes | [DMG](https://github.com/arymis1/flynamic-island/releases/download/mac-editions-2026-11-23-build37/Flynamic-Island-Combined.dmg) |
| [Intel](mac-intel) | Intel | Apple Music, Spotify | Yes | [DMG](https://github.com/arymis1/flynamic-island/releases/download/mac-editions-2026-11-23-build37/Flynamic-Island-Intel.dmg) |

## Install

Requires macOS 14 or later. Open the DMG, drag Flynamic into Applications, and open it. See [setup](docs/downloads.md) for updates and first-launch permissions.

## How to use it

- **Open the island.** Hover at the top center of your screen to expand it. Click the pin to keep it open.
- **Control playback.** See the song and album art, play or pause, skip tracks, drag the progress bar to seek, and adjust volume.
- **Swipe between Music and Stats.** On the Stats and Intel editions, swipe left with two fingers over the expanded island for Music, or right for live CPU and memory usage.
- **Switch players.** Music + Stats follows playback automatically. Use the waveform menu’s **Player** submenu to pick a source manually. For Chrome, start with **Enable YouTube Music** in the waveform menu. [Chrome setup](mac-music-system-stats#youtube-music-setup)

## Build

With Xcode command-line tools installed, run `./build.sh` from your edition’s folder. The app appears in that folder.

[Privacy](docs/privacy.md) · [Verification](docs/verification.md) · [Third-party notices](THIRD_PARTY_NOTICES.md)
