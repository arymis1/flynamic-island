# Privacy and permissions

Desktop editions read metadata and control playback through Scripting Bridge. macOS controls Automation consent. Music + Stats accesses matching `music.youtube.com` tabs through Chrome Apple Events. This requires Chrome’s JavaScript-from-Apple-Events setting. It starts checking Chrome after you choose **Player → Enable YouTube Music** from the menu bar icon. Enabling that Chrome setting is broader than a per-site permission, although this application's bridge restricts its page commands to the YouTube Music HTTPS origin.

The current Apple silicon Music Only and Music + System Stats builds animate their bars from playback state. The Intel edition and the original installers support optional system audio analysis. The audio analysis uses a Core Audio process tap and processes samples in memory without saving or uploading audio. The application does not change the user's Music route independently of the Mac's output selection.

Artwork can be fetched from the supported player's image CDN. Newer desktop snapshots may query Apple's public catalog with the song title and artist when native artwork is unavailable; matching uses album and duration locally. No account cookies or API credentials are required by these integrations.

CPU and RAM statistics are local kernel counter reads. They do not require Activity Monitor, administrator access, or a remote service.

This source backup excludes local credentials, personal screenshots, chat attachments, logs, generated application bundles and build caches. Distribution installers live separately as Release assets. No privacy database, system-wide Gatekeeper policy, or account permission is reset by the repository tooling.
