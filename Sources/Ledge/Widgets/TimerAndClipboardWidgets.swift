import SwiftUI
import AppKit

// MARK: - Focus timer

final class TimerStore: ObservableObject {
    static let shared = TimerStore()

    @Published var total: TimeInterval = 25 * 60
    @Published var remaining: TimeInterval = 25 * 60
    @Published var running = false

    private var endDate: Date?
    private var tick: Timer?

    var progress: Double { total > 0 ? 1 - remaining / total : 0 }

    func start() {
        guard !running else { return }
        endDate = Date().addingTimeInterval(remaining)
        running = true
        tick = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.update() }
    }

    func pause() {
        update()
        stopTicking()
    }

    func reset() {
        stopTicking()
        remaining = total
    }

    func set(minutes: Int) {
        stopTicking()
        total = Double(minutes * 60)
        remaining = total
    }

    private func stopTicking() {
        running = false
        tick?.invalidate()
        tick = nil
        endDate = nil
    }

    private func update() {
        guard let end = endDate else { return }
        remaining = max(0, end.timeIntervalSinceNow)
        if remaining <= 0 {
            stopTicking()
            remaining = total
            NSSound(named: "Glass")?.play()
        }
    }
}

struct TimerTile: View {
    @ObservedObject var t = TimerStore.shared
    @Environment(\.palette) var p

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Ring(value: t.progress, color: .orange, lineWidth: 4)
                Image(systemName: t.running ? "pause.fill" : "play.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(p.primary)
            }
            .frame(width: 34, height: 34)
            .contentShape(Circle())
            .onTapGesture { t.running ? t.pause() : t.start() }

            VStack(alignment: .leading, spacing: 1) {
                Text(Fmt.mmss(t.remaining))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(p.primary)
                Text(t.running ? "Focusing" : "Focus")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(p.secondary)
            }
        }
    }
}

struct TimerCard: View {
    @ObservedObject var t = TimerStore.shared
    @Environment(\.palette) var p

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Ring(value: t.progress, color: .orange, lineWidth: 8)
                Text(Fmt.mmss(t.remaining))
                    .font(.system(size: 34, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(p.primary)
            }
            .frame(width: 150, height: 150)

            HStack(spacing: 8) {
                ForEach([5, 15, 25, 50], id: \.self) { m in
                    Button("\(m)m") { t.set(minutes: m) }
                        .buttonStyle(.plain)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Int(t.total / 60) == m ? Color.white : p.primary)
                        .frame(width: 46, height: 26)
                        .background(Capsule().fill(Int(t.total / 60) == m ? Color.orange : p.tile))
                }
            }

            HStack(spacing: 20) {
                IconButton(symbol: "arrow.counterclockwise", size: 14) { t.reset() }
                IconButton(symbol: t.running ? "pause.fill" : "play.fill", size: 22) {
                    t.running ? t.pause() : t.start()
                }
            }
        }
        .frame(width: 240)
    }
}

// MARK: - Clipboard history

final class ClipboardStore: ObservableObject {
    static let shared = ClipboardStore()

    @Published var history: [String] = []

    private let pb = NSPasteboard.general
    private var lastChange: Int
    private var timer: Timer?

    init() {
        lastChange = NSPasteboard.general.changeCount
        timer =Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in self?.check() }
    }

    private func check() {
        guard pb.changeCount != lastChange else { return }
        lastChange = pb.changeCount
        // Skip passwords copied from password managers.
        let types = pb.types?.map { $0.rawValue } ?? []
        if types.contains("org.nspasteboard.ConcealedType") || types.contains("org.nspasteboard.TransientType") { return }
        guard let s = pb.string(forType: .string),
              !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        history.removeAll { $0 == s }
        history.insert(s, at: 0)
        if history.count > 25 { history.removeLast(history.count - 25) }
    }

    func copy(_ s: String) {
        pb.clearContents()
        pb.setString(s, forType: .string)
        lastChange = pb.changeCount
        history.removeAll { $0 == s }
        history.insert(s, at: 0)
    }

    func clear() { history.removeAll() }
}

struct ClipboardTile: View {
    @ObservedObject var c = ClipboardStore.shared
    @Environment(\.palette) var p

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard.fill")
                .font(.system(size: 17))
                .foregroundStyle(p.primary)
            VStack(alignment: .leading, spacing: 1) {
                Text("Clipboard")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(p.primary)
                Text("\(c.history.count) items")
                    .font(.system(size: 10.5))
                    .foregroundStyle(p.secondary)
            }
        }
    }
}

struct ClipboardCard: View {
    @ObservedObject var c = ClipboardStore.shared
    @EnvironmentObject var state: DockState
    @Environment(\.palette) var p

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardHeader(title: "Clipboard", subtitle: "Click an item to copy it again") {
                if !c.history.isEmpty {
                    Button("Clear") { c.clear() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(p.secondary)
                }
            }
            if c.history.isEmpty {
                Text("Things you copy will show up here.")
                    .font(.system(size: 12))
                    .foregroundStyle(p.secondary)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(c.history.prefix(10).enumerated()), id: \.offset) { _, item in
                        HoverRow {
                            Text(item.replacingOccurrences(of: "\n", with: " "))
                                .font(.system(size: 12))
                                .foregroundStyle(p.primary)
                                .lineLimit(1)
                                .frame(width: 280, alignment: .leading)
                        }
                        .onTapGesture {
                            c.copy(item)
                            state.collapse()
                        }
                    }
                }
            }
        }
        .frame(width: 300, alignment: .leading)
    }
}
