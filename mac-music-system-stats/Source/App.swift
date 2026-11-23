import AppKit
import SwiftUI
import Combine
import QuartzCore
import OSLog

struct AirPlayOutput: Identifiable {
    let id: String
    let name: String
    let selected: Bool
    let available: Bool
    let symbol: String
}

final class MusicModel: ObservableObject {
    @Published private(set) var isMusicRunning = false
    @Published private(set) var source = MediaSource.appleMusic
    var visibilityChanged: ((Bool) -> Void)?
    @Published var status = "connecting"
    var hasCurrentTrack: Bool { isMusicRunning && status == "track" }
    @Published var title = "FLYnamic Island"
    @Published var artist = ""
    @Published var album = ""
    @Published var artwork: NSImage?
    @Published var artworkAccent = ArtworkAccent.fallback
    @Published var artworkBackdrop: NSImage?
    var playbackActivityChanged: ((Bool) -> Void)?
    @Published var playing = false { didSet {
        if oldValue != playing { playbackActivityChanged?(playing) }
    } }
    @Published var favorited = false
    @Published var favoriteAvailable = false
    @Published var updatingFavorite = false
    @Published var shuffleEnabled = false
    @Published var shuffleAvailable = false
    @Published var updatingShuffle = false
    private var shuffleRevision = 0
    private var pendingShuffle: (desired: Bool, deadline: Double)?
    private var pendingFavorite: PendingFavorite?
    private var trackID = ""
    @Published var position = 0.0
    @Published var duration = 0.0
    @Published private(set) var volume = 50.0
    private var volumeRevision = 0
    private var volumeCommandInFlight = false
    private var pendingVolume: (target: Double, deadline: TimeInterval)?
    @Published var busy = false
    @Published var message = ""
    @Published var airPlayOutputs: [AirPlayOutput] = []
    @Published var airPlayLoading = false
    @Published var airPlayError = ""
    private let queue = DispatchQueue(label: "local.music-island.music", qos: .userInitiated)
    private let authorizationQueue = DispatchQueue(label: "local.music-island.authorization", qos: .userInitiated, attributes: .concurrent)
    private var authorizationRequest: UUID?
    private var authorizationCheckRevision = 0
    private var started = false
    private let bridges: [MediaSource: MusicBridge] = Dictionary(uniqueKeysWithValues: MediaSource.allCases.filter { $0 != .youtubeMusic }.map {
        ($0, MusicBridge(bundleIdentifier: $0.bundleIdentifier))
    })
    private var bridge: MusicBridge { bridges[source]! }
    private var runningPIDs: [MediaSource: pid_t] = [:]
    private var playingSources = Set<MediaSource>()
    private var sourceSelection = MediaSourceSelection()
    private var selectionTimer: Timer?
    private var selectionPolling = false
    private let chromeLog = Logger(subsystem: "local.aryan.music-island", category: "YouTubeMusic")
    private let chrome = ChromeBridge()
    private let chromeQueue = DispatchQueue(label: "local.music-island.chrome", qos: .userInitiated)
    private var chromePID: pid_t?
    private var chromeTrackAvailable = false
    private var chromePlaying = false
    private var chromePolling = false
    private var chromeAuthorizationRequest: UUID?
    private var chromeGeneration = 0
    private(set) var chromeStatus = "closed"
    private(set) var youtubeEnabled = UserDefaults.standard.bool(forKey: "youtubeMusicEnabled")
    private(set) var preferredSource: MediaSource?
    var availableSources: Set<MediaSource> {
        var sources = Set(runningPIDs.keys)
        if chromeTrackAvailable { sources.insert(.youtubeMusic) }
        return sources
    }
    private var playerQueue: DispatchQueue { source == .youtubeMusic ? chromeQueue : queue }
    private let youtubeArtwork = YouTubeArtworkLoader()
    private let spotifyArtwork = SpotifyArtworkLoader()
    private let appleArtwork = AppleArtworkLoader()
    private var artworkURL = ""
    private var timer: Timer?
    private var playbackTimer: Timer?
    private var playbackPolling = false
    private var positionAnchorTime = ProcessInfo.processInfo.systemUptime
    private var playbackSync = PlaybackSync()
    private var playbackCommandInFlight = false
    private var polling = false
    private var authorized = false
    private var paletteImage: NSImage?
    private var palette = ArtworkAccent.fallback
    private var backdrop: NSImage?
    private(set) var sessionGeneration = 0

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
        let playbackTimer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in self?.refreshPlayback() }
        RunLoop.main.add(playbackTimer, forMode: .common)
        self.playbackTimer = playbackTimer
        // Workspace notifications can be missed during launch/restart. A cheap
        // process check also repairs detection when only one player is open.
        let selectionTimer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.refreshPlayers() }
        selectionTimer.tolerance = 0.2
        RunLoop.main.add(selectionTimer, forMode: .common)
        self.selectionTimer = selectionTimer
        timer?.fireDate = .distantFuture
        playbackTimer.fireDate = .distantFuture
        selectionTimer.fireDate = .distantFuture
        status = "closed"
    }
    func start() {
        guard !started else { return }
        started = true
        selectionTimer?.fireDate = Date(timeIntervalSinceNow: 2)
        refreshPlayers()
    }
    func refreshPlayers(excludingPID: pid_t? = nil) {
        guard started else { return }
        var pids: [MediaSource: pid_t] = [:]
        for candidate in bridges.keys {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: candidate.bundleIdentifier)
                .first(where: { !$0.isTerminated && $0.processIdentifier != excludingPID }) {
                pids[candidate] = app.processIdentifier
                if runningPIDs[candidate] != app.processIdentifier {
                    let bridge = bridges[candidate]!
                    let pid = app.processIdentifier
                    queue.async { _ = bridge.connect(toProcessIdentifier: pid) }
                }
            }
        }
        let processChanged = pids[source] != runningPIDs[source]
        runningPIDs = pids
        playingSources.formIntersection(Set(pids.keys))
        updateChromeProcess(excludingPID: excludingPID)
        selectPlayer(force: processChanged)
        if isMusicRunning && !authorized && !busy { connect(request: false) }
        if pids.count > 1 || (chromeTrackAvailable && !pids.isEmpty) { probePlayers() }
    }
    func playerNotification(source: MediaSource, playing: Bool) {
        guard runningPIDs[source] != nil else { return }
        if source == self.source && playbackSync.pending != nil { return }
        if playing { playingSources.insert(source) } else { playingSources.remove(source) }
        selectPlayer()
    }
    private func probePlayers() {
        guard !selectionPolling else { return }
        selectionPolling = true
        let pids = runningPIDs
        let bridges = bridges
        queue.async {
            var playing = Set<MediaSource>()
            for candidate in pids.keys {
                let bridge = bridges[candidate]!
                if bridge.permissionRequestingConsent(false) == 0,
                   bridge.playbackState()["playing"] as? Bool == true { playing.insert(candidate) }
            }
            DispatchQueue.main.async {
                self.selectionPolling = false
                guard self.runningPIDs == pids else { return }
                if self.source != .youtubeMusic, self.playbackSync.pending != nil {
                    if self.playing { playing.insert(self.source) } else { playing.remove(self.source) }
                }
                self.playingSources = playing
                self.selectPlayer()
            }
        }
    }
    private func selectPlayer(force: Bool = false) {
        let available = availableSources
        var playing = playingSources
        if chromePlaying { playing.insert(.youtubeMusic) }
        let automatic = sourceSelection.update(running: available, playing: playing)
        if let preferredSource, !available.contains(preferredSource) { self.preferredSource = nil }
        activate(preferredSource ?? automatic, force: force)
    }

    func choosePlayer(_ source: MediaSource?) {
        preferredSource = source
        selectPlayer()
    }

    func setupYouTubeMusic() {
        guard youtubeEnabled else {
            setYouTubeEnabled(true)
            return
        }
        switch chromeStatus {
        case "permission": requestChromeConsent()
        case "denied", "permission-pending":
            if let automation = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                NSWorkspace.shared.open(automation)
            }
        case "closed", "idle": openYouTubeMusic()
        default: refreshPlayers()
        }
    }

    func setYouTubeEnabled(_ enabled: Bool) {
        youtubeEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "youtubeMusicEnabled")
        if enabled {
            updateChromeProcess(excludingPID: nil, probe: false)
            if chromePID == nil { openYouTubeMusic() }
            else { requestChromeConsent() }
        } else {
            refreshPlayers()
        }
    }

    func requestChromeConsent() {
        guard youtubeEnabled, chromePID != nil, chromeAuthorizationRequest == nil else { return }
        let request = UUID()
        chromeAuthorizationRequest = request
        chromeStatus = "permission-wait"
        let generation = chromeGeneration
        NSApp.activate(ignoringOtherApps: true)
        authorizationQueue.async {
            let result = ChromeBridge().permissionRequestingConsent(true)
            DispatchQueue.main.async {
                guard self.chromeAuthorizationRequest == request else { return }
                self.chromeAuthorizationRequest = nil
                guard self.chromeGeneration == generation else { return }
                self.chromeLog.info("Chrome Automation check returned \(result)")
                self.chromeStatus = result == 0 ? "connecting" : result == -1743 ? "denied" : "permission"
                self.probeChrome()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self, self.chromeGeneration == generation, self.chromeAuthorizationRequest == request else { return }
            self.chromeStatus = "permission-pending"
        }
    }

    private func updateChromeProcess(excludingPID: pid_t?, probe: Bool = true) {
        let pid = youtubeEnabled ? NSRunningApplication.runningApplications(withBundleIdentifier: MediaSource.youtubeMusic.bundleIdentifier)
            .first(where: { !$0.isTerminated && $0.processIdentifier != excludingPID })?.processIdentifier : nil
        if pid != chromePID {
            chromeGeneration += 1
            chromePID = pid
            chromeTrackAvailable = false
            chromePlaying = false
            chromeStatus = pid == nil ? "closed" : "connecting"
        }
        if probe { probeChrome() }
    }

    private func probeChrome() {
        guard chromePID != nil, chromeAuthorizationRequest == nil, !chromePolling else { return }
        chromePolling = true
        let generation = chromeGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self, self.chromeGeneration == generation, self.chromePolling,
                  self.chromeStatus == "connecting" else { return }
            self.chromeStatus = "permission-pending"
        }
        chromeQueue.async {
            let snapshot = self.chrome.snapshot()
            DispatchQueue.main.async {
                self.chromePolling = false
                guard self.chromeGeneration == generation else { return }
                let status = snapshot["status"] as? String ?? "error"
                if self.chromeStatus != status {
                    self.chromeLog.info("Chrome player status: \(status, privacy: .public)")
                    self.chromeStatus = status
                }
                self.chromeTrackAvailable = status == "track"
                self.chromePlaying = self.source == .youtubeMusic && self.playbackSync.pending != nil
                    ? self.playing : snapshot["playing"] as? Bool == true
                self.selectPlayer()
            }
        }
    }

    private func activate(_ selected: MediaSource?, force: Bool = false) {
        let running = selected != nil
        guard force || isMusicRunning != running || (selected != nil && selected != source) else { return }
        sessionGeneration += 1
        spotifyArtwork.cancel(); appleArtwork.cancel(); youtubeArtwork.cancel(); artworkURL = ""
        if let selected { source = selected }
        isMusicRunning = running
        polling = false; playbackPolling = false
        playbackSync.reset(); playbackCommandInFlight = false; pendingFavorite = nil
        shuffleRevision += 1; pendingShuffle = nil
        shuffleEnabled = false; shuffleAvailable = false; updatingShuffle = false
        busy = false; updatingFavorite = false; message = ""; authorized = false
        playing = false; favoriteAvailable = false
        trackID = ""; title = "FLYnamic Island"; artist = ""; album = ""
        artwork = nil; artworkBackdrop = nil; artworkAccent = .fallback
        position = 0; duration = 0
        pendingVolume = nil
        volume = 50
        timer?.fireDate = running ? Date() : .distantFuture
        playbackTimer?.fireDate = running ? Date() : .distantFuture
        status = running ? "connecting" : "closed"
        visibilityChanged?(running)
        if selected == .youtubeMusic {
            authorized = true
            refresh()
        } else if running { connect(request: false) }
    }
    func connect(request: Bool = true) {
        guard !busy, isMusicRunning, source != .youtubeMusic else { return }
        if request && authorizationRequest != nil {
            status = "permission-pending"
            return
        }
        busy = true
        authorizationCheckRevision += 1
        let revision = authorizationCheckRevision
        let selectedSource = source
        let generation = sessionGeneration
        let requestID = request ? UUID() : nil
        if let requestID {
            authorizationRequest = requestID
            status = "permission-wait"
            NSApp.activate(ignoringOtherApps: true)
        }
        // Consent is allowed to wait for a person; it must never occupy the
        // serial queue that refreshes playback or probes another player.
        authorizationQueue.async {
            let bridge = MusicBridge(bundleIdentifier: selectedSource.bundleIdentifier)
            let permission = bridge.permissionRequestingConsent(request)
            DispatchQueue.main.async {
                if let requestID, self.authorizationRequest == requestID { self.authorizationRequest = nil }
                guard self.sessionGeneration == generation, self.authorizationCheckRevision == revision else { return }
                self.busy = false
                self.authorized = permission == 0
                self.status = PlayerAuthorization.status(result: permission, running: self.isMusicRunning,
                                                         requestPending: self.authorizationRequest != nil)
                if self.authorized { self.refresh() }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self, self.sessionGeneration == generation,
                  self.authorizationCheckRevision == revision, self.busy, !self.authorized else { return }
            self.busy = false
            self.status = self.authorizationRequest != nil ? "permission-pending" : "connection-error"
        }
    }
    func refresh() {
        guard authorized, isMusicRunning, !polling else { return }
        polling = true
        let generation = sessionGeneration
        let playbackRevision = playbackSync.revision
        let shuffleRevision = shuffleRevision
        let volumeRevision = volumeRevision
        let source = source
        let desktopBridge = bridges[source]
        let pid = runningPIDs[source]
        playerQueue.async {
            let snapshot = desktopBridge?.snapshot(forRunningProcessIdentifier: pid ?? 0) ?? self.chrome.snapshot()
            let image = snapshot["artwork"] as? NSImage
            if desktopBridge != nil, image !== self.paletteImage {
                self.paletteImage = image
                self.palette = ArtworkAccent.extract(from: image)
                self.backdrop = ArtworkAccent.backdrop(from: image)
            }
            let accent = desktopBridge == nil ? .fallback : self.palette
            let backdrop = desktopBridge == nil ? nil : self.backdrop
            DispatchQueue.main.async {
                guard self.isMusicRunning, self.sessionGeneration == generation else { return }
                self.polling = false
                let newStatus = snapshot["status"] as? String ?? "error"
                if source == .youtubeMusic, newStatus != "track" {
                    self.probeChrome()
                    return
                }
                if newStatus == "closed" {
                    // Trust the actual process list before discarding a song.
                    self.refreshPlayers()
                    guard self.sessionGeneration == generation else { return }
                    self.status = PlayerConnection.presentationStatus(reportedStatus: newStatus,
                        processRunning: self.runningPIDs[self.source] != nil, hadTrack: self.status == "track")
                    if self.isMusicRunning { return }
                }
                if newStatus == "track" {
                    self.status = newStatus
                    let newID = snapshot["id"] as? String ?? ""
                    let trackChanged = newID != self.trackID
                    if trackChanged { self.message = "" }
                    self.trackID = newID
                    let nativeFavorite = snapshot["favorited"] as? Bool ?? false
                    self.favorited = nativeFavorite
                    if let pending = self.pendingFavorite {
                        switch pending.resolve(trackID: newID, favorite: nativeFavorite, now: ProcessInfo.processInfo.systemUptime) {
                        case .waiting: break
                        case .confirmed, .changedTrack:
                            self.pendingFavorite = nil; self.updatingFavorite = false; self.message = ""
                        case .timedOut:
                            self.pendingFavorite = nil; self.updatingFavorite = false
                            self.message = "Music hasn’t confirmed that change. Try again."
                        }
                    }
                    self.favoriteAvailable = snapshot["favoriteAvailable"] as? Bool ?? false
                    if self.shuffleRevision == shuffleRevision {
                        self.shuffleAvailable = snapshot["shuffleAvailable"] as? Bool ?? false
                        let nativeShuffle = snapshot["shuffle"] as? Bool ?? false
                        if let pending = self.pendingShuffle {
                            if self.shuffleAvailable && nativeShuffle == pending.desired {
                                self.pendingShuffle = nil; self.updatingShuffle = false
                                self.shuffleEnabled = nativeShuffle
                            } else if ProcessInfo.processInfo.systemUptime >= pending.deadline {
                                self.pendingShuffle = nil; self.updatingShuffle = false
                                self.shuffleEnabled = nativeShuffle
                                self.message = "\(self.source.title) hasn’t enabled shuffle for this queue."
                            }
                        } else { self.shuffleEnabled = nativeShuffle }
                    }
                    self.title = snapshot["title"] as? String ?? "Unknown track"
                    self.artist = snapshot["artist"] as? String ?? ""
                    self.album = snapshot["album"] as? String ?? ""
                    self.duration = snapshot["duration"] as? Double ?? 0
                    self.applyPlayback(position: snapshot["position"] as? Double ?? 0, playing: snapshot["playing"] as? Bool ?? false, revision: playbackRevision)
                    if let volume = snapshot["volume"] as? Double {
                        self.observeVolume(volume, revision: volumeRevision)
                    }
                    if self.source == .youtubeMusic {
                        self.loadYouTubeArtwork(snapshot["artworkURL"] as? String ?? "", trackID: newID, generation: generation)
                    } else if self.source == .spotify {
                        self.loadSpotifyArtwork(snapshot["artworkURL"] as? String ?? "", trackID: newID, generation: generation)
                    } else if let nativeArtwork = snapshot["artwork"] as? NSImage {
                        self.appleArtwork.cancel()
                        self.artwork = nativeArtwork
                        self.artworkAccent = accent
                        self.artworkBackdrop = backdrop
                    } else {
                        if trackChanged {
                            self.artwork = nil; self.artworkBackdrop = nil; self.artworkAccent = .fallback
                        }
                        self.loadAppleArtwork(trackID: newID, generation: generation)
                    }
                } else if self.playbackSync.pending == nil {
                    self.status = newStatus
                    self.playing = false
                    self.favoriteAvailable = false
                    self.shuffleAvailable = false
                    self.pendingShuffle = nil; self.updatingShuffle = false
                    self.pendingFavorite = nil; self.updatingFavorite = false
                    if newStatus == "closed" || newStatus == "idle" {
                        self.spotifyArtwork.cancel(); self.appleArtwork.cancel(); self.artworkURL = ""; self.trackID = ""
                        self.title = "FLYnamic Island"; self.artist = ""; self.artwork = nil
                        self.artworkAccent = .fallback
                        self.artworkBackdrop = nil
                        self.duration = 0; self.position = 0
                    }
                    if snapshot["code"] as? Int == -1743 { self.authorized = false; self.status = "denied" }
                }
            }
        }
    }
    private func loadYouTubeArtwork(_ url: String, trackID: String, generation: Int) {
        if artworkURL != url {
            artworkURL = url
            artwork = nil; artworkBackdrop = nil; artworkAccent = .fallback
        }
        youtubeArtwork.load(url) { [weak self] image in
            guard let self, self.sessionGeneration == generation, self.trackID == trackID,
                  self.artworkURL == url, self.artwork !== image else { return }
            self.artwork = image
            self.artworkAccent = ArtworkAccent.extract(from: image)
            self.artworkBackdrop = ArtworkAccent.backdrop(from: image)
        }
    }

    private func commandForCurrentTrack() -> (String, Double) -> Bool {
        if let desktopBridge = bridges[source] {
            return { desktopBridge.performCommand($0, value: $1) }
        }
        let id = trackID
        let pid = chromePID ?? 0
        return { [chrome] in chrome.performCommand($0, value: $1, trackID: id, expectedPID: pid) }
    }

    private func loadSpotifyArtwork(_ url: String, trackID: String, generation: Int) {
        if artworkURL != url {
            artworkURL = url
            artwork = nil; artworkBackdrop = nil; artworkAccent = .fallback
        }
        spotifyArtwork.load(url) { [weak self] image in
            guard let self, self.sessionGeneration == generation, self.status == "track", self.trackID == trackID, self.artworkURL == url else { return }
            guard image !== self.artwork else { return }
            self.artwork = image
            self.artworkAccent = ArtworkAccent.extract(from: image)
            self.artworkBackdrop = ArtworkAccent.backdrop(from: image)
        }
    }
    private func loadAppleArtwork(trackID: String, generation: Int) {
        appleArtwork.load(title: title, artist: artist, album: album, duration: duration) { [weak self] image in
            guard let self, self.sessionGeneration == generation, self.source == .appleMusic,
                  self.status == "track", self.trackID == trackID else { return }
            guard image !== self.artwork else { return }
            self.artwork = image
            self.artworkAccent = ArtworkAccent.extract(from: image)
            self.artworkBackdrop = ArtworkAccent.backdrop(from: image)
        }
    }
    private func observeVolume(_ reported: Double, revision: Int) {
        guard revision == volumeRevision else { return }
        if let pendingVolume {
            guard pendingVolume.deadline.isFinite,
                  abs(reported - pendingVolume.target) < 0.001 ||
                    ProcessInfo.processInfo.systemUptime >= pendingVolume.deadline else { return }
            self.pendingVolume = nil
        }
        if volume != reported { volume = reported }
    }

    func setVolume(_ requested: Double) {
        guard authorized, status == "track", requested.isFinite else { return }
        let target = min(100, max(0, requested.rounded()))
        guard target != volume else { return }
        volumeRevision += 1
        pendingVolume = (target, .infinity)
        volume = target
        message = ""
        sendVolumeIntent()
    }

    private func sendVolumeIntent() {
        guard !volumeCommandInFlight, authorized, status == "track",
              let pending = pendingVolume, !pending.deadline.isFinite else { return }
        volumeCommandInFlight = true
        let revision = volumeRevision
        let generation = sessionGeneration
        let send = commandForCurrentTrack()
        playerQueue.async {
            let success = send("volume", pending.target)
            DispatchQueue.main.async {
                self.volumeCommandInFlight = false
                guard self.sessionGeneration == generation, self.volumeRevision == revision else {
                    // Keep only the latest drag position while a command is in flight.
                    self.sendVolumeIntent()
                    return
                }
                self.pendingVolume = (pending.target, ProcessInfo.processInfo.systemUptime + (success ? 2 : 0))
                if !success { self.message = "Music couldn’t change volume. Try again." }
                self.refresh()
            }
        }
    }

    func command(_ command: String, value: Double = 0) {
        if command == "playpause" { togglePlayback(); return }
        guard authorized, status == "track", !busy else { return }
        busy = true
        message = ""
        let generation = sessionGeneration
        if command == "seek" { position = value; positionAnchorTime = ProcessInfo.processInfo.systemUptime }
        let send = commandForCurrentTrack()
        playerQueue.async {
            let success = send(command, value)
            DispatchQueue.main.async {
                guard self.isMusicRunning, self.sessionGeneration == generation else { return }
                self.busy = false
                if !success { self.message = "Music couldn’t complete that. Try again." }
                self.refreshPlayback()
            }
        }
    }
    private func togglePlayback() {
        guard authorized, isMusicRunning, status == "track" else { return }
        let previous = playing
        position = currentPosition()
        positionAnchorTime = ProcessInfo.processInfo.systemUptime
        playing.toggle()
        playbackSync.request(playing: playing, previous: previous)
        message = ""
        sendPlaybackIntent()
    }
    private func sendPlaybackIntent() {
        guard !playbackCommandInFlight, let request = playbackSync.pending else { return }
        playbackCommandInFlight = true
        let generation = sessionGeneration
        let send = commandForCurrentTrack()
        playerQueue.async {
            // Explicit commands remain correct even when Music's reported state lags.
            let success = send(request.desired ? "play" : "pause", 0)
            DispatchQueue.main.async {
                guard self.isMusicRunning, self.sessionGeneration == generation else { return }
                self.playbackCommandInFlight = false
                if self.playbackSync.pending?.revision != request.revision {
                    self.sendPlaybackIntent()
                } else if success {
                    self.playbackSync.sent(revision: request.revision, now: ProcessInfo.processInfo.systemUptime)
                } else if let previous = self.playbackSync.failed(revision: request.revision) {
                    self.position = self.currentPosition()
                    self.positionAnchorTime = ProcessInfo.processInfo.systemUptime
                    self.playing = previous
                    self.message = "Music couldn’t change playback. Try again."
                }
                self.refreshPlayback()
            }
        }
    }
    func currentPosition() -> Double {
        IslandLogic.playhead(position: position, anchor: positionAnchorTime, now: ProcessInfo.processInfo.systemUptime, playing: playing, duration: duration)
    }
    private func applyPlayback(position: Double, playing: Bool, revision: Int) {
        switch playbackSync.observe(playing: playing, revision: revision, now: ProcessInfo.processInfo.systemUptime) {
        case .ignored, .waiting: return
        case .accepted: break
        case .timedOut: message = "Music hasn’t confirmed playback. Try again."
        }
        self.position = IslandLogic.boundedPosition(position, duration: duration)
        positionAnchorTime = ProcessInfo.processInfo.systemUptime
        if self.playing != playing { self.playing = playing }
        if source != .youtubeMusic {
            if playing { playingSources.insert(source) } else { playingSources.remove(source) }
        }
    }
    func refreshPlayback() {
        guard source != .youtubeMusic, authorized, isMusicRunning, !busy, !polling, !playbackPolling else { return }
        playbackPolling = true
        let generation = sessionGeneration
        let playbackRevision = playbackSync.revision
        let bridge = bridge
        queue.async {
            let state = bridge.playbackState()
            DispatchQueue.main.async {
                guard self.isMusicRunning, self.sessionGeneration == generation else { return }
                self.playbackPolling = false
                if state["status"] as? String == "ready" {
                    self.applyPlayback(position: state["position"] as? Double ?? 0, playing: state["playing"] as? Bool ?? false, revision: playbackRevision)
                }
            }
        }
    }
    func toggleShuffle() {
        guard authorized, isMusicRunning, status == "track", shuffleAvailable, !updatingShuffle else { return }
        let previous = shuffleEnabled
        let desired = !previous
        shuffleRevision += 1
        let revision = shuffleRevision
        let generation = sessionGeneration
        let send = commandForCurrentTrack()
        shuffleEnabled = desired; updatingShuffle = true; message = ""
        pendingShuffle = (desired, .infinity)
        playerQueue.async {
            let success = send("shuffle", desired ? 1 : 0)
            DispatchQueue.main.async {
                guard self.sessionGeneration == generation, self.shuffleRevision == revision else { return }
                if success {
                    self.pendingShuffle = (desired, ProcessInfo.processInfo.systemUptime + 3)
                } else {
                    self.pendingShuffle = nil; self.updatingShuffle = false
                    self.shuffleEnabled = previous
                    self.message = "\(self.source.title) couldn’t change shuffle. Try again."
                }
                self.refresh()
            }
        }
    }
    func toggleFavorite() {
        guard authorized, status == "track", favoriteAvailable, !trackID.isEmpty, !busy, !updatingFavorite else { return }
        let expectedID = trackID
        let desired = !favorited
        busy = true
        updatingFavorite = true
        pendingFavorite = PendingFavorite(trackID: expectedID, desired: desired, deadline: ProcessInfo.processInfo.systemUptime + 10)
        message = ""
        let bridge = bridge
        let generation = sessionGeneration
        queue.async {
            let result = bridge.setFavorite(desired, forTrackID: expectedID)
            DispatchQueue.main.async {
                guard self.sessionGeneration == generation else { return }
                self.busy = false
                if result["success"] as? Bool == true {
                    if self.trackID == expectedID && result["confirmed"] as? Bool == true {
                        self.favorited = desired; self.pendingFavorite = nil; self.updatingFavorite = false
                    }
                } else {
                    self.pendingFavorite = nil; self.updatingFavorite = false
                    self.message = result["reason"] as? String == "changed"
                        ? "The song changed. Try the star again."
                        : "Music couldn’t update Favorites. Try again."
                }
                self.refresh()
            }
        }
    }
    func openYouTubeMusic() {
        guard let chrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier: MediaSource.youtubeMusic.bundleIdentifier),
              let page = URL(string: "https://music.youtube.com/") else { return }
        NSWorkspace.shared.open([page], withApplicationAt: chrome,
                                configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }
    func openMusic() {
        if source == .youtubeMusic {
            openYouTubeMusic()
            return
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleIdentifier) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }
    func loadAirPlayOutputs(clearError: Bool = true) {
        guard source != .youtubeMusic, authorized, !airPlayLoading else { return }
        airPlayLoading = true
        if clearError { airPlayError = "" }
        queue.async {
            let snapshot = self.bridges[.appleMusic]!.airPlayOutputs()
            DispatchQueue.main.async {
                self.airPlayLoading = false
                self.airPlayOutputs = (snapshot["outputs"] as? [[String: Any]] ?? []).compactMap { item in
                    guard let id = item["id"] as? String, let name = item["name"] as? String else { return nil }
                    return AirPlayOutput(id: id, name: name, selected: item["selected"] as? Bool ?? false,
                                         available: item["available"] as? Bool ?? false, symbol: item["symbol"] as? String ?? "hifispeaker")
                }
                if snapshot["status"] as? String != "ready" { self.airPlayError = "Open Music to check available outputs." }
            }
        }
    }
    func selectAirPlayOutput(_ id: String) {
        guard source != .youtubeMusic, authorized, !airPlayLoading else { return }
        airPlayLoading = true
        airPlayError = ""
        queue.async {
            let success = self.bridges[.appleMusic]!.selectAirPlayOutput(id)
            DispatchQueue.main.async {
                self.airPlayLoading = false
                if !success { self.airPlayError = "Couldn’t switch outputs. Try Sound Settings." }
                self.loadAirPlayOutputs(clearError: false)
            }
        }
    }
}

final class IslandState: ObservableObject {
    @Published var expanded = false
    @Published var pinned = false
    @Published var safeTop: CGFloat = 32
    @Published var collapsedWidth: CGFloat = 179
    @Published var showingAirPlay = false
    @Published var panelVisible = false
    @Published var requestedPane: IslandPane?
    var setExpanded: ((Bool) -> Void)?
    var pointerIsInside: () -> Bool = { false }
    var collapseWork: DispatchWorkItem?
    func hover(_ entered: Bool) {
        collapseWork?.cancel()
        if entered { setExpanded?(true) }
        else if !pinned && !showingAirPlay {
            let work = DispatchWorkItem { [weak self] in self?.setExpanded?(false) }
            collapseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: work)
        }
    }
    func togglePin() {
        pinned.toggle()
        UserDefaults.standard.set(pinned, forKey: "keepExpanded")
        if pinned { setExpanded?(true) }
        else if !pointerIsInside() { hover(false) }
    }
}

struct AirPlayPicker: View {
    @ObservedObject var music: MusicModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Sound").font(.system(size: 15, weight: .semibold))
                Spacer()
                if music.airPlayLoading { ProgressView().controlSize(.small) }
                else { Button { music.loadAirPlayOutputs() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain).help("Refresh outputs").accessibilityLabel("Refresh outputs") }
            }
            Divider()
            Text("Output").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            if music.airPlayOutputs.isEmpty && !music.airPlayLoading {
                Text("No outputs found. Check available speakers in Music.").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            ForEach(music.airPlayOutputs) { output in
                Button { music.selectAirPlayOutput(output.id) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: output.symbol).frame(width: 28, height: 28)
                            .foregroundStyle(output.selected ? Color.accentColor : .white)
                            .background(output.selected ? Color.white : Color.white.opacity(0.13), in: Circle())
                        Text(output.name).lineLimit(1)
                        Spacer()
                        if output.selected { Image(systemName: "checkmark").fontWeight(.semibold) }
                    }.padding(.vertical, 8).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(!output.available || music.airPlayLoading)
                    .accessibilityLabel(output.name).accessibilityValue(output.selected ? "Selected" : "Not selected")
            }
            if !music.airPlayError.isEmpty { Text(music.airPlayError).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            Divider()
            Button("Sound Settings…") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!)
            }.buttonStyle(.plain).font(.system(size: 12))
        }.padding(18).frame(width: 280).preferredColorScheme(.dark)
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    if !Task.isCancelled { music.loadAirPlayOutputs(clearError: false) }
                }
            }
    }
}

struct ArtView: View {
    var image: NSImage?
    var size: CGFloat
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.2).fill(LinearGradient(colors: [Color(red: 0.49, green: 0.08, blue: 0.19), Color(red: 0.14, green: 0.02, blue: 0.05)], startPoint: .topLeading, endPoint: .bottomTrailing))
            if let image { Image(nsImage: image).resizable().scaledToFill() }
            else { Image(systemName: "music.note").font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(.white.opacity(0.8)) }
        }
        .frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.2))
        .accessibilityLabel("Album artwork")
    }
}

struct PlaybackBars: View {
    let playing: Bool
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let barRanges: [Double] = [11, 18, 14, 9]

    var body: some View {
        let animating = playing && !reduceMotion
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !animating)) { context in
            // Two overlapping rhythms give the bars a smooth, staggered motion.
            let phase = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 4) * (.pi / 2)
            HStack(spacing: 2.5) {
                ForEach(barRanges.indices, id: \.self) { index in
                    let offset = Double(index)
                    let level = animating
                        ? 0.58 + 0.26 * sin(5 * phase - 0.9 * offset) + 0.10 * sin(7 * phase + 1.1 * offset)
                        : 0.58
                    Capsule().fill(color)
                        .frame(width: 3, height: 3 + (playing ? barRanges[index] * level : 0))
                }
            }
            .frame(width: 23, height: 24)
        }
        .accessibilityHidden(true)
    }
}

struct CircleControl: View {
    let symbol: String
    let label: String
    var prominent = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: prominent ? 28 : 20, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: prominent ? 48 : 44, height: prominent ? 48 : 44)
                .contentShape(Circle())
        }.buttonStyle(.plain).help(label).accessibilityLabel(label)
    }
}

struct MusicScrubber: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var value: Double
    var upperBound: Double
    var tint: Color
    var label: String
    var expandsOnDrag = false
    var onEditingChanged: (Bool) -> Void = { _ in }
    @State private var dragging = false
    @State private var hovered = false
    var body: some View {
        GeometryReader { geometry in
            let fraction = IslandLogic.boundedPosition(value, duration: max(1, upperBound)) / max(1, upperBound)
            ZStack(alignment: .leading) {
                if expandsOnDrag {
                    ZStack(alignment: .leading) {
                        Rectangle().fill(.white.opacity(dragging ? 0.28 : 0.17))
                        Rectangle().fill(dragging ? .white : tint)
                            .frame(width: geometry.size.width * fraction)
                    }
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.16)) { track in
                        track.frame(height: dragging ? 10 : 3)
                            .clipShape(Capsule())
                    }
                } else {
                    Capsule().fill(.white.opacity(0.17)).frame(height: 3)
                    Capsule().fill(tint).frame(width: geometry.size.width * fraction, height: 3)
                    Circle().fill(tint).frame(width: 7, height: 7)
                        .offset(x: max(0, geometry.size.width * fraction - 3.5))
                        .opacity(dragging || hovered ? 1 : 0)
                }
            }.frame(height: 18).contentShape(Rectangle())
                .onHover { hovered = $0 }
                .gesture(DragGesture(minimumDistance: 0).onChanged { gesture in
                    if !dragging { dragging = true; onEditingChanged(true) }
                    value = min(1, max(0, gesture.location.x / max(1, geometry.size.width))) * upperBound
                }.onEnded { gesture in
                    value = min(1, max(0, gesture.location.x / max(1, geometry.size.width))) * upperBound
                    onEditingChanged(false)
                    dragging = false
                })
        }.frame(height: 18)
            .accessibilityRepresentation {
                Slider(value: Binding(get: { value }, set: { newValue in
                    onEditingChanged(true); value = newValue; onEditingChanged(false)
                }), in: 0...max(1, upperBound)).accessibilityLabel(label)
            }
    }
}

struct IslandView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var music: MusicModel
    @ObservedObject var island: IslandState
    @ObservedObject var stats: SystemStatsModel
    private var showingStats: Bool {
        return IslandPane.selected(playing: music.playing, playerRunning: music.isMusicRunning, hasTrack: music.hasCurrentTrack, requested: island.requestedPane) == .stats
    }
    private var musicPageMix: Double { showingStats ? 0 : 1 }
    private func selectPage(_ pane: IslandPane) {
        withAnimation(.easeOut(duration: reduceMotion ? 0.12 : 0.20)) {
            island.requestedPane = pane
        }
    }
    // Keep a real rolling history across panes and between hovers. These
    // inexpensive kernel reads do not require the card or Activity Monitor open.
    private func updateSampling() { stats.setSamplingEnabled(island.panelVisible) }
    @State private var seekDraft = 0.0
    @State private var seeking = false
    private let accent = Color(red: 1, green: 0.22, blue: 0.36)
    private var artworkTint: Color {
        Color(red: music.artworkAccent.red, green: music.artworkAccent.green, blue: music.artworkAccent.blue)
    }
    private var lightArtworkTint: Color {
        Color(red: music.artworkAccent.red * 0.55 + 0.45,
              green: music.artworkAccent.green * 0.55 + 0.45,
              blue: music.artworkAccent.blue * 0.55 + 0.45)
    }
    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: island.safeTop > 0 ? 0 : 20,
                               bottomLeadingRadius: island.expanded ? 27 : 10,
                               bottomTrailingRadius: island.expanded ? 27 : 10,
                               topTrailingRadius: island.safeTop > 0 ? 0 : 20)
    }
    private var expandedHeight: CGFloat { island.safeTop > 0 ? island.safeTop + 232 : 246 }
    var body: some View {
        ZStack(alignment: .top) {
            shape.fill(.black.opacity(island.expanded && IslandGlassChrome.isSupported ? 0 : 1))
            VStack(spacing: 0) {
                Color.clear.frame(height: island.safeTop)
                ZStack {
                    Color(white: 0.14)
                    ZStack {
                        LinearGradient(colors: [artworkTint, artworkTint.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        if let backdrop = music.artworkBackdrop {
                            Image(nsImage: backdrop).resizable().interpolation(.high).scaledToFill()
                        }
                    }.opacity(musicPageMix)
                }
                .frame(width: 386, height: expandedHeight - island.safeTop).clipped()
                .overlay(LinearGradient(colors: [.black.opacity(0.32), .black.opacity(0.52)], startPoint: .top, endPoint: .bottom))
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .white, location: 0.13), .init(color: .white, location: 1)], startPoint: .top, endPoint: .bottom))
            }.frame(width: 386, height: expandedHeight, alignment: .top)
                .opacity(IslandGlassChrome.isSupported ? 0.32 : 1)
                .mask {
                    if IslandGlassChrome.isSupported {
                        // Fade the album backing away at the corners so the actual
                        // desktop behind the glass remains visible there.
                        RadialGradient(colors: [.white, .white.opacity(0.65), .clear],
                                       center: .center, startRadius: 40, endRadius: 235)
                    } else {
                        Color.white
                    }
                }
                .opacity(island.expanded ? 1 : 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            if IslandGlassChrome.isSupported {
                // Quiet center for text; leave the perimeter open to the native material.
                RadialGradient(colors: [.black.opacity(0.75), .black.opacity(0.40), .clear],
                               center: .center, startRadius: 30, endRadius: 240)
                    .opacity(island.expanded ? 1 : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                LinearGradient(stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: island.safeTop / expandedHeight),
                    .init(color: .clear, location: min(1, (island.safeTop + 45) / expandedHeight))
                ], startPoint: .top, endPoint: .bottom)
                    .opacity(island.expanded && island.safeTop > 0 ? 1 : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            // Keep content laid out at its final size; reveal it through the animated mask.
            expanded.padding(.horizontal, 22).padding(.top, island.safeTop > 0 ? island.safeTop + 13 : 17)
                .frame(width: 386, alignment: .top)
                .opacity(island.expanded ? 1 : 0)
                .offset(y: island.expanded ? 0 : -5)
                .animation(.easeOut(duration: island.expanded ? 0.18 : 0.08).delay(island.expanded ? 0.09 : 0), value: island.expanded)
                .allowsHitTesting(island.expanded)
                .accessibilityHidden(!island.expanded)
            Button { island.togglePin() } label: {
                HStack(spacing: 10) {
                    ArtView(image: music.artwork, size: 22)
                    if island.safeTop == 0 {
                        Text(music.status == "track" ? music.title : "FLYnamic Island").font(.system(size: 12, weight: .medium)).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    PlaybackBars(
                        playing: music.playing && music.hasCurrentTrack && island.panelVisible && !island.expanded,
                        color: artworkTint
                    )
                }.padding(.horizontal, 12)
                    .frame(width: island.collapsedWidth, height: island.safeTop > 0 ? island.safeTop : 40)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityLabel(music.hasCurrentTrack ? "Open music controls. \(music.title). \(music.playing ? "Playing" : "Paused")" : "Show system statistics")
                .opacity(!island.expanded && music.hasCurrentTrack ? 1 : 0)
                .animation(.easeOut(duration: 0.12).delay(island.expanded ? 0 : 0.16), value: island.expanded)
                .allowsHitTesting(!island.expanded)
                .accessibilityHidden(island.expanded)
        }
        .frame(width: island.expanded ? 386 : island.collapsedWidth,
               height: island.expanded ? expandedHeight : (island.safeTop > 0 ? island.safeTop : 40), alignment: .top)
        .foregroundStyle(.white)
        .modifier(IslandGlassChrome(expanded: island.expanded, shape: shape))
        .clipShape(shape)
        .frame(width: 386, height: expandedHeight, alignment: .top)
        .animation(.easeInOut(duration: 0.45), value: music.artworkAccent)
        .onChange(of: island.showingAirPlay) { _, showing in
            if !showing && !island.pinned && !island.pointerIsInside() { island.hover(false) }
        }
        .onAppear { updateSampling() }
        .onChange(of: island.expanded) { _, expanded in
            if !expanded { island.requestedPane = nil }
            updateSampling()
        }
        .onChange(of: island.panelVisible) { _, _ in updateSampling() }
        .onChange(of: showingStats) { _, _ in updateSampling() }
        .onChange(of: music.playing) { _, _ in updateSampling() }
        .onChange(of: music.hasCurrentTrack) { _, _ in island.setExpanded?(island.expanded) }
        .onDisappear { stats.setSamplingEnabled(false) }
        .accessibilityAction(named: Text("Show system stats")) { selectPage(.stats) }
        .accessibilityAction(named: Text("Show music controls")) {
            if music.isMusicRunning { selectPage(.music) }
        }
        .preferredColorScheme(.dark)
    }
    @ViewBuilder var expanded: some View {
        VStack(spacing: 9) {
            HStack {
                if showingStats {
                    Text("System").font(.system(size: 14, weight: .semibold))
                }
                Spacer()
                if music.isMusicRunning {
                    HStack(spacing: 5) {
                        Circle().fill(.white.opacity(0.8 - musicPageMix * 0.6))
                        Circle().fill(.white.opacity(0.2 + musicPageMix * 0.6))
                    }.frame(width: 13, height: 4).padding(.trailing, 8)
                        .help("Swipe left with two fingers for Music; swipe right for Stats.")
                        .accessibilityLabel(showingStats ? "Page 1 of 2, System statistics" : "Page 2 of 2, Music")
                }
                Button { island.togglePin() } label: {
                    Image(systemName: island.pinned ? "pin.fill" : "pin")
                        .font(.system(size: 12)).foregroundStyle(island.pinned ? .white : .white.opacity(0.45))
                        .frame(width: 24, height: 24)
                }.buttonStyle(.plain).help(island.pinned ? "Unpin island" : "Keep expanded")
                    .accessibilityLabel(island.pinned ? "Unpin island" : "Keep expanded")
            }.frame(height: 25)
            ZStack(alignment: .topLeading) {
                SystemStatsView(stats: stats)
                    .frame(width: 342, height: 177, alignment: .top)
                    .offset(x: reduceMotion || showingStats ? 0 : -18)
                    .opacity(showingStats ? 1 : 0)
                    .allowsHitTesting(showingStats)
                    .accessibilityHidden(!showingStats)
                musicContents
                    .frame(width: 342, height: 177, alignment: .top)
                    .offset(x: reduceMotion || !showingStats ? 0 : 18)
                    .opacity(musicPageMix)
                    .allowsHitTesting(!showingStats)
                    .accessibilityHidden(showingStats)
            }.frame(width: 342, height: 177, alignment: .topLeading).clipped()
        }
    }
    @ViewBuilder var musicContents: some View {
        if music.status == "track" {
            VStack(spacing: 8) {
                HStack(spacing: 13) {
                    Button { music.openMusic() } label: {
                        HStack(spacing: 13) {
                            ArtView(image: music.artwork, size: 43)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(music.title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                                Text(music.artist.isEmpty ? music.source.title : music.artist).font(.system(size: 12)).foregroundStyle(.white.opacity(0.78)).lineLimit(1)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .help("Open in \(music.source.title)")
                        .accessibilityLabel("Open \(music.title) in \(music.source.title)")
                    if music.source == .appleMusic {
                    Button { music.toggleFavorite() } label: {
                        ZStack {
                            if music.updatingFavorite { ProgressView().controlSize(.mini) }
                            else { Image(systemName: music.favorited ? "star.fill" : "star") }
                        }
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(music.favorited ? lightArtworkTint : .white.opacity(0.65))
                            .frame(width: 28, height: 30)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .disabled(music.busy || music.updatingFavorite || !music.favoriteAvailable)
                        .help(music.favoriteAvailable ? (music.favorited ? "Remove from Favorites" : "Add to Favorites") : "Favorites unavailable for this song")
                        .accessibilityLabel(music.favorited ? "Remove from Favorites" : "Add to Favorites")
                        .accessibilityValue(music.updatingFavorite ? "Saving in Apple Music" : (music.favorited ? "Favorited" : "Not favorited"))
                    }
                }
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !music.playing || !island.expanded || showingStats)) { _ in
                    let livePosition = music.currentPosition()
                    let session = music.sessionGeneration
                    VStack(spacing: 0) {
                    MusicScrubber(value: Binding(get: { seeking ? seekDraft : livePosition }, set: {
                        if music.sessionGeneration == session { seekDraft = $0 }
                    }), upperBound: music.duration, tint: lightArtworkTint, label: "Track position", expandsOnDrag: true, onEditingChanged: { editing in
                        guard music.sessionGeneration == session else { return }
                        seeking = editing
                        if !editing { music.command("seek", value: seekDraft) }
                    }).disabled(music.duration <= 0)
                        .id(session)
                    HStack {
                        Text(IslandLogic.seconds(seeking ? seekDraft : livePosition))
                        Spacer()
                        Text("−" + IslandLogic.seconds(max(0, music.duration - (seeking ? seekDraft : livePosition))))
                    }.font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(.white.opacity(0.65))
                    }
                }
                .onChange(of: music.sessionGeneration) { _, _ in seeking = false }
                ZStack {
                    HStack(spacing: 20) {
                        CircleControl(symbol: "backward.fill", label: "Previous track") { music.command("previous") }
                            .disabled(music.busy)
                        CircleControl(symbol: music.playing ? "pause.fill" : "play.fill", label: music.playing ? "Pause" : "Play", prominent: true) { music.command("playpause") }
                        CircleControl(symbol: "forward.fill", label: "Next track") { music.command("next") }
                            .disabled(music.busy)
                    }
                    HStack {
                        Button { music.toggleShuffle() } label: {
                            Image(systemName: "shuffle")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(music.shuffleEnabled ? lightArtworkTint : .white.opacity(0.55))
                                .frame(width: 30, height: 40)
                                .background(music.shuffleEnabled ? lightArtworkTint.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 9))
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .disabled(!music.shuffleAvailable || music.updatingShuffle)
                            .help(music.shuffleEnabled ? "Turn shuffle off" : "Turn shuffle on")
                            .accessibilityLabel("Shuffle")
                            .accessibilityValue(music.shuffleEnabled ? "On" : "Off")
                        Spacer()
                        Button {
                            island.collapseWork?.cancel(); island.showingAirPlay = true
                            music.loadAirPlayOutputs()
                        } label: {
                            Image(systemName: "airplay.audio").font(.system(size: 20)).foregroundStyle(.white.opacity(0.55)).frame(width: 28, height: 40)
                        }.buttonStyle(.plain).help("Sound output").accessibilityLabel("Sound output")
                            .disabled(music.source == .youtubeMusic)
                            .popover(isPresented: $island.showingAirPlay, arrowEdge: .top) { AirPlayPicker(music: music) }
                    }
                }
                HStack(spacing: 9) {
                    Image(systemName: "speaker.fill").font(.system(size: 10))
                    let session = music.sessionGeneration
                    MusicScrubber(value: Binding(get: { music.volume }, set: { value in
                        if music.sessionGeneration == session { music.setVolume(value) }
                    }), upperBound: 100, tint: .white.opacity(0.55), label: "Music volume")
                    .id(session)
                    Image(systemName: "speaker.wave.3.fill").font(.system(size: 10))
                }.foregroundStyle(.white.opacity(0.35))
                if !music.message.isEmpty { Text(music.message).font(.system(size: 9)).foregroundStyle(.orange) }
            }
        } else {
            VStack(spacing: 12) {
                HStack {
                    ArtView(image: nil, size: 43)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("FLYnamic Island").font(.system(size: 16, weight: .semibold))
                        Text("Your music, a little closer.").font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                    }
                    Spacer()
                }
                Text(emptyMessage).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(emptyAction) {
                        if music.status == "permission" { music.connect() }
                        else if ["denied", "permission-pending"].contains(music.status) { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!) }
                        else if music.status == "connection-error" { music.connect(request: false) }
                        else if music.status == "error" { music.refresh() }
                        else { music.openMusic() }
                    }.buttonStyle(.borderedProminent).tint(accent).disabled(music.busy)
                    Spacer()
                    Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.4))
                }
            }.padding(.top, 4)
        }
    }
    var emptyMessage: String {
        switch music.status {
        case "permission": return "Allow FLYnamic Island to control \(music.source.title) to show your song and playback controls."
        case "permission-wait": return "Waiting for macOS to ask permission. Click Allow in the control \(music.source.title) prompt."
        case "permission-pending": return "macOS hasn’t finished the permission request. Check for an Allow prompt behind other windows. If none appears, quit and reopen FLYnamic Island."
        case "connection-error": return "Couldn’t check \(music.source.title)’s connection. You can retry or reopen FLYnamic Island."
        case "denied": return "Allow FLYnamic Island to control \(music.source.title) in System Settings → Privacy & Security → Automation."
        case "closed": return "Open Spotify or Apple Music and choose a song."
        case "idle": return "Choose a song in \(music.source.title) to get started."
        case "error": return "\(music.source.title) isn’t responding. You can retry or reopen it."
        default: return "Connecting to \(music.source.title)…"
        }
    }
    var emptyAction: String {
        switch music.status {
        case "permission": return "Connect \(music.source.title)"
        case "permission-wait": return "Waiting for approval…"
        case "denied", "permission-pending": return "Open Settings"
        case "error", "connection-error": return "Retry"
        default: return "Open \(music.source.title)"
        }
    }
}

final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation {
    private static let menuBarIcon: NSImage = {
        let image = NSImage(size: NSSize(width: 22, height: 18), flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.setFillColor(NSColor.black.cgColor)
            let pill = CGRect(x: 2, y: 6, width: 15.5, height: 6)
            context.addPath(CGPath(roundedRect: pill, cornerWidth: 3, cornerHeight: 3, transform: nil))
            context.fillPath()

            func drawSparkle(x: CGFloat, y: CGFloat, radius: CGFloat) {
                let waist = radius * 0.28
                context.addLines(between: [
                    CGPoint(x: x, y: y + radius), CGPoint(x: x + waist, y: y + waist),
                    CGPoint(x: x + radius, y: y), CGPoint(x: x + waist, y: y - waist),
                    CGPoint(x: x, y: y - radius), CGPoint(x: x - waist, y: y - waist),
                    CGPoint(x: x - radius, y: y), CGPoint(x: x - waist, y: y + waist)
                ])
                context.closePath()
                context.fillPath()
            }

            drawSparkle(x: 18.5, y: 14.3, radius: 2.7)
            drawSparkle(x: 4, y: 3, radius: 1.55)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Flynamic Island"
        return image
    }()

    let music = MusicModel()
    let island = IslandState()
    let stats = SystemStatsModel()
    var panel: IslandPanel!
    var item: NSStatusItem!
    var screen: NSScreen { NSScreen.screens.first ?? NSScreen.main! }
    var visibility = IslandVisibility()
    var hidden: Bool { !visibility.isVisible }
    var pointerTimer: Timer?
    var hoverTracker = HoverTracker()
    var swipeTracker = IslandSwipeTracker()
    var scrollMonitor: Any?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        panel = IslandPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.canBecomeVisibleWithoutLogin = false
        panel.title = "FLYnamic Island"
        panel.identifier = NSUserInterfaceItemIdentifier("MusicIsland")
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.contentView = NSHostingView(rootView: IslandView(music: music, island: island, stats: stats))
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            return self.handleIslandScroll(event)
        }
        island.setExpanded = { [weak self] expanded in self?.resize(expanded) }
        island.pointerIsInside = { [weak self] in self?.hoverTracker.isInside ?? false }
        island.pinned = UserDefaults.standard.bool(forKey: "keepExpanded")
        resize(island.pinned, animate: false)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = Self.menuBarIcon
        let menu = NSMenu()
        menu.addItem(withTitle: "Show / hide island", action: #selector(toggleVisibility), keyEquivalent: "")
        menu.addItem(withTitle: "Keep expanded", action: #selector(togglePin), keyEquivalent: "")
        menu.addItem(withTitle: "Open player", action: #selector(openMusic), keyEquivalent: "")
        let player = NSMenuItem(title: "Player", action: nil, keyEquivalent: "")
        player.submenu = NSMenu(title: "Player")
        menu.addItem(player)
        menu.addItem(withTitle: "Enable YouTube Music…", action: #selector(setupYouTubeMusic), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit FLYnamic Island", action: #selector(quit), keyEquivalent: "q")
        for entry in menu.items { entry.target = self }
        item.menu = menu
        menu.delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(displayChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.trackPointer() }
        timer.tolerance = 0.003
        RunLoop.main.add(timer, forMode: .common)
        pointerTimer = timer
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(musicApplicationChanged(_:)), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        workspace.addObserver(self, selector: #selector(musicApplicationChanged(_:)), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        music.visibilityChanged = { [weak self] _ in
            self?.island.requestedPane = nil
            self?.island.showingAirPlay = false
            self?.applyVisibility()
        }
        music.playbackActivityChanged = { [weak self] _ in
            guard let self else { return }
            self.island.showingAirPlay = false
            self.resize(self.island.expanded, animate: false)
        }
        let distributed = DistributedNotificationCenter.default()
        for name in ["com.spotify.client.PlaybackStateChanged", "com.apple.Music.playerInfo"] {
            distributed.addObserver(self, selector: #selector(playerInfoChanged(_:)), name: Notification.Name(name), object: nil)
        }
        applyVisibility()
        music.start()
    }
    func resize(_ expanded: Bool, animate: Bool = true) {
        guard panel != nil else { return }
        if !expanded { swipeTracker.reset() }
        let s = screen
        island.safeTop = s.safeAreaInsets.top
        let notchWidth = (s.auxiliaryTopRightArea?.minX ?? s.frame.midX) - (s.auxiliaryTopLeftArea?.maxX ?? s.frame.midX)
        let compact = IslandLogic.panelFrame(screen: s.frame, topInset: island.safeTop, notchWidth: notchWidth, expanded: false)
        let host = IslandLogic.panelFrame(screen: s.frame, topInset: island.safeTop, notchWidth: notchWidth, expanded: true)
        island.collapsedWidth = music.hasCurrentTrack ? compact.width : (island.safeTop > 0 ? max(120, notchWidth) : 230)
        panel.ignoresMouseEvents = !expanded
        // Window geometry never animates. A single SwiftUI spring animates the visible mask.
        if panel.frame != host { panel.setFrame(host, display: true) }
        if animate && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            withAnimation(.spring(response: 0.36, dampingFraction: 0.92)) { island.expanded = expanded }
        } else { island.expanded = expanded }
    }
    func trackPointer() {
        guard !hidden, panel != nil else { return }
        let s = screen
        let compact = CGRect(x: s.frame.midX - island.collapsedWidth / 2,
                             y: panel.frame.maxY - (island.safeTop > 0 ? island.safeTop : 40),
                             width: island.collapsedWidth, height: island.safeTop > 0 ? island.safeTop : 40)
        if let entered = hoverTracker.update(pointer: NSEvent.mouseLocation, collapsed: compact, expanded: panel.frame, isExpanded: island.expanded) {
            island.hover(entered)
        }
    }
    func handleIslandScroll(_ event: NSEvent) -> NSEvent? {
        guard event.window === panel, island.expanded, island.panelVisible,
              music.isMusicRunning, !island.showingAirPlay else {
            swipeTracker.reset()
            return event
        }
        // Only direct, phase-bearing trackpad scrolling changes pages. Mouse
        // wheels, vertical scrolling, and inertia never trigger extra switches.
        guard event.hasPreciseScrollingDeltas, event.momentumPhase.isEmpty else { return event }
        let phase: IslandSwipeTracker.Phase
        if event.phase.contains(.began) { phase = .began }
        else if event.phase.contains(.cancelled) { phase = .cancelled }
        else if event.phase.contains(.ended) { phase = .ended }
        else if event.phase.contains(.changed) { phase = .changed }
        else { return event }
        let wasClaimed = swipeTracker.claimed
        let naturalSign = event.isDirectionInvertedFromDevice ? 1.0 : -1.0
        let direction = swipeTracker.update(x: event.scrollingDeltaX * naturalSign,
                                            y: event.scrollingDeltaY, phase: phase)
        if let direction {
            let duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.12 : 0.20
            withAnimation(.easeOut(duration: duration)) {
                island.requestedPane = direction == .left ? .music : .stats
            }
        }
        return wasClaimed || swipeTracker.claimed || direction != nil ? nil : event
    }
    @objc func toggleVisibility() {
        visibility.toggleManualVisibility()
        applyVisibility()
    }
    @objc func musicApplicationChanged(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              MediaSource.allCases.contains(where: { $0.bundleIdentifier == app.bundleIdentifier }) else { return }
        music.refreshPlayers(excludingPID: notification.name == NSWorkspace.didTerminateApplicationNotification ? app.processIdentifier : nil)
    }
    @objc func playerInfoChanged(_ notification: Notification) {
        guard let state = notification.userInfo?["Player State"] as? String else { return }
        let source: MediaSource = notification.name.rawValue.hasPrefix("com.spotify") ? .spotify : .appleMusic
        music.playerNotification(source: source, playing: state.lowercased() == "playing")
    }
    func applyVisibility() {
        guard panel != nil else { return }
        if visibility.isVisible {
            island.panelVisible = true
            if !panel.isVisible { resize(island.pinned, animate: false) }
            pointerTimer?.fireDate = Date()
            panel.orderFrontRegardless()
        } else {
            island.panelVisible = false
            island.collapseWork?.cancel()
            island.showingAirPlay = false
            hoverTracker = HoverTracker()
            pointerTimer?.fireDate = .distantFuture
            stats.setSamplingEnabled(false)
            resize(false, animate: false)
            panel.orderOut(nil)
        }
    }
    @objc func togglePin() {
        island.togglePin()
        UserDefaults.standard.set(island.pinned, forKey: "keepExpanded")
        if !island.pinned { resize(false) }
    }
    @objc func openMusic() { music.openMusic() }
    @objc private func choosePlayer(_ item: NSMenuItem) {
        music.choosePlayer((item.representedObject as? String).flatMap(MediaSource.init(rawValue:)))
    }
    @objc private func disableYouTubeMusic() { music.setYouTubeEnabled(false) }
    @objc private func setupYouTubeMusic() { music.setupYouTubeMusic() }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if let submenu = menu.item(withTitle: "Player")?.submenu {
            submenu.removeAllItems()
            let automatic = submenu.addItem(withTitle: "Automatic", action: #selector(choosePlayer(_:)), keyEquivalent: "")
            automatic.target = self
            automatic.state = music.preferredSource == nil ? .on : .off
            for source in MediaSource.allCases where music.availableSources.contains(source) {
                let player = submenu.addItem(withTitle: source.title, action: #selector(choosePlayer(_:)), keyEquivalent: "")
                player.target = self
                player.representedObject = source.rawValue
                player.state = music.preferredSource == source ? .on : .off
            }
            if music.youtubeEnabled {
                submenu.addItem(.separator())
                let disable = submenu.addItem(withTitle: "Disable YouTube Music", action: #selector(disableYouTubeMusic), keyEquivalent: "")
                disable.target = self
            }
        }
        if let setup = menu.items.first(where: { $0.action == #selector(setupYouTubeMusic) }) {
            let title: String
            switch (music.youtubeEnabled, music.chromeStatus) {
            case (false, _): title = "Enable YouTube Music…"
            case (true, "track"): title = "YouTube Music connected"
            case (true, "closed"): title = "Open YouTube Music in Chrome"
            case (true, "idle"): title = "Open a song in YouTube Music"
            case (true, "permission"): title = "Allow Chrome Automation…"
            case (true, "denied"), (true, "permission-pending"): title = "Open Chrome Automation Settings…"
            case (true, "permission-wait"): title = "Waiting for Chrome permission…"
            case (true, "chrome-setting"): title = "Chrome needs JavaScript from Apple Events"
            case (true, "connecting"): title = "Connecting to YouTube Music…"
            default: title = "Retry YouTube Music connection"
            }
            setup.title = title
        }
        for entry in menu.items where entry.action == #selector(toggleVisibility) || entry.action == #selector(togglePin) {
            entry.isEnabled = true
        }
    }
    @objc func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard item.action == #selector(setupYouTubeMusic), music.youtubeEnabled else { return true }
        return !["track", "chrome-setting", "connecting", "permission-wait"].contains(music.chromeStatus)
    }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        stats.setSamplingEnabled(false)
    }
    @objc func displayChanged() { resize(island.expanded, animate: false) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
enum MusicIslandMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
