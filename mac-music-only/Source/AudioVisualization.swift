import AppKit
import Combine

final class AudioVisualization: ObservableObject {
    @Published var levels = [Double](repeating: 0, count: 4)
    @Published var status = "Waiting for playback"
    var enabled: Bool {
        UserDefaults.standard.object(forKey: "reactiveBarsEnabled") as? Bool ?? true
    }
    private let meter = IslandAudioMeter()
    private let queue = DispatchQueue(label: "local.music-island.audio", qos: .userInitiated)
    private var timer: Timer?
    private var pid: pid_t = 0
    private var playing = false
    private var started = false
    private var visible = true
    private var generation = 0
    private var bundleIdentifier = "com.apple.Music"
    private var sourceTitle = "Apple Music"
    func setSource(_ bundleIdentifier: String, title: String) {
        self.bundleIdentifier = bundleIdentifier; sourceTitle = title
    }
    init() {
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let values = self.playing && self.enabled && self.visible ? self.meter.levels().map(\.doubleValue) : [0, 0, 0, 0]
            if self.levels != values { self.levels = values }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
    func update(playing: Bool) {
        self.playing = playing
        timer?.fireDate = playing && enabled && visible ? Date() : .distantFuture
        meter.setPlaybackActive(playing && enabled && visible)
        if !playing { levels = [0, 0, 0, 0] }
        guard enabled, playing else { return }
        let newPID = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first?.processIdentifier ?? 0
        guard newPID != 0, newPID != pid else { return }
        pid = newPID
        status = "Connecting live audio"
        let attemptGeneration = generation
        let sourceBundle = bundleIdentifier
        queue.async {
            let code = self.meter.start(forProcess: newPID, bundleIdentifier: sourceBundle)
            DispatchQueue.main.async {
                guard self.generation == attemptGeneration, self.pid == newPID else { return }
                self.started = code == 0
                self.status = code == 0 ? "Live \(self.sourceTitle) audio" : "Live audio unavailable (\(code))"
                self.meter.setPlaybackActive(self.playing && self.enabled && self.visible)
            }
        }
    }
    func setVisible(_ visible: Bool) {
        self.visible = visible
        timer?.fireDate = playing && enabled && visible ? Date() : .distantFuture
        meter.setPlaybackActive(playing && enabled && visible)
        if !visible { levels = [0, 0, 0, 0] }
    }
    func musicClosed() {
        generation += 1
        playing = false; pid = 0; started = false
        timer?.fireDate = .distantFuture
        meter.setPlaybackActive(false)
        levels = [0, 0, 0, 0]; status = "Waiting for playback"
        queue.async { self.meter.stop() }
    }
    func toggle() {
        UserDefaults.standard.set(!enabled, forKey: "reactiveBarsEnabled")
        if !enabled {
            meter.setPlaybackActive(false); levels = [0, 0, 0, 0]
            queue.async { self.meter.stop() }
            pid = 0; started = false; status = "Live bars off"
        } else { pid = 0; update(playing: playing) }
    }
}
