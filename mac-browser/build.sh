#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
bundle="$PWD/FLYnamic YT Music.app"
build_dir="$PWD/.build"
mkdir -p "$build_dir" "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
xcrun clang -fobjc-arc -target arm64-apple-macosx14.0 -c Source/MusicBridge.m -o "$build_dir/MusicBridge.o"
xcrun clang -fobjc-arc -target arm64-apple-macosx14.0 -c Source/AudioMeter.m -o "$build_dir/AudioMeter.o"
xcrun clang -fobjc-arc -target arm64-apple-macosx14.0 -c Source/ChromeBridge.m -o "$build_dir/ChromeBridge.o"
xcrun swiftc -swift-version 5 -O -parse-as-library -target arm64-apple-macosx14.0 \
  -import-objc-header Source/MusicBridge.h Source/App.swift Source/YouTubeMusicModel.swift Source/IslandLogic.swift Source/ArtworkAccent.swift Source/AudioVisualization.swift Source/SpotifyArtwork.swift Source/AppleArtwork.swift Source/SystemStats.swift Source/SystemStatsView.swift \
  "$build_dir/MusicBridge.o" "$build_dir/AudioMeter.o" "$build_dir/ChromeBridge.o" -framework AppKit -framework SwiftUI -framework ScriptingBridge \
  -framework Carbon -framework QuartzCore -framework CoreAudio -o "$bundle/Contents/MacOS/FLYnamicYTMusic"
/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$bundle/Contents/Info.plist" >/dev/null 2>&1 || cat > "$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>FLYnamic YT Music</string>
<key>CFBundleDisplayName</key><string>FLYnamic YT Music</string>
<key>CFBundleIdentifier</key><string>local.aryan.flynamic-yt-music</string>
<key>CFBundleExecutable</key><string>FLYnamicYTMusic</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrefersDisplaySafeAreaCompatibilityMode</key><false/>
<key>NSAppleEventsUsageDescription</key><string>FLYnamic YT Music shows your current song and lets you play, pause, skip, seek, and adjust volume in Apple Music.</string>
</dict></plist>
PLIST
/usr/libexec/PlistBuddy -c 'Set :NSAudioCaptureUsageDescription FLYnamic YT Music analyzes Chrome audio to animate live level bars. Other Chrome tabs can contribute audio. Audio is never saved or uploaded.' "$bundle/Contents/Info.plist" 2>/dev/null || /usr/libexec/PlistBuddy -c 'Add :NSAudioCaptureUsageDescription string FLYnamic YT Music analyzes Chrome audio to animate live level bars. Other Chrome tabs can contribute audio. Audio is never saved or uploaded.' "$bundle/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :NSAppleEventsUsageDescription FLYnamic YT Music reads song information and controls playback in YouTube Music tabs in Chrome. No other page content is read.' "$bundle/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 1.0' "$bundle/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 3' "$bundle/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Delete :NSLocationUsageDescription' "$bundle/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c 'Delete :NSLocationWhenInUseUsageDescription' "$bundle/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c 'Set :CFBundleName FLYnamic YT Music' "$bundle/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName FLYnamic YT Music' "$bundle/Contents/Info.plist"
cp Resources/YouTubeMusic.js "$bundle/Contents/Resources/YouTubeMusic.js"
cp Resources/PrivacyInfo.xcprivacy "$bundle/Contents/Resources/PrivacyInfo.xcprivacy"
codesign --force --sign - "$bundle"
echo "Built: $bundle"
