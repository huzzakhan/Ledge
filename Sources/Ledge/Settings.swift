import SwiftUI
import Combine

enum WidgetKind: String, CaseIterable, Identifiable {
    case clock, weather, apps, reminders, music, controls, stats, timer, clipboard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clock: return "Clock & Calendar"
        case .weather: return "Weather"
        case .apps: return "Apps & Folders"
        case .reminders: return "Reminders"
        case .music: return "Now Playing"
        case .controls: return "Quick Controls"
        case .stats: return "System Stats"
        case .timer: return "Focus Timer"
        case .clipboard: return "Clipboard"
        }
    }

    var symbol: String {
        switch self {
        case .clock: return "clock.fill"
        case .weather: return "cloud.sun.fill"
        case .apps: return "square.grid.2x2.fill"
        case .reminders: return "checklist"
        case .music: return "music.note"
        case .controls: return "switch.2"
        case .stats: return "gauge.medium"
        case .timer: return "timer"
        case .clipboard: return "doc.on.clipboard"
        }
    }

    var blurb: String {
        switch self {
        case .clock: return "Time, date, month view and your next events"
        case .weather: return "Current conditions and a 5-day forecast"
        case .apps: return "Favourite apps and folders, plus running apps"
        case .reminders: return "Apple Reminders — check off and add new ones"
        case .music: return "Controls for Apple Music and Spotify"
        case .controls: return "Wi-Fi, Bluetooth, Dark Mode, sound, brightness"
        case .stats: return "CPU, memory, disk and battery"
        case .timer: return "Pomodoro-style focus timer"
        case .clipboard: return "Recent things you've copied"
        }
    }
}

enum DockPosition: String, CaseIterable, Identifiable {
    case bottom, top, floating
    var id: String { rawValue }
    var title: String {
        switch self {
        case .bottom: return "Above the Dock"
        case .top: return "Top of screen"
        case .floating: return "Floating (drag anywhere)"
        }
    }
}

enum DockTheme: String, CaseIterable, Identifiable {
    case dark, light, glass
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dark: return "Dark"
        case .light: return "Light"
        case .glass: return "Glass"
        }
    }
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let d = UserDefaults.standard

    static let defaultWidgets: [WidgetKind] = [.clock, .weather, .apps, .reminders, .music, .controls, .stats]

    @Published var widgets: [WidgetKind] { didSet { d.set(widgets.map { $0.rawValue }, forKey: "widgets") } }
    @Published var position: DockPosition { didSet { d.set(position.rawValue, forKey: "position") } }
    @Published var theme: DockTheme { didSet { d.set(theme.rawValue, forKey: "theme") } }
    @Published var scale: Double { didSet { d.set(scale, forKey: "scale") } }
    @Published var weatherCity: String { didSet { d.set(weatherCity, forKey: "weatherCity") } }
    @Published var useCelsius: Bool { didSet { d.set(useCelsius, forKey: "useCelsius") } }
    @Published var use24h: Bool { didSet { d.set(use24h, forKey: "use24h") } }
    @Published var dockVisible: Bool { didSet { d.set(dockVisible, forKey: "dockVisible") } }

    var floatingAnchor: CGPoint? {
        get {
            guard d.object(forKey: "anchorX") != nil else { return nil }
            return CGPoint(x: d.double(forKey: "anchorX"), y: d.double(forKey: "anchorY"))
        }
        set {
            if let p = newValue {
                d.set(Double(p.x), forKey: "anchorX")
                d.set(Double(p.y), forKey: "anchorY")
            } else {
                d.removeObject(forKey: "anchorX")
                d.removeObject(forKey: "anchorY")
            }
        }
    }

    init() {
        let storedWidgets = d.stringArray(forKey: "widgets")
        widgets = (storedWidgets ?? AppSettings.defaultWidgets.map { $0.rawValue })
            .compactMap { WidgetKind(rawValue: $0) }
        position = DockPosition(rawValue: d.string(forKey: "position") ?? "") ?? .bottom
        theme = DockTheme(rawValue: d.string(forKey: "theme") ?? "") ?? .dark
        scale = d.object(forKey: "scale") == nil ? 1.0 : d.double(forKey: "scale")
        weatherCity = d.string(forKey: "weatherCity") ?? ""
        useCelsius = d.object(forKey: "useCelsius") == nil ? Locale.current.usesMetricSystem : d.bool(forKey: "useCelsius")
        use24h = d.bool(forKey: "use24h")
        dockVisible = d.object(forKey: "dockVisible") == nil ? true : d.bool(forKey: "dockVisible")
    }
}
