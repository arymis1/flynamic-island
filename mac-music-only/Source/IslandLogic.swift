import Foundation
import CoreGraphics

enum MediaSource: String, CaseIterable, Hashable {
    case appleMusic, spotify
    var bundleIdentifier: String { self == .spotify ? "com.spotify.client" : "com.apple.Music" }
    var title: String { self == .spotify ? "Spotify" : "Apple Music" }
}

struct MediaSourceSelection {
    private(set) var current: MediaSource?
    private var previouslyPlaying = Set<MediaSource>()
    mutating func update(running: Set<MediaSource>, playing: Set<MediaSource>) -> MediaSource? {
        let playing = playing.intersection(running)
        let newlyPlaying = playing.subtracting(previouslyPlaying)
        previouslyPlaying = playing
        if newlyPlaying.count == 1 { current = newlyPlaying.first }
        else if let current, playing.contains(current) { return current }
        else if let next = MediaSource.allCases.first(where: { playing.contains($0) }) { current = next }
        else if let current, running.contains(current) { return current }
        else { current = MediaSource.allCases.first(where: { running.contains($0) }) }
        return current
    }
}

struct MusicIslandVisibility {
    private(set) var musicRunning = false
    private(set) var manuallyHidden = false
    var isVisible: Bool { musicRunning && !manuallyHidden }
    mutating func updateMusicRunning(_ running: Bool) {
        if running && !musicRunning { manuallyHidden = false }
        musicRunning = running
    }
    mutating func toggleManualVisibility() {
        if musicRunning { manuallyHidden.toggle() }
    }
}

struct PendingFavorite {
    enum Resolution { case waiting, confirmed, timedOut, changedTrack }
    let trackID: String
    let desired: Bool
    let deadline: Double
    func resolve(trackID: String, favorite: Bool, now: Double) -> Resolution {
        if trackID != self.trackID { return .changedTrack }
        if favorite == desired { return .confirmed }
        return now >= deadline ? .timedOut : .waiting
    }
}

struct PlaybackSync {
    struct Request {
        let revision: Int
        let desired: Bool
        let previous: Bool
        var deadline: Double?
    }
    enum Observation { case ignored, waiting, accepted, timedOut }
    private(set) var revision = 0
    private(set) var pending: Request?

    mutating func request(playing: Bool, previous: Bool) {
        revision += 1
        pending = Request(revision: revision, desired: playing, previous: previous)
    }
    mutating func sent(revision: Int, now: Double) {
        guard pending?.revision == revision else { return }
        pending?.deadline = now + 3
    }
    mutating func observe(playing: Bool, revision: Int, now: Double) -> Observation {
        // A read queued before the latest click must never reverse that click.
        guard revision == self.revision else { return .ignored }
        guard let request = pending else { return .accepted }
        guard let deadline = request.deadline else { return .waiting }
        if playing == request.desired { pending = nil; return .accepted }
        if now < deadline { return .waiting }
        pending = nil
        return .timedOut
    }
    mutating func failed(revision: Int) -> Bool? {
        guard let request = pending, request.revision == revision else { return nil }
        reset()
        return request.previous
    }
    mutating func reset() {
        revision += 1
        pending = nil
    }
}

struct HoverTracker {
    private(set) var isInside = false
    mutating func update(pointer: CGPoint, collapsed: CGRect, expanded: CGRect, isExpanded: Bool) -> Bool? {
        let region = (isExpanded ? expanded : collapsed).insetBy(dx: -3, dy: -2)
        let inside = region.contains(pointer)
        guard inside != isInside else { return nil }
        isInside = inside
        return inside
    }
}

enum IslandLogic {
    static func playhead(position: Double, anchor: Double, now: Double, playing: Bool, duration: Double) -> Double {
        boundedPosition(position + (playing ? max(0, now - anchor) : 0), duration: duration)
    }
    static func seconds(_ value: Double) -> String {
        guard value.isFinite else { return "0:00" }
        let total = Int(max(0, min(value, 359_999)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
    static func boundedPosition(_ position: Double, duration: Double) -> Double {
        guard position.isFinite, duration.isFinite, duration > 0 else { return 0 }
        return min(max(0, position), duration)
    }
    static func panelFrame(screen: CGRect, topInset: CGFloat, notchWidth: CGFloat, expanded: Bool) -> CGRect {
        let width: CGFloat = expanded ? 386 : (topInset > 0 ? max(120, notchWidth) + 88 : 230)
        let height: CGFloat = expanded ? (topInset > 0 ? topInset + 232 : 246) : (topInset > 0 ? topInset : 40)
        let top = screen.maxY - (topInset > 0 ? 0 : 30)
        return CGRect(x: screen.midX - width / 2, y: top - height, width: width, height: height)
    }
}
