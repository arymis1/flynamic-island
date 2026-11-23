# Flynamic Island — Music + System Stats

Apple Music, Spotify desktop, and YouTube Music in Chrome, with CPU/RAM stats and two-finger page swipe. Version 1.4, build 37. Apple silicon.

The compact bars animate when a song plays and settle into dots when paused. They use playback state and require no system audio capture. The expanded panel uses Liquid Glass on macOS 26 and later.

Build with `./build.sh` on macOS with Xcode command-line tools. The result stays in this folder and is not installed or launched automatically. See [setup](../docs/downloads.md).

## YouTube Music setup

1. Open Google Chrome and visit [YouTube Music](https://music.youtube.com/).
2. Select **Enable YouTube Music** in the waveform menu, then allow Chrome Automation if prompted.
3. In Chrome, enable **View → Developer → Allow JavaScript from Apple Events**.

Choose **Player → Automatic** to follow playback or pick a connected player to keep it selected. Automatic switching continues after setup. Chrome integration targets YouTube Music tabs in regular Chrome windows.

## Download

[DMG](https://github.com/arymis1/flynamic-island/releases/download/mac-editions-2026-11-23-build37/Flynamic-Island-Combined.dmg) (version 1.4, build 37)
