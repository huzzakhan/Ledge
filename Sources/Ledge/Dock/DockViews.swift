import SwiftUI

struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize { .zero }
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

/// Root of the floating window: the bar plus the expanded card above (or below) it.
/// It measures itself and tells the controller how big the window should be.
struct DockRootView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var state: DockState
    var onSize: (CGSize) -> Void

    var body: some View {
        let palette = Palette.make(settings.theme)
        let atTop = settings.position == .top
        let scale = CGFloat(settings.scale)

        VStack(spacing: 10) {
            if atTop {
                DockBar()
                card(atTop: true)
            } else {
                card(atTop: false)
                DockBar()
            }
        }
        .padding(18)
        .fixedSize()
        .background(
            GeometryReader { g in
                Color.clear.preference(key: SizePreferenceKey.self,
                                       value: CGSize(width: ceil(g.size.width * scale),
                                                     height: ceil(g.size.height * scale)))
            }
        )
        .onPreferenceChange(SizePreferenceKey.self) { onSize($0) }
        .scaleEffect(scale, anchor: atTop ? .top : .bottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: atTop ? .top : .bottom)
        .environment(\.palette, palette)
        .environment(\.colorScheme, palette.scheme)
        .environmentObject(settings)
        .environmentObject(state)
    }

    @ViewBuilder
    private func card(atTop: Bool) -> some View {
        if let kind = state.expanded {
            ExpandedCard(kind: kind)
                .id(kind)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.92, anchor: atTop ? .top : .bottom).combined(with: .opacity),
                    removal: .opacity))
        }
    }
}

struct DockBar: View {
    @EnvironmentObject var settings: AppSettings
    @Environment(\.palette) var p

    var body: some View {
        HStack(spacing: 8) {
            if settings.position == .floating {
                ZStack {
                    Capsule().fill(p.secondary.opacity(0.6)).frame(width: 4, height: 24)
                    WindowDragHandle()
                }
                .frame(width: 14, height: 58)
                .help("Drag to move")
            }

            if settings.widgets.isEmpty {
                Text("Right-click → Settings… to add widgets")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(p.secondary)
                    .padding(.horizontal, 16)
                    .frame(height: 58)
            }

            ForEach(settings.widgets) { kind in
                WidgetTile(kind: kind)
            }
        }
        .padding(8)
        .background(GlassBackground(radius: 23))
        .contextMenu {
            Button("Settings…") {
                NotificationCenter.default.post(name: .ledgeOpenSettings, object: nil)
            }
            Menu("Position") {
                ForEach(DockPosition.allCases) { pos in
                    Button(pos.title) { settings.position = pos }
                }
            }
            Menu("Style") {
                ForEach(DockTheme.allCases) { theme in
                    Button(theme.title) { settings.theme = theme }
                }
            }
            Divider()
            Button("Hide Ledge (⌥⌘D to bring back)") { settings.dockVisible = false }
        }
    }
}

struct WidgetTile: View {
    let kind: WidgetKind
    @EnvironmentObject var state: DockState

    var body: some View {
        Tile(active: state.expanded == kind, action: { state.toggle(kind) }) {
            switch kind {
            case .clock: ClockTile()
            case .weather: WeatherTile()
            case .apps: AppsTile()
            case .reminders: RemindersTile()
            case .music: MusicTile()
            case .controls: ControlsTile()
            case .stats: StatsTile()
            case .timer: TimerTile()
            case .clipboard: ClipboardTile()
            }
        }
    }
}

struct ExpandedCard: View {
    let kind: WidgetKind

    var body: some View {
        Group {
            switch kind {
            case .clock: ClockCard()
            case .weather: WeatherCard()
            case .apps: AppsCard()
            case .reminders: RemindersCard()
            case .music: MusicCard()
            case .controls: ControlsCard()
            case .stats: StatsCard()
            case .timer: TimerCard()
            case .clipboard: ClipboardCard()
            }
        }
        .padding(16)
        .background(GlassBackground(radius: 22))
    }
}
