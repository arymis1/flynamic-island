import Foundation
import CoreGraphics

enum MediaSource: String, CaseIterable, Hashable {
    case appleMusic, spotify, youtubeMusic
    static var allCases: [MediaSource] { [.youtubeMusic] }
    var bundleIdentifier: String { self == .youtubeMusic ? "com.google.Chrome" : (self == .spotify ? "com.spotify.client" : "com.apple.Music") }
    var title: String { self == .youtubeMusic ? "YouTube Music" : (self == .spotify ? "Spotify" : "Apple Music") }
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

enum IslandPane: Equatable {
    case stats, music
    static func selected(playing: Bool, playerRunning: Bool, hasTrack: Bool, requested: IslandPane?) -> IslandPane {
        return requested ?? .music
    }
}

enum PlayerConnection {
    static func shouldReconnect(reportedStatus: String, processRunning: Bool) -> Bool {
        reportedStatus == "closed" && processRunning
    }
    static func presentationStatus(reportedStatus: String, processRunning: Bool, hadTrack: Bool) -> String {
        shouldReconnect(reportedStatus: reportedStatus, processRunning: processRunning)
            ? (hadTrack ? "track" : "connecting") : reportedStatus
    }
}

struct IslandSwipeTracker {
    enum Phase { case began, changed, ended, cancelled }
    enum Direction { case left, right }
    private enum Axis { case pending, horizontal, vertical }
    private var axis = Axis.pending
    private var x = 0.0
    private var y = 0.0
    private(set) var claimed = false

    mutating func reset() { self = IslandSwipeTracker() }
    mutating func update(x deltaX: Double, y deltaY: Double, phase: Phase,
                         precise: Bool = true, momentum: Bool = false) -> Direction? {
        guard precise, !momentum else { return nil }
        if phase == .began { reset() }
        defer { if phase == .ended || phase == .cancelled { reset() } }
        guard phase != .cancelled, !claimed, axis != .vertical else { return nil }
        x += deltaX; y += deltaY
        if axis == .pending {
            if abs(y) >= 12 && abs(y) > abs(x) * 1.5 { axis = .vertical }
            else if abs(x) >= 12 && abs(x) > abs(y) * 1.5 { axis = .horizontal }
        }
        guard axis == .horizontal, abs(x) >= 40 else { return nil }
        claimed = true
        return x < 0 ? .left : .right
    }
}

struct IslandVisibility {
    private(set) var manuallyHidden = false
    var isVisible: Bool { !manuallyHidden }
    mutating func toggleManualVisibility() { manuallyHidden.toggle() }
}

enum ScreenSessionState: Equatable { case desktop, locked, inactive }

enum LockScreenPresentation {
    static func isVisible(manuallyHidden: Bool, session: ScreenSessionState, enabled: Bool, hasTrack: Bool) -> Bool {
        guard !manuallyHidden else { return false }
        switch session {
        case .desktop: return true
        case .locked: return enabled && hasTrack
        case .inactive: return false
        }
    }
    static func session(onConsole: Bool, loggedIn: Bool, locked: Bool) -> ScreenSessionState {
        guard onConsole && loggedIn else { return .inactive }
        return locked ? .locked : .desktop
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
