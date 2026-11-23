# Mac downloads

Choose the edition for your music player and Mac processor. The table lists the original public installers. Build from the source on `main` for newer changes.

| Edition | Installer version / build | GitHub DMG | Google Drive |
| --- | --- | --- | --- |
| Music only, Apple silicon | 1.2 / 5 | [Download](https://github.com/arymis1/flynamic-island/releases/download/mac-editions-2026-11-01/FLYnamic-Island-Music-Only-Apple-Silicon.dmg) | [Drive](https://drive.google.com/file/d/13cvpgZbwxjsyUvCEzO9qxehmhOHajvrQ/view) |
| Music + System Stats, Apple silicon | 1.3 / 25 | [Download](https://github.com/arymis1/flynamic-island/releases/download/mac-editions-2026-11-01/FLYnamic-Island-Music-System-Stats-Apple-Silicon.dmg) | [Drive](https://drive.google.com/file/d/1krZzsMbrvYTMSnyBAsTGMTQquP5BvggI/view) |
| Browser YouTube Music + Stats, Apple silicon | 1.0 / 1 | [Download](https://github.com/arymis1/flynamic-island/releases/download/mac-editions-2026-11-01/FLYnamic-Island-Browser-YouTube-Music.dmg) | [Drive](https://drive.google.com/file/d/1uiuHCaczqXB1Yz0qnlAA5a4m9M_3TRtt/view) |
| Intel Mac Music + System Stats | 1.3 / 25 | [Download](https://github.com/arymis1/flynamic-island/releases/download/mac-editions-2026-11-01/FLYnamic-Island-Intel.dmg) | [Drive](https://drive.google.com/file/d/1rxc1DkYaafZZ37GbAXiMdj2ldSehNJL2/view) |

The [release manifest](release-manifest.json) lists installer sizes and SHA-256 hashes.

1. Quit Flynamic if it’s running.
2. Open the DMG and drag the app into Applications. Choose **Replace** if you’re updating the same edition.
3. Open Flynamic from Applications. The app is ad-hoc signed, so macOS may require **System Settings → Privacy & Security → Open Anyway** after the first launch attempt.

Music Only, Music + System Stats, and Intel share an app name and bundle identity. Install one of those editions at a time. Browser Music has a separate app identity. See [privacy and permissions](privacy.md) for player-specific setup.
