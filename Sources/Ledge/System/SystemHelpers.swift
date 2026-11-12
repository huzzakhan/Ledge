import AppKit
import EventKit
import ServiceManagement

// MARK: - AppleScript

enum AppleScript {
    private static var cache: [String: NSAppleScript] = [:]

    /// Runs an AppleScript. Static scripts are compiled once and cached.
    @discardableResult
    static func run(_ source: String, cache useCache: Bool = true) -> NSAppleEventDescriptor? {
        let script: NSAppleScript
        if useCache, let cached = cache[source] {
            script = cached
        } else {
            guard let s = NSAppleScript(source: source) else { return nil }
            if useCache { cache[source] = s }
            script = s
        }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        return error == nil ? result : nil
    }
}

// MARK: - URLs / System Settings

enum SystemLinks {
    static func open(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }

    /// e.g. "Privacy_Reminders", "Privacy_Calendars", "Privacy_Automation", "Privacy_LocationServices"
    static func privacy(_ anchor: String) {
        open("x-apple.systempreferences:com.apple.preference.security?\(anchor)")
    }
}

// MARK: - Bluetooth (uses the same IOBluetooth calls as the popular `blueutil` tool)

enum Bluetooth {
    private typealias GetFn = @convention(c) () -> Int32
    private typealias SetFn = @convention(c) (Int32) -> Int32
    private static let handle = dlopen("/System/Library/Frameworks/IOBluetooth.framework/IOBluetooth", RTLD_LAZY)

    static func isOn() -> Bool? {
        guard let h = handle, let sym = dlsym(h, "IOBluetoothPreferenceGetControllerPowerState") else { return nil }
        return unsafeBitCast(sym, to: GetFn.self)() != 0
    }

    @discardableResult
    static func setOn(_ on: Bool) -> Bool {
        guard let h = handle, let sym = dlsym(h, "IOBluetoothPreferenceSetControllerPowerState") else { return false }
        _ = unsafeBitCast(sym, to: SetFn.self)(on ? 1 : 0)
        return true
    }
}

// MARK: - Built-in display brightness

enum DisplayBrightness {
    private typealias GetFn = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (UInt32, Float) -> Int32
    private static let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)

    static func get() -> Double? {
        guard let h = handle, let sym = dlsym(h, "DisplayServicesGetBrightness") else { return nil }
        var value: Float = 0
        let result = unsafeBitCast(sym, to: GetFn.self)(CGMainDisplayID(), &value)
        return result == 0 ? Double(value) : nil
    }

    static func set(_ value: Double) {
        guard let h = handle, let sym = dlsym(h, "DisplayServicesSetBrightness") else { return }
        _ = unsafeBitCast(sym, to: SetFn.self)(CGMainDisplayID(), Float(min(max(value, 0), 1)))
    }
}

// MARK: - macOS Dock

enum SystemDock {
    static var isAutohide: Bool {
        UserDefaults(suiteName: "com.apple.dock")?.bool(forKey: "autohide") ?? false
    }

    static func setAutohide(_ on: Bool) {
        AppleScript.run("tell application \"System Events\" to set autohide of dock preferences to \(on)", cache: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            NotificationCenter.default.post(name: .ledgeReposition, object: nil)
        }
    }
}

// MARK: - Launch at login

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Ledge: launch at login change failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - EventKit (Reminders + Calendar)

enum EventKitHub {
    static let store = EKEventStore()

    static func hasAccess(_ type: EKEntityType) -> Bool {
        let status = EKEventStore.authorizationStatus(for: type)
        if #available(macOS 14.0, *) {
            return status == .fullAccess || status == .authorized
        }
        return status == .authorized
    }

    static func isUndetermined(_ type: EKEntityType) -> Bool {
        EKEventStore.authorizationStatus(for: type) == .notDetermined
    }

    static func request(_ type: EKEntityType, completion: @escaping (Bool) -> Void) {
        let done: (Bool, Error?) -> Void = { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
        if #available(macOS 14.0, *) {
            if type == .event {
                store.requestFullAccessToEvents(completion: done)
            } else {
                store.requestFullAccessToReminders(completion: done)
            }
        } else {
            store.requestAccess(to: type, completion: done)
        }
    }
}

// MARK: - Formatting

enum Fmt {
    static func mmss(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let t = Int(seconds)
        return String(format: "%d:%02d", t / 60, t % 60)
    }

    static func bytes(_ value: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .memory)
    }

    static func clamp01(_ v: Double) -> Double {
        guard v.isFinite else { return 0 }
        return min(max(v, 0), 1)
    }
}
