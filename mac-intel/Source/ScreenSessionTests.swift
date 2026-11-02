import AppKit

@main enum ScreenSessionTests {
    static func main() {
        let monitor = ScreenSessionMonitor()
        var observed: [ScreenSessionState] = []
        monitor.start { observed.append($0) }
        assert(observed.count == 1 && observed.first == ScreenSessionMonitor.currentState())
        monitor.stop()
        let stoppedCount = observed.count
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 2.3))
        assert(observed.count == stoppedCount)
        monitor.start { observed.append($0) }
        assert(observed.count == stoppedCount + 1)
        monitor.stop()
        print("Screen-session checks passed: live session read, initial callback, stopped monitor, and restart. No lock/unlock or authentication settings were changed.")
    }
}
