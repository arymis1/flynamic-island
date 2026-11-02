# Mac downloads

Choose the edition matching the player's app and the Mac's processor. GitHub Releases require access to this private repository. Existing Drive files and their sharing settings are unchanged.

| Edition | Version / build | Release asset | Existing Drive download |
| --- | --- | --- | --- |
| Music only, Apple silicon | 1.2 / 5 | `FLYnamic-Island-Music-Only-Apple-Silicon.dmg` | [Drive](https://drive.google.com/file/d/13cvpgZbwxjsyUvCEzO9qxehmhOHajvrQ/view) |
| Music + System Stats, Apple silicon | 1.3 / 25 | `FLYnamic-Island-Music-System-Stats-Apple-Silicon.dmg` | [Drive](https://drive.google.com/file/d/1krZzsMbrvYTMSnyBAsTGMTQquP5BvggI/view) |
| Browser YouTube Music + Stats, Apple silicon | 1.0 / 1 | `FLYnamic-Island-Browser-YouTube-Music.dmg` | [Drive](https://drive.google.com/file/d/1uiuHCaczqXB1Yz0qnlAA5a4m9M_3TRtt/view) |
| Intel Mac Music + System Stats | 1.3 / 25 | `FLYnamic-Island-Intel.dmg` | [Drive](https://drive.google.com/file/d/1rxc1DkYaafZZ37GbAXiMdj2ldSehNJL2/view) |

`release-manifest.json` records the original installers' sizes and SHA-256 hashes. Initial Release assets are these preserved installers, not newly compiled artifacts. Rebuilding may yield different bytes and an ad-hoc signing identity that triggers new permission prompts.

Open the DMG, copy the app into Applications, and launch that copy. Approve only the normal permissions for the chosen player and optional audio analysis. The three desktop-player editions use the same app name and bundle identity; install one desktop edition at a time. The YouTube Music edition has a separate app identity.
