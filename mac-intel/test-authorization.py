from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
src = root / 'outputs/music-island/Source'
model = (src / 'App.swift').read_text().split('final class IslandState:')[0]
# Substitute only OS boundaries: deterministic processes and permission results.
start = model.index('        var pids: [MediaSource: pid_t] = [:]')
end = model.index('        let processChanged', start)
model = model[:start] + '        let pids = ConsentFixture.running\n' + model[end:]
assert model.count('let permission = bridge.permissionRequestingConsent(request)') == 1
model = model.replace('let permission = bridge.permissionRequestingConsent(request)', 'let permission = ConsentFixture.check(request)')
model = model.replace('            let bridge = MusicBridge(bundleIdentifier: selectedSource.bundleIdentifier)', '')
model = model.replace('        let selectedSource = source', '')
model = model.replace('            NSApp.activate(ignoringOtherApps: true)', '            // Do not activate an app during the isolated test.')
model = model.replace('.now() + 8)', '.now() + 0.08)')
fixture = r'''
import AppKit
import Foundation

enum ConsentFixture {
    static var running: [MediaSource: pid_t] = [.spotify: 12345]
    static let lock = NSLock()
    static var passiveResult = -1744
    static var requests = 0
    static let release = DispatchSemaphore(value: 0)
    static func check(_ request: Bool) -> Int {
        lock.lock()
        if request { requests += 1 }
        let result = passiveResult
        lock.unlock()
        if !request { return result }
        _ = release.wait(timeout: .now() + 3)
        return -1743
    }
    static func setResult(_ result: Int) { lock.lock(); passiveResult = result; lock.unlock() }
    static func count() -> Int { lock.lock(); defer { lock.unlock() }; return requests }
}
func wait(_ condition: () -> Bool) {
    let end = Date(timeIntervalSinceNow: 1.5)
    while !condition() && Date() < end { RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.005)) }
    precondition(condition(), "Timed out waiting for expected state")
}
@main enum AuthorizationTests {
    static func main() {
        let model = MusicModel()
        precondition(model.status == "closed" && !model.busy && ConsentFixture.count() == 0)
        model.start()
        wait { model.status == "permission" && !model.busy }
        precondition(ConsentFixture.count() == 0, "Startup must never display consent")
        model.connect()
        wait { ConsentFixture.count() == 1 }
        wait { model.status == "permission-pending" && !model.busy }
        // Consent is still blocked. The existing playback/output queue stays usable.
        model.loadAirPlayOutputs()
        wait { !model.airPlayLoading }
        model.connect()
        precondition(ConsentFixture.count() == 1, "Do not stack consent prompts after watchdog")
        model.refreshPlayers()
        wait { !model.busy }
        precondition(model.status == "permission-pending")
        ConsentFixture.setResult(-1743)
        ConsentFixture.release.signal()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.03))
        model.refreshPlayers()
        wait { model.status == "denied" && !model.busy }
        ConsentFixture.setResult(-1712)
        model.refreshPlayers()
        wait { model.status == "connection-error" && !model.busy }
        // Closing the player invalidates outstanding permission callbacks.
        ConsentFixture.setResult(-1744)
        model.refreshPlayers()
        wait { model.status == "permission" && !model.busy }
        model.connect()
        wait { ConsentFixture.count() == 2 }
        ConsentFixture.running = [:]
        model.refreshPlayers()
        precondition(model.status == "closed" && !model.busy)
        ConsentFixture.release.signal()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        precondition(model.status == "closed", "Old consent result must not revive a closed source")
        print("PASS: launch gating; no unsolicited consent; blocked consent timeout; playback queue responsive; no duplicate prompts; denial/timeout recovery; stale callback rejection")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='flynamic-auth-tests-') as tmp:
    tmp = Path(tmp)
    (tmp/'Model.swift').write_text(model)
    (tmp/'Tests.swift').write_text(fixture)
    build = root/'outputs/music-island/.build'
    args = ['xcrun','swiftc','-swift-version','5','-parse-as-library','-import-objc-header',str(src/'MusicBridge.h'),str(tmp/'Model.swift'),str(tmp/'Tests.swift')]
    args += [str(src/f) for f in ['IslandLogic.swift','ArtworkAccent.swift','AudioVisualization.swift','SpotifyArtwork.swift','AppleArtwork.swift']]
    args += [str(build/'MusicBridge.o'),str(build/'AudioMeter.o')]
    for fw in ['AppKit','SwiftUI','ScriptingBridge','Carbon','QuartzCore','CoreAudio']: args += ['-framework',fw]
    args += ['-o',str(tmp/'test')]
    subprocess.run(args,check=True)
    subprocess.run([str(tmp/'test')],check=True,timeout=12)
