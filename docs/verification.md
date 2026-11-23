# Repository verification

This page records checks for the November 1, 2026 import. The source and build numbers on `main` have progressed since that import.

## Provenance

- Music-only sources: preserved version 1.2 build 5 source archive.
- Music + Stats: current version 1.3 build 25 sources.
- Browser: existing YouTube Music edition version 1.0 build 1 sources/resources.
- Intel: version 1.3 build 25 sources, byte-identical to Music + Stats; different compilation target.
- Original source locations and personal working files are not part of this repository.

Each edition retains its own source snapshot and build script so changes can be reviewed separately. Swift and Objective-C now both receive an explicit matching architecture; application source behavior is unchanged. The packager takes an explicit app path and defaults to a local `release` folder instead of reading the installed app.

## Test scope

Historical checks covered playback synchronization, hover and page routing, CPU/memory accounting, audio-band analysis and artwork handling. Intel unit checks ran as x86_64 processes through Rosetta on an Apple-silicon Mac; this does not establish physical Intel UI, audio-tap or permission behavior. No new live player commands or permissions are exercised by the source import.

## Import checks completed

- All four application source snapshots compare byte-for-byte with their preserved originals.
- All four edition build scripts completed successfully from clean source folders using the installed SDK, and each application passed strict/deep signature verification. Swift and Objective-C target architectures agree.
- Executable inspection confirms arm64 for the three Apple-silicon editions and x86_64 for the Intel edition.
- Source files were checked for common token/private-key signatures, personal email addresses, and machine-specific user/temp paths; none were found. Test fixtures deliberately include invalid credential-bearing URLs to test rejection; these are not real secrets.
- Build artifacts, local state, screenshots, generated archives and signing materials are excluded from the source commit. Release assets preserve the existing installer bytes and checksums.
- These are build, source-integrity and packaging checks. No fresh live-player, physical-Intel, permission or UI test is claimed. Installed applications and original project folders were not changed.

The relocated packager also passed an end-to-end read-only mount test: the image contains only FLYnamic Island.app and preserves the source app hashes and signature. This test image was not substituted for the preserved Release installer.
