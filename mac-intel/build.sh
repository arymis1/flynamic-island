#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
bundle="$PWD/FLYnamic Island.app"
build_dir="$PWD/.build"
mkdir -p "$build_dir" "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
xcrun clang -fobjc-arc -target x86_64-apple-macosx14.0 -c Source/MusicBridge.m -o "$build_dir/MusicBridge.o"
xcrun clang -fobjc-arc -target x86_64-apple-macosx14.0 -c Source/AudioMeter.m -o "$build_dir/AudioMeter.o"
xcrun swiftc -swift-version 5 -O -parse-as-library -target x86_64-apple-macosx14.0 \
  -import-objc-header Source/MusicBridge.h Source/App.swift Source/IslandLogic.swift Source/ArtworkAccent.swift Source/AudioVisualization.swift Source/SpotifyArtwork.swift Source/AppleArtwork.swift Source/SystemStats.swift Source/SystemStatsView.swift \
  "$build_dir/MusicBridge.o" "$build_dir/AudioMeter.o" -framework AppKit -framework SwiftUI -framework ScriptingBridge \
  -framework Carbon -framework QuartzCore -framework CoreAudio -o "$bundle/Contents/MacOS/MusicIsland"
/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$bundle/Contents/Info.plist" >/dev/null 2>&1 || cat > "$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>FLYnamic Island</string>
<key>CFBundleDisplayName</key><string>FLYnamic Island</string>
<key>CFBundleIdentifier</key><string>local.aryan.music-island</string>
<key>CFBundleExecutable</key><string>MusicIsland</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrefersDisplaySafeAreaCompatibilityMode</key><false/>
<key>NSAppleEventsUsageDescription</key><string>FLYnamic Island shows your current song and lets you play, pause, skip, seek, and adjust volume in Apple Music.</string>
</dict></plist>
PLIST
/usr/libexec/PlistBuddy -c 'Set :NSAudioCaptureUsageDescription FLYnamic Island analyzes the selected Spotify or Apple Music audio to animate live level bars. Audio is never saved or uploaded.' "$bundle/Contents/Info.plist" 2>/dev/null || /usr/libexec/PlistBuddy -c 'Add :NSAudioCaptureUsageDescription string FLYnamic Island analyzes the selected Spotify or Apple Music audio to animate live level bars. Audio is never saved or uploaded.' "$bundle/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :NSAppleEventsUsageDescription FLYnamic Island shows the current song and controls playback in Spotify or Apple Music.' "$bundle/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 1.3' "$bundle/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 27' "$bundle/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Delete :NSLocationUsageDescription' "$bundle/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c 'Delete :NSLocationWhenInUseUsageDescription' "$bundle/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c 'Set :CFBundleName FLYnamic Island' "$bundle/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName FLYnamic Island' "$bundle/Contents/Info.plist"
cp Resources/PrivacyInfo.xcprivacy "$bundle/Contents/Resources/PrivacyInfo.xcprivacy"
codesign --force --sign - "$bundle"
echo "Built: $bundle"
