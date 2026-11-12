import SwiftUI
import AppKit
import CoreWLAN

final class ControlsStore: ObservableObject {
    static let shared = ControlsStore()

    @Published var wifiOn = false
    @Published var wifiName: String?
    @Published var bluetoothOn: Bool?
    @Published var darkMode = false
    @Published var volume: Double = 0.5
    @Published var muted = false
    @Published var brightness: Double?
    @Published var dockHidden = SystemDock.isAutohide

    private var timer: Timer?
    private var lastVolumeSet = Date.distantPast

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        let iface = CWWiFiClient.shared().interface()
        set(\.wifiOn, iface?.powerOn() ?? false)
        set(\.wifiName, iface?.ssid())
        set(\.bluetoothOn, Bluetooth.isOn())
        set(\.darkMode, NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
        set(\.dockHidden, SystemDock.isAutohide)
        set(\.brightness, DisplayBrightness.get())

        // Don't fight the slider while the user is dragging it.
        if Date().timeIntervalSince(lastVolumeSet) > 1.5 {
            if let v = AppleScript.run("output volume of (get volume settings)")?.int32Value {
                set(\.volume, Double(v) / 100)
            }
            if let m = AppleScript.run("output muted of (get volume settings)")?.booleanValue {
                set(\.muted, m)
            }
        }
    }

    /// Only publish when the value actually changed (avoids needless redraws).
    private func set<T: Equatable>(_ key: ReferenceWritableKeyPath<ControlsStore, T>, _ value: T) {
        if self[keyPath: key] != value { self[keyPath: key] = value }
    }

    // MARK: Actions

    func toggleWifi() {
        guard let iface = CWWiFiClient.shared().interface() else {
            SystemLinks.open("x-apple.systempreferences:com.apple.wifi-settings-extension")
            return
        }
        do {
            try iface.setPower(!wifiOn)
            wifiOn.toggle()
        } catch {
            SystemLinks.open("x-apple.systempreferences:com.apple.wifi-settings-extension")
        }
    }

    func toggleBluetooth() {
        let target = !(bluetoothOn ?? false)
        if Bluetooth.setOn(target) {
            bluetoothOn = target
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.refresh() }
        } else {
            SystemLinks.open("x-apple.systempreferences:com.apple.BluetoothSettings")
        }
    }

    func toggleDarkMode() {
        AppleScript.run("tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.refresh() }
    }

    func setVolume(_ v: Double) {
        volume = Fmt.clamp01(v)
        lastVolumeSet = Date()
        AppleScript.run("set volume output volume \(Int(volume * 100))", cache: false)
        if muted {
            AppleScript.run("set volume output muted false")
            muted = false
        }
    }

    func toggleMute() {
        lastVolumeSet = Date()
        AppleScript.run(muted ? "set volume output muted false" : "set volume output muted true")
        muted.toggle()
    }

    func setBrightness(_ v: Double) {
        brightness = Fmt.clamp01(v)
        DisplayBrightness.set(Fmt.clamp01(v))
    }

    func toggleSystemDock() {
        dockHidden.toggle()
        SystemDock.setAutohide(dockHidden)
    }

    func openFocus() {
        SystemLinks.open("x-apple.systempreferences:com.apple.Focus-Settings.extension")
    }

    func screenshot() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Screenshot.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
    }

    func airDrop() {
        let path = "/System/Library/CoreServices/Finder.app/Contents/Applications/AirDrop.app"
        if FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path),
                                               configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
        } else {
            SystemLinks.open("x-apple.systempreferences:com.apple.AirDrop-Handoff-Settings.extension")
        }
    }

    func sleepDisplay() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p.arguments = ["displaysleepnow"]
        try? p.run()
    }
}

// MARK: - Tile

struct ControlsTile: View {
    @ObservedObject var c = ControlsStore.shared
    @EnvironmentObject var state: DockState
    @Environment(\.palette) var p

    var body: some View {
        HStack(spacing: 7) {
            RoundToggle(symbol: "wifi", on: c.wifiOn) { c.toggleWifi() }
                .help(c.wifiOn ? "Wi-Fi: \(c.wifiName ?? "On")" : "Wi-Fi: Off")
            RoundToggle(symbol: "dot.radiowaves.left.and.right", on: c.bluetoothOn ?? false) { c.toggleBluetooth() }
                .help("Bluetooth")
            RoundToggle(symbol: "circle.lefthalf.filled", on: c.darkMode) { c.toggleDarkMode() }
                .help("Dark Mode")
            RoundToggle(symbol: c.muted ? "speaker.slash.fill" : "speaker.wave.2.fill", on: false) { c.toggleMute() }
                .help("Mute")
            Rectangle().fill(p.stroke).frame(width: 1, height: 26)
            RoundToggle(symbol: "slider.horizontal.3", on: state.expanded == .controls) { state.toggle(.controls) }
                .help("More controls")
        }
    }
}

// MARK: - Card (Control Center style)

struct ControlsCard: View {
    @ObservedObject var c = ControlsStore.shared
    @Environment(\.palette) var p

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                CCToggle(title: "Wi-Fi", subtitle: c.wifiOn ? (c.wifiName ?? "On") : "Off",
                         symbol: "wifi", on: c.wifiOn) { c.toggleWifi() }
                CCToggle(title: "Bluetooth", subtitle: c.bluetoothOn == nil ? "Settings" : ((c.bluetoothOn ?? false) ? "On" : "Off"),
                         symbol: "dot.radiowaves.left.and.right", on: c.bluetoothOn ?? false) { c.toggleBluetooth() }
            }
            HStack(spacing: 10) {
                CCToggle(title: "Dark Mode", subtitle: c.darkMode ? "On" : "Off",
                         symbol: "circle.lefthalf.filled", on: c.darkMode) { c.toggleDarkMode() }
                CCToggle(title: "Focus", subtitle: "Settings",
                         symbol: "moon.fill", on: false) { c.openFocus() }
            }

            if let b = c.brightness {
                VStack(alignment: .leading, spacing: 5) {
                    SectionLabel(text: "Display")
                    CCSlider(symbol: "sun.max.fill", value: b) { v in c.setBrightness(v) }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(p.tile))
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    SectionLabel(text: "Sound")
                    Spacer()
                    Text("\(Int(c.volume * 100))%")
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(p.secondary)
                }
                CCSlider(symbol: c.muted ? "speaker.slash.fill" : "speaker.wave.2.fill", value: c.muted ? 0 : c.volume) { v in
                    c.setVolume(v)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(p.tile))

            HStack(spacing: 0) {
                CCAction(title: "Screenshot", symbol: "camera.viewfinder") { c.screenshot() }
                CCAction(title: "AirDrop", symbol: "paperplane.fill") { c.airDrop() }
                CCAction(title: "Sleep Display", symbol: "display") { c.sleepDisplay() }
                CCAction(title: c.dockHidden ? "Show Dock" : "Hide Dock", symbol: "dock.arrow.down.rectangle") {
                    c.toggleSystemDock()
                }
            }
        }
        .frame(width: 316, alignment: .leading)
        .onAppear { c.refresh() }
    }
}

struct CCToggle: View {
    let title: String
    let subtitle: String?
    let symbol: String
    let on: Bool
    let action: () -> Void

    @Environment(\.palette) var p

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(on ? Color.white : p.primary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(on ? Color.accentColor : p.tileHover))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(p.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 10.5))
                            .foregroundStyle(p.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(width: 92, alignment: .leading)
            }
            .padding(10)
            .frame(width: 153, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(p.tile))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct CCAction: View {
    let title: String
    let symbol: String
    let action: () -> Void

    @Environment(\.palette) var p
    @State var hover = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(p.primary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(hover ? p.tileHover : p.tile))
                Text(title)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(p.secondary)
                    .lineLimit(1)
            }
            .frame(width: 79)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
