import SwiftUI
import AppKit

// MARK: - Palette / theming

struct Palette {
    var tile: Color
    var tileHover: Color
    var primary: Color
    var secondary: Color
    var stroke: Color
    var barTint: Color
    var material: NSVisualEffectView.Material
    var isDark: Bool

    var scheme: ColorScheme { isDark ? .dark : .light }

    static func make(_ theme: DockTheme) -> Palette {
        switch theme {
        case .dark:
            return Palette(tile: Color.white.opacity(0.07), tileHover: Color.white.opacity(0.14),
                           primary: .white, secondary: Color.white.opacity(0.55),
                           stroke: Color.white.opacity(0.10), barTint: Color.black.opacity(0.72),
                           material: .hudWindow, isDark: true)
        case .light:
            return Palette(tile: Color.black.opacity(0.05), tileHover: Color.black.opacity(0.10),
                           primary: Color.black.opacity(0.88), secondary: Color.black.opacity(0.50),
                           stroke: Color.black.opacity(0.08), barTint: Color.white.opacity(0.55),
                           material: .popover, isDark: false)
        case .glass:
            return Palette(tile: Color.white.opacity(0.10), tileHover: Color.white.opacity(0.18),
                           primary: .white, secondary: Color.white.opacity(0.68),
                           stroke: Color.white.opacity(0.20), barTint: Color.black.opacity(0.15),
                           material: .hudWindow, isDark: true)
        }
    }
}

private struct PaletteKey: EnvironmentKey {
    static var defaultValue: Palette { Palette.make(.dark) }
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

// MARK: - Blur

struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var dark: Bool

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.blendingMode = .behindWindow
        v.state = .active
        apply(v)
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) { apply(v) }

    private func apply(_ v: NSVisualEffectView) {
        v.material = material
        v.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    }
}

/// The frosted, rounded panel used for the bar and the pop-up cards.
struct GlassBackground: View {
    @Environment(\.palette) var p
    var radius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            VisualEffect(material: p.material, dark: p.isDark)
            p.barTint
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(p.stroke, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.30), radius: 14, x: 0, y: 7)
    }
}

// MARK: - Tile (one widget in the bar)

struct Tile<Content: View>: View {
    var active: Bool
    var action: () -> Void
    @ViewBuilder var content: () -> Content

    @Environment(\.palette) var p
    @State var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 15, style: .continuous)
        content()
            .padding(.horizontal, 12)
            .frame(height: 58)
            .background(shape.fill(active || hovering ? p.tileHover : p.tile))
            .contentShape(shape)
            .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
            .onTapGesture { action() }
    }
}

// MARK: - Small controls

struct IconButton: View {
    let symbol: String
    var size: CGFloat = 13
    let action: () -> Void

    @Environment(\.palette) var p
    @State var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(p.primary)
                .frame(width: size * 2.2, height: size * 2.2)
                .background(Circle().fill(hover ? p.tileHover : Color.clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Small round toggle, like the buttons in Control Center.
struct RoundToggle: View {
    let symbol: String
    let on: Bool
    var size: CGFloat = 30
    let action: () -> Void

    @Environment(\.palette) var p

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(on ? Color.white : p.primary)
                .frame(width: size, height: size)
                .background(Circle().fill(on ? Color.accentColor : p.tileHover))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

struct Ring: View {
    var value: Double
    var color: Color
    var lineWidth: CGFloat = 4

    @Environment(\.palette) var p

    var body: some View {
        ZStack {
            Circle().stroke(p.tileHover, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(Fmt.clamp01(value)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

struct ProgressBar: View {
    var value: Double
    var tint: Color? = nil

    @Environment(\.palette) var p

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(p.tileHover)
                Capsule()
                    .fill(tint ?? p.primary.opacity(0.85))
                    .frame(width: g.size.width * CGFloat(Fmt.clamp01(value)))
            }
        }
    }
}

/// Thin draggable scrubber (music position).
struct Scrubber: View {
    var value: Double
    var live: Bool = false
    var onCommit: (Double) -> Void

    @Environment(\.palette) var p
    @State var drag: Double?

    var body: some View {
        GeometryReader { g in
            let v = drag ?? Fmt.clamp01(value)
            let h: CGFloat = drag == nil ? 5 : 8
            ZStack(alignment: .leading) {
                Capsule().fill(p.tileHover).frame(height: h)
                Capsule().fill(p.primary).frame(width: max(0, g.size.width * CGFloat(v)), height: h)
            }
            .frame(width: g.size.width, height: g.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { d in
                        let nv = Fmt.clamp01(Double(d.location.x / max(g.size.width, 1)))
                        drag = nv
                        if live { onCommit(nv) }
                    }
                    .onEnded { _ in
                        if let final = drag { onCommit(final) }
                        drag = nil
                    }
            )
        }
        .frame(height: 14)
        .animation(.easeOut(duration: 0.15), value: drag == nil)
    }
}

/// Big Control Center style slider (brightness / volume).
struct CCSlider: View {
    let symbol: String
    var value: Double
    var onChange: (Double) -> Void

    @Environment(\.palette) var p
    @State var drag: Double?

    var body: some View {
        GeometryReader { g in
            let v = drag ?? Fmt.clamp01(value)
            ZStack(alignment: .leading) {
                Capsule().fill(p.tileHover)
                Capsule()
                    .fill(p.isDark ? Color.white.opacity(0.92) : Color.white)
                    .frame(width: max(28, g.size.width * CGFloat(v)))
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.55))
                    .padding(.leading, 9)
            }
            .frame(width: g.size.width, height: g.size.height)
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { d in
                        let nv = Fmt.clamp01(Double(d.location.x / max(g.size.width, 1)))
                        drag = nv
                        onChange(nv)
                    }
                    .onEnded { _ in drag = nil }
            )
        }
        .frame(height: 28)
    }
}

struct CardHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.palette) var p

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(p.primary)
                if let subtitle {
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(p.secondary)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
    }
}

extension CardHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle, trailing: { EmptyView() })
    }
}

struct SectionLabel: View {
    let text: String
    @Environment(\.palette) var p
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(p.secondary)
    }
}

/// Row that highlights on hover; used in lists inside cards.
struct HoverRow<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @Environment(\.palette) var p
    @State var hover = false

    var body: some View {
        content()
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(hover ? p.tile : Color.clear))
            .contentShape(Rectangle())
            .onHover { hover = $0 }
    }
}

/// A view that lets you drag the borderless window around (floating mode).
struct WindowDragHandle: NSViewRepresentable {
    final class HandleView: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    }

    func makeNSView(context: Context) -> HandleView { HandleView() }
    func updateNSView(_ nsView: HandleView, context: Context) {}
}
