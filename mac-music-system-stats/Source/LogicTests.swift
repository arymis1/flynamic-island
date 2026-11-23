import Foundation
import CoreGraphics
import AppKit

@main enum LogicTests {
    static func main() {
        var selection = MediaSourceSelection()
        assert(selection.update(running: [], playing: []) == nil)
        assert(selection.update(running: [.spotify], playing: []) == .spotify)
        assert(selection.update(running: [.spotify], playing: [.spotify]) == .spotify)
        assert(selection.update(running: [.spotify, .appleMusic], playing: [.spotify]) == .spotify)
        assert(selection.update(running: [.spotify, .appleMusic], playing: [.spotify, .appleMusic]) == .appleMusic)
        assert(selection.update(running: [.spotify, .appleMusic], playing: [.spotify, .appleMusic]) == .appleMusic)
        assert(selection.update(running: [.spotify, .appleMusic], playing: [.spotify]) == .spotify)
        assert(selection.update(running: [.spotify, .appleMusic], playing: []) == .spotify)
        assert(selection.update(running: [.appleMusic], playing: []) == .appleMusic)
        assert(selection.update(running: [], playing: [.spotify]) == nil)
        assert(selection.update(running: [.spotify], playing: []) == .spotify)
        let available: Set<MediaSource> = [.appleMusic, .spotify, .youtubeMusic]
        assert(selection.update(running: available, playing: [.spotify]) == .spotify)
        assert(selection.update(running: available, playing: [.spotify, .youtubeMusic]) == .youtubeMusic)
        assert(selection.update(running: available, playing: [.spotify, .youtubeMusic]) == .youtubeMusic)
        assert(selection.update(running: available, playing: []) == .youtubeMusic)
        assert(selection.update(running: [.appleMusic], playing: [.appleMusic]) == .appleMusic)
        assert(SpotifyArtworkLoader.allowedURL("https://i.scdn.co/image/abc") != nil)
        assert(SpotifyArtworkLoader.allowedURL("https://image-cdn-ak.spotifycdn.com/image/abc") != nil)
        assert(SpotifyArtworkLoader.allowedURL("http://i.scdn.co/image/abc") == nil)
        assert(SpotifyArtworkLoader.allowedURL("https://i.scdn.co.evil.test/image/abc") == nil)
        assert(SpotifyArtworkLoader.allowedURL("https://user:secret@i.scdn.co/image/abc") == nil)
        assert(SpotifyArtworkLoader.allowedURL("file:///etc/passwd") == nil)
        var playback = PlaybackSync()
        let beforeClick = playback.revision
        assert(playback.observe(playing: true, revision: beforeClick, now: 0) == .accepted)
        playback.request(playing: false, previous: true)
        let pause = playback.revision
        assert(playback.observe(playing: true, revision: beforeClick, now: 1) == .ignored)
        assert(playback.observe(playing: false, revision: pause, now: 1) == .waiting)
        playback.sent(revision: pause, now: 2)
        // A successful send does not mean Music's next read has caught up.
        assert(playback.observe(playing: true, revision: pause, now: 2.1) == .waiting)
        assert(playback.pending?.desired == false)
        assert(playback.observe(playing: false, revision: pause, now: 2.2) == .accepted)
        assert(playback.pending == nil)
        assert(playback.observe(playing: true, revision: beforeClick, now: 2.3) == .ignored)
        // Several clicks while a command is running keep only the latest intent.
        playback.request(playing: true, previous: false)
        let oldPlay = playback.revision
        playback.request(playing: false, previous: true)
        let oldPause = playback.revision
        playback.request(playing: true, previous: false)
        let latestPlay = playback.revision
        playback.sent(revision: oldPlay, now: 3)
        assert(playback.pending?.deadline == nil)
        assert(playback.failed(revision: oldPause) == nil)
        assert(playback.pending?.desired == true)
        assert(playback.observe(playing: false, revision: oldPause, now: 3.1) == .ignored)
        playback.sent(revision: latestPlay, now: 3.2)
        assert(playback.observe(playing: false, revision: latestPlay, now: 4) == .waiting)
        assert(playback.observe(playing: true, revision: latestPlay, now: 4.1) == .accepted)
        playback.request(playing: false, previous: true)
        let failedPause = playback.revision
        assert(playback.failed(revision: failedPause) == true)
        assert(playback.pending == nil)
        assert(playback.observe(playing: false, revision: failedPause, now: 5) == .ignored)
        playback.request(playing: false, previous: true)
        let timeoutPause = playback.revision
        playback.sent(revision: timeoutPause, now: 5)
        assert(playback.observe(playing: true, revision: timeoutPause, now: 7.99) == .waiting)
        assert(playback.observe(playing: true, revision: timeoutPause, now: 8) == .timedOut)
        assert(playback.pending == nil)
        playback.request(playing: true, previous: false)
        let closedSession = playback.revision
        playback.reset()
        assert(playback.pending == nil)
        assert(playback.observe(playing: true, revision: closedSession, now: 9) == .ignored)
        var visibility = IslandVisibility()
        assert(LockScreenPresentation.session(onConsole: true, loggedIn: true, locked: true) == .locked)
        assert(LockScreenPresentation.session(onConsole: true, loggedIn: true, locked: false) == .desktop)
        assert(LockScreenPresentation.session(onConsole: false, loggedIn: true, locked: true) == .inactive)
        assert(LockScreenPresentation.session(onConsole: true, loggedIn: false, locked: true) == .inactive)
        assert(LockScreenPresentation.isVisible(manuallyHidden: false, session: .locked, enabled: true, hasTrack: true))
        assert(!LockScreenPresentation.isVisible(manuallyHidden: false, session: .locked, enabled: true, hasTrack: false))
        assert(!LockScreenPresentation.isVisible(manuallyHidden: true, session: .locked, enabled: true, hasTrack: true))
        assert(!LockScreenPresentation.isVisible(manuallyHidden: false, session: .locked, enabled: false, hasTrack: true))
        assert(!LockScreenPresentation.isVisible(manuallyHidden: false, session: .inactive, enabled: true, hasTrack: true))
        assert(LockScreenPresentation.isVisible(manuallyHidden: false, session: .desktop, enabled: false, hasTrack: false))
        assert(visibility.isVisible)
        assert(PlayerConnection.shouldReconnect(reportedStatus: "closed", processRunning: true))
        assert(!PlayerConnection.shouldReconnect(reportedStatus: "closed", processRunning: false))
        assert(!PlayerConnection.shouldReconnect(reportedStatus: "idle", processRunning: true))
        assert(PlayerConnection.presentationStatus(reportedStatus: "closed", processRunning: true, hadTrack: true) == "track")
        assert(PlayerConnection.presentationStatus(reportedStatus: "closed", processRunning: true, hadTrack: false) == "connecting")
        assert(PlayerConnection.presentationStatus(reportedStatus: "closed", processRunning: false, hadTrack: true) == "closed")
        visibility.toggleManualVisibility()
        assert(!visibility.isVisible)
        visibility.toggleManualVisibility()
        assert(visibility.isVisible)
        for playing in [false, true] {
            for running in [false, true] {
                for hasTrack in [false, true] {
                    for requested: IslandPane? in [nil, .stats, .music] {
                        let pane = IslandPane.selected(playing: playing, playerRunning: running, hasTrack: hasTrack, requested: requested)
                        if running || playing {
                            assert(pane == (requested ?? ((playing || hasTrack) ? .music : .stats)))
                        } else { assert(pane == .stats) }
                    }
                }
            }
        }
        // Pause keeps the music card; an explicit stats page also survives pause.
        assert(IslandPane.selected(playing: false, playerRunning: true, hasTrack: true, requested: nil) == .music)
        assert(IslandPane.selected(playing: false, playerRunning: true, hasTrack: true, requested: .stats) == .stats)
        assert(IslandPane.selected(playing: false, playerRunning: false, hasTrack: false, requested: nil) == .stats)
        assert(IslandLogic.seconds(0) == "0:00")
        var swipe = IslandSwipeTracker()
        assert(swipe.update(x: -10, y: 1, phase: .began) == nil)
        assert(swipe.update(x: -31, y: 1, phase: .changed) == .left) // quick switch before release
        assert(swipe.update(x: -80, y: 0, phase: .changed) == nil) // one switch per gesture
        assert(swipe.update(x: -80, y: 0, phase: .changed, momentum: true) == nil)
        assert(swipe.update(x: 0, y: 0, phase: .ended) == nil && !swipe.claimed)
        assert(swipe.update(x: 45, y: 1, phase: .began) == .right)
        swipe.reset()
        assert(swipe.update(x: 1, y: 20, phase: .began) == nil)
        assert(swipe.update(x: 100, y: 0, phase: .changed) == nil) // vertical intent stays vertical
        assert(swipe.update(x: 50, y: 50, phase: .began) == nil) // ambiguous diagonal
        assert(swipe.update(x: 100, y: 0, phase: .cancelled) == nil)
        assert(swipe.update(x: 80, y: 0, phase: .began, precise: false) == nil)
        assert(swipe.update(x: 80, y: 0, phase: .began, momentum: true) == nil)
        assert(IslandLogic.seconds(65.9) == "1:05")
        assert(IslandLogic.seconds(-10) == "0:00")
        assert(IslandLogic.seconds(.nan) == "0:00")
        assert(IslandLogic.boundedPosition(90, duration: 60) == 60)
        assert(IslandLogic.boundedPosition(-10, duration: 60) == 0)
        assert(IslandLogic.boundedPosition(.infinity, duration: 60) == 0)
        assert(IslandLogic.playhead(position: 12, anchor: 100, now: 100.9, playing: true, duration: 60) > 12.89)
        assert(IslandLogic.playhead(position: 12, anchor: 100, now: 120, playing: false, duration: 60) == 12)
        assert(IslandLogic.playhead(position: 12, anchor: 100, now: 99, playing: true, duration: 60) == 12)
        assert(IslandLogic.playhead(position: 59, anchor: 100, now: 105, playing: true, duration: 60) == 60)
        assert(IslandLogic.playhead(position: 30, anchor: 105, now: 105.25, playing: true, duration: 60) == 30.25)
        let pending = PendingFavorite(trackID: "a", desired: true, deadline: 110)
        assert(pending.resolve(trackID: "a", favorite: false, now: 101) == .waiting)
        assert(pending.resolve(trackID: "a", favorite: true, now: 105) == .confirmed)
        assert(pending.resolve(trackID: "a", favorite: false, now: 110) == .timedOut)
        assert(pending.resolve(trackID: "b", favorite: false, now: 101) == .changedTrack)
        assert(PendingFavorite(trackID: "a", desired: false, deadline: 110).resolve(trackID: "a", favorite: false, now: 102) == .confirmed)
        let screen = CGRect(x: 0, y: 0, width: 1470, height: 956)
        let compact = IslandLogic.panelFrame(screen: screen, topInset: 32, notchWidth: 179, expanded: false)
        let expanded = IslandLogic.panelFrame(screen: screen, topInset: 32, notchWidth: 179, expanded: true)
        assert(compact.maxY == screen.maxY && expanded.maxY == screen.maxY)
        assert(compact.midX == screen.midX && expanded.midX == screen.midX)
        assert(compact.width == 267 && compact.height == 32)
        // The artwork and waveform occupy separate wings outside the camera housing.
        let notchLeft = screen.midX - 179 / 2
        let notchRight = screen.midX + 179 / 2
        assert(compact.minX + 12 + 22 < notchLeft)
        assert(compact.maxX - 12 - 23 > notchRight)
        assert(expanded.height > compact.height)
        let external = CGRect(x: -1920, y: 100, width: 1920, height: 1080)
        let other = IslandLogic.panelFrame(screen: external, topInset: 0, notchWidth: 0, expanded: true)
        assert(other.midX == external.midX && other.maxY < external.maxY)
        var hover = HoverTracker()
        let notchPoint = CGPoint(x: compact.midX, y: compact.midY)
        assert(hover.update(pointer: notchPoint, collapsed: compact, expanded: expanded, isExpanded: false) == true)
        for _ in 0..<120 {
            assert(hover.update(pointer: notchPoint, collapsed: compact, expanded: expanded, isExpanded: true) == nil)
        }
        let controlsPoint = CGPoint(x: expanded.midX, y: expanded.minY + 40)
        assert(hover.update(pointer: controlsPoint, collapsed: compact, expanded: expanded, isExpanded: true) == nil)
        assert(hover.update(pointer: .zero, collapsed: compact, expanded: expanded, isExpanded: true) == false)
        assert(hover.update(pointer: .zero, collapsed: compact, expanded: expanded, isExpanded: false) == nil)
        assert(hover.update(pointer: notchPoint, collapsed: compact, expanded: expanded, isExpanded: false) == true)
        let red = ArtworkAccent.fromRGBA(Array(repeating: [UInt8(230), 30, 30, 255], count: 32).flatMap { $0 })
        let blue = ArtworkAccent.fromRGBA(Array(repeating: [UInt8(25), 50, 220, 255], count: 32).flatMap { $0 })
        assert(red.red > red.green * 3 && red.red > red.blue * 3)
        assert(blue.blue > blue.red * 3 && blue.blue > blue.green * 3)
        assert(ArtworkAccent.fromRGBA([100, 100, 100, 255]) == .neutral)
        assert(ArtworkAccent.fromRGBA([0, 0, 0, 0]) == .fallback)
        assert(ArtworkAccent.fromRGBA([]) == .fallback)
        let darkBlue = ArtworkAccent.fromRGBA([10, 10, 70, 255])
        assert(darkBlue.blue >= 0.78 && darkBlue.blue > darkBlue.red * 3)
        let mixed = ArtworkAccent.fromRGBA([0, 0, 0, 255, 255, 255, 255, 255, 40, 210, 50, 255])
        assert(mixed.green > mixed.red * 3)
        let image = NSImage(size: NSSize(width: 20, height: 20))
        image.lockFocus()
        NSColor.blue.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 20, height: 20)).fill()
        image.unlockFocus()
        let imageBlue = ArtworkAccent.extract(from: image)
        assert(imageBlue.blue > imageBlue.red * 3 && imageBlue.blue > imageBlue.green * 3)
        print("Logic checks passed: idle stats/music routing, manual hide, automatic players, hover continuity, artwork, and delayed playback confirmation.")
    }
}
