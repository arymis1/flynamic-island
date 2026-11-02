// SkyLight API declarations adapted from SkyLightWindow, Copyright (c) 2025
// Lakr Aream, MIT. See Resources/SkyLightWindow-LICENSE.txt.
import AppKit
import Darwin

// Owns a dedicated overlay space, never the user's desktop/login space. Every
// symbol is optional; an unsupported OS leaves the regular island untouched.
final class LockScreenSpace {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias Create = @convention(c) (Int32, Int32, Int32) -> UInt64
    private typealias Destroy = @convention(c) (Int32, UInt64) -> Int32
    private typealias SetLevel = @convention(c) (Int32, UInt64, Int32) -> Int32
    private typealias Visibility = @convention(c) (Int32, CFArray) -> Int32
    private typealias Attach = @convention(c) (Int32, UInt64, CFArray, Int32) -> Int32
    private let handle: UnsafeMutableRawPointer
    private let connection: Int32
    private let space: UInt64
    private let destroy: Destroy
    private let show: Visibility
    private let hide: Visibility
    private let attach: Attach
    private(set) var lastError: Int32?

    init?() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_LAZY) else { return nil }
        guard let mainSymbol = dlsym(handle, "SLSMainConnectionID"),
              let createSymbol = dlsym(handle, "SLSSpaceCreate"),
              let destroySymbol = dlsym(handle, "SLSSpaceDestroy"),
              let levelSymbol = dlsym(handle, "SLSSpaceSetAbsoluteLevel"),
              let showSymbol = dlsym(handle, "SLSShowSpaces"),
              let hideSymbol = dlsym(handle, "SLSHideSpaces"),
              let attachSymbol = dlsym(handle, "SLSSpaceAddWindowsAndRemoveFromSpaces") else {
            dlclose(handle); return nil
        }
        let main = unsafeBitCast(mainSymbol, to: MainConnection.self)
        let create = unsafeBitCast(createSymbol, to: Create.self)
        let destroy = unsafeBitCast(destroySymbol, to: Destroy.self)
        let setLevel = unsafeBitCast(levelSymbol, to: SetLevel.self)
        let connection = main()
        let space = create(connection, 1, 0)
        guard space > 0 else { dlclose(handle); return nil }
        // Notification overlays sit above the lock screen's own space (300).
        guard setLevel(connection, space, 400) == 0 else {
            _ = destroy(connection, space); dlclose(handle); return nil
        }
        self.handle = handle; self.connection = connection; self.space = space
        self.destroy = destroy
        show = unsafeBitCast(showSymbol, to: Visibility.self)
        hide = unsafeBitCast(hideSymbol, to: Visibility.self)
        attach = unsafeBitCast(attachSymbol, to: Attach.self)
    }
    func present(_ window: NSWindow) -> Bool {
        guard window.windowNumber > 0 else { lastError = -1; return false }
        let windows = [NSNumber(value: window.windowNumber)] as CFArray
        let attached = attach(connection, space, windows, 7)
        guard attached == 0 else { lastError = attached; return false }
        let shown = show(connection, [NSNumber(value: space)] as CFArray)
        lastError = shown == 0 ? nil : shown
        return shown == 0
    }
    deinit {
        _ = hide(connection, [NSNumber(value: space)] as CFArray)
        _ = destroy(connection, space)
        dlclose(handle)
    }
}
