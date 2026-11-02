import AppKit
import CoreGraphics

final class ScreenSessionMonitor {
    static func trace(_ event: String) {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any] ?? [:]
        let line = "\(Date()) \(event) console=\(String(describing: session[kCGSessionOnConsoleKey as String])) loggedIn=\(String(describing: session[kCGSessionLoginDoneKey as String])) locked=\(String(describing: session["CGSSessionScreenIsLocked"]))\n"
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("FLYnamic Island")
        let url = directory.appendingPathComponent("lock-screen-check.log")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = Data(line.utf8)
            if FileManager.default.fileExists(atPath: url.path), let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                if try handle.seekToEnd() < 32_768 { try handle.write(contentsOf: data) }
                else { try handle.truncate(atOffset: 0); try handle.write(contentsOf: data) }
            } else { try data.write(to: url) }
        } catch { /* Diagnostics must not affect window behavior. */ }
    }
    private var distributedObservers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var watchdog: Timer?
    private var lastState: ScreenSessionState?
    private var changed: ((ScreenSessionState) -> Void)?

    static func currentState() -> ScreenSessionState {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any],
              let onConsole = session[kCGSessionOnConsoleKey as String] as? Bool,
              let loggedIn = session[kCGSessionLoginDoneKey as String] as? Bool else { return .inactive }
        // This observed session key and the distributed lock notifications are
        // version-dependent. Missing/unknown state never elevates the panel.
        let locked = session["CGSSessionScreenIsLocked"] as? Bool ?? false
        return LockScreenPresentation.session(onConsole: onConsole, loggedIn: loggedIn, locked: locked)
    }
    func start(_ changed: @escaping (ScreenSessionState) -> Void) {
        stop()
        self.changed = changed
        let distributed = DistributedNotificationCenter.default()
        distributedObservers.append(distributed.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            Self.trace("lock notification")
            let current = Self.currentState()
            self?.publish(current == .inactive ? .inactive : .locked)
        })
        distributedObservers.append(distributed.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            Self.trace("unlock notification")
            self?.publish(Self.currentState())
        })
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.sessionDidBecomeActiveNotification, NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.screensDidWakeNotification] {
            workspaceObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Self.trace("workspace \(name.rawValue)")
                self?.publish(Self.currentState())
            })
        }
        // Restore the normal window level even if an unlock notification is
        // missed. Also handle launch while locked and switching user sessions.
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.publish(Self.currentState()) }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
        publish(Self.currentState())
    }
    private func publish(_ state: ScreenSessionState) {
        guard state != lastState else { return }
        Self.trace("state \(state)")
        lastState = state
        changed?(state)
    }
    func stop() {
        watchdog?.invalidate(); watchdog = nil
        for observer in distributedObservers { DistributedNotificationCenter.default().removeObserver(observer) }
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        distributedObservers = []; workspaceObservers = []
        changed = nil; lastState = nil
    }
    deinit { stop() }
}
