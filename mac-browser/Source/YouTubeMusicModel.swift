import AppKit
import Combine
import ImageIO

final class YouTubeArtworkLoader: NSObject, URLSessionTaskDelegate {
    private var task: URLSessionDataTask?
    private var current = ""
    private var retry = Date.distantPast
    private var loading = false
    private let cache = NSCache<NSString, NSImage>()
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.urlCache = nil
        config.timeoutIntervalForRequest = 8
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    override init() { super.init(); cache.countLimit = 8 }
    static func allowedURL(_ value: String) -> URL? {
        guard let url = URL(string: value), url.scheme == "https", url.user == nil, url.password == nil,
              let host = url.host?.lowercased(),
              host == "i.ytimg.com" || host == "yt3.ggpht.com" || host == "lh3.googleusercontent.com" || host == "yt3.googleusercontent.com" else { return nil }
        return url
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.flatMap { Self.allowedURL($0.absoluteString) } == nil ? nil : request)
    }
    func cancel() { task?.cancel(); task = nil; current = ""; loading = false; retry = .distantPast }
    func load(_ value: String, completion: @escaping (NSImage) -> Void) {
        guard let url = Self.allowedURL(value) else {
            cancel(); return
        }
        if current != value { cancel(); current = value }
        if let image = cache.object(forKey: value as NSString) { completion(image); return }
        guard !loading, Date() >= retry else { return }
        loading = true
        task = session.dataTask(with: url) { [weak self] data, response, _ in
            var image: NSImage?
            if let response = response as? HTTPURLResponse, response.statusCode == 200,
               Self.allowedURL(response.url?.absoluteString ?? "") != nil,
               let data, data.count < 6 * 1024 * 1024,
               let source = CGImageSourceCreateWithData(data as CFData, nil),
               let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 320] as CFDictionary) {
                image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            }
            DispatchQueue.main.async {
                guard let self, self.current == value else { return }
                self.loading = false; self.task = nil; self.retry = Date().addingTimeInterval(10)
                if let image { self.cache.setObject(image, forKey: value as NSString); completion(image) }
            }
        }
        task?.resume()
    }
}

final class MusicModel: ObservableObject {
    let visualizer = AudioVisualization()
    let source = MediaSource.youtubeMusic
    @Published private(set) var isMusicRunning = false
    var visibilityChanged: ((Bool) -> Void)?
    var playbackActivityChanged: ((Bool) -> Void)?
    @Published var status = "connecting"
    var hasCurrentTrack: Bool { isMusicRunning && status == "track" }
    @Published var title = "FLYnamic YT Music"
    @Published var artist = ""
    @Published var album = ""
    @Published var artwork: NSImage?
    @Published var artworkAccent = ArtworkAccent.fallback
    @Published var artworkBackdrop: NSImage?
    @Published var playing = false { didSet {
        visualizer.update(playing: playing)
        if oldValue != playing { playbackActivityChanged?(playing) }
    } }
    @Published var favorited = false
    @Published var favoriteAvailable = false
    @Published var updatingFavorite = false
    @Published var shuffleEnabled = false
    @Published var shuffleAvailable = false
    @Published var updatingShuffle = false
    @Published var position = 0.0
    @Published var duration = 0.0
    @Published var volume = 50.0
    @Published var busy = false
    @Published var message = ""
    @Published var airPlayOutputs: [AirPlayOutput] = []
    @Published var airPlayLoading = false
    @Published var airPlayError = ""
    private let queue = DispatchQueue(label: "local.flynamic.yt-music", qos: .userInitiated)
    private let bridge = ChromeBridge()
    private let outputBridge = MusicBridge(bundleIdentifier: "com.apple.Music")
    private let loader = YouTubeArtworkLoader()
    private var timer: Timer?
    private var polling = false
    private var trackID = ""
    private var anchor = ProcessInfo.processInfo.systemUptime
    private var playbackSync = PlaybackSync()
    private var commandInFlight = false
    init() {
        visualizer.setSource("com.google.Chrome", title: "Chrome")
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.refresh() }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refresh()
    }
    func refreshPlayers(excludingPID: pid_t? = nil) { refresh() }
    func playerNotification(source: MediaSource, playing: Bool) {}
    func connect(request: Bool = true) {
        guard !busy else { return }
        busy = true
        queue.async {
            _ = self.bridge.permissionRequestingConsent(request)
            DispatchQueue.main.async { self.busy = false; self.refresh() }
        }
    }
    func refresh() {
        guard !polling else { return }
        polling = true
        let revision = playbackSync.revision
        queue.async {
            let snapshot = self.bridge.snapshot()
            DispatchQueue.main.async {
                self.polling = false
                let status = snapshot["status"] as? String ?? "error"
                let wasRunning = self.isMusicRunning
                self.isMusicRunning = status != "closed"
                if self.isMusicRunning != wasRunning { self.visibilityChanged?(self.isMusicRunning) }
                self.status = status
                guard status == "track" else {
                    self.trackID = ""; self.playbackSync.reset(); self.playing = false
                    self.artwork = nil; self.artworkBackdrop = nil; self.artworkAccent = .fallback
                    self.loader.cancel(); self.visualizer.musicClosed()
                    return
                }
                let id = snapshot["id"] as? String ?? ""
                let changed = id != self.trackID
                if changed {
                    self.trackID = id; self.message = ""; self.playbackSync.reset()
                    self.loader.cancel(); self.artwork = nil; self.artworkBackdrop = nil; self.artworkAccent = .fallback
                }
                self.title = snapshot["title"] as? String ?? "YouTube Music"
                self.artist = snapshot["artist"] as? String ?? ""
                self.album = snapshot["album"] as? String ?? ""
                self.duration = snapshot["duration"] as? Double ?? 0
                self.volume = snapshot["volume"] as? Double ?? 50
                self.shuffleEnabled = snapshot["shuffle"] as? Bool ?? false
                self.shuffleAvailable = snapshot["shuffleAvailable"] as? Bool ?? false
                let nativePlaying = snapshot["playing"] as? Bool ?? false
                let observation = self.playbackSync.observe(playing: nativePlaying,
                        revision: changed ? self.playbackSync.revision : revision, now: ProcessInfo.processInfo.systemUptime)
                switch observation {
                case .accepted, .timedOut:
                    self.position = snapshot["position"] as? Double ?? 0
                    self.anchor = ProcessInfo.processInfo.systemUptime
                    self.playing = nativePlaying
                    if observation == .timedOut { self.message = "YouTube Music hasn’t confirmed playback. Try again." }
                default: break
                }
                let art = snapshot["artworkURL"] as? String ?? ""
                self.loader.load(art) { [weak model = self] image in
                    guard let model, model.trackID == id, model.status == "track", model.artwork !== image else { return }
                    model.artwork = image
                    model.artworkAccent = ArtworkAccent.extract(from: image)
                    model.artworkBackdrop = ArtworkAccent.backdrop(from: image)
                }
            }
        }
    }
    func currentPosition() -> Double {
        IslandLogic.playhead(position: position, anchor: anchor, now: ProcessInfo.processInfo.systemUptime, playing: playing, duration: duration)
    }
    func refreshPlayback() { refresh() }
    func command(_ command: String, value: Double = 0) {
        guard status == "track" else { return }
        if command == "playpause" {
            position = currentPosition(); anchor = ProcessInfo.processInfo.systemUptime
            let previous = playing; playing.toggle()
            playbackSync.request(playing: playing, previous: previous)
            sendPlaybackIntent()
            return
        }
        guard !busy else { return }
        busy = true
        let id = trackID
        if command == "seek" { position = value; anchor = ProcessInfo.processInfo.systemUptime }
        queue.async {
            let success = self.bridge.performCommand(command, value: value, trackID: id)
            DispatchQueue.main.async {
                self.busy = false
                guard self.trackID == id else { return }
                if !success { self.message = "YouTube Music couldn’t complete that. Try again." }
                self.refresh()
            }
        }
    }
    private func sendPlaybackIntent() {
        guard !commandInFlight, let pending = playbackSync.pending else { return }
        commandInFlight = true
        let id = trackID
        queue.async {
            let success = self.bridge.performCommand(pending.desired ? "play" : "pause", value: 0, trackID: id)
            DispatchQueue.main.async {
                self.commandInFlight = false
                guard self.trackID == id else { return }
                if self.playbackSync.pending?.revision != pending.revision { self.sendPlaybackIntent() }
                else if success { self.playbackSync.sent(revision: pending.revision, now: ProcessInfo.processInfo.systemUptime) }
                else if let previous = self.playbackSync.failed(revision: pending.revision) {
                    self.playing = previous; self.message = "YouTube Music couldn’t change playback."
                }
                self.refresh()
            }
        }
    }
    func toggleShuffle() { command("shuffle", value: shuffleEnabled ? 0 : 1) }
    func toggleFavorite() {}
    func openMusic() {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") else { return }
        NSWorkspace.shared.open([URL(string: "https://music.youtube.com/")!], withApplicationAt: app,
                                configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }
    func loadAirPlayOutputs(clearError: Bool = true) {
        guard !airPlayLoading else { return }
        airPlayLoading = true
        queue.async {
            let snapshot = self.outputBridge.airPlayOutputs()
            DispatchQueue.main.async {
                self.airPlayLoading = false
                self.airPlayOutputs = (snapshot["outputs"] as? [[String: Any]] ?? []).compactMap {
                    guard let id = $0["id"] as? String, let name = $0["name"] as? String else { return nil }
                    return AirPlayOutput(id: id, name: name, selected: $0["selected"] as? Bool ?? false,
                        available: $0["available"] as? Bool ?? false, symbol: $0["symbol"] as? String ?? "hifispeaker")
                }
            }
        }
    }
    func selectAirPlayOutput(_ id: String) {
        queue.async {
            let success = self.outputBridge.selectAirPlayOutput(id)
            DispatchQueue.main.async {
                if !success { self.airPlayError = "Couldn’t switch outputs. Try Sound Settings." }
                self.loadAirPlayOutputs()
            }
        }
    }
    deinit { timer?.invalidate() }
}
