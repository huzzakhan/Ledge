import SwiftUI
import EventKit

// MARK: - Calendar events

struct EventItem: Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let allDay: Bool
    let color: Color
}

final class CalendarStore: ObservableObject {
    static let shared = CalendarStore()

    @Published var events: [EventItem] = []
    @Published var hasAccess = EventKitHub.hasAccess(.event)

    init() {
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: EventKitHub.store,
                                               queue: .main) { [weak self] _ in self?.refresh() }
        refresh()
    }

    func requestAccess() {
        if EventKitHub.isUndetermined(.event) {
            EventKitHub.request(.event) { [weak self] _ in self?.refresh() }
        } else {
            SystemLinks.privacy("Privacy_Calendars")
        }
    }

    func refresh() {
        hasAccess = EventKitHub.hasAccess(.event)
        guard hasAccess else { return }
        let cal = Calendar.current
        let now = Date()
        let end = cal.date(byAdding: .day, value: 2, to: cal.startOfDay(for: now)) ?? now.addingTimeInterval(172_800)
        let predicate = EventKitHub.store.predicateForEvents(withStart: now, end: end, calendars: nil)
        let found = EventKitHub.store.events(matching: predicate)
            .sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
            .prefix(5)
            .map { e -> EventItem in
                EventItem(id: e.eventIdentifier ?? UUID().uuidString,
                          title: e.title ?? "Event",
                          start: e.startDate ?? now,
                          end: e.endDate ?? now,
                          allDay: e.isAllDay,
                          color: Color(nsColor: e.calendar?.color ?? .systemBlue))
            }
        events = Array(found)
    }
}

// MARK: - Tile

struct ClockTile: View {
    @ObservedObject var settings = AppSettings.shared
    @Environment(\.palette) var p

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            VStack(alignment: .leading, spacing: 1) {
                Text(timeString(ctx.date))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(p.primary)
                Text(ctx.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(p.secondary)
            }
        }
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = settings.use24h ? "HH:mm" : "h:mm"
        return f.string(from: date)
    }
}

// MARK: - Card

struct ClockCard: View {
    @ObservedObject var store = CalendarStore.shared
    @Environment(\.palette) var p

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            MonthGrid()

            Rectangle().fill(p.stroke).frame(height: 1)

            SectionLabel(text: "Up next")

            if !store.hasAccess {
                Button {
                    store.requestAccess()
                } label: {
                    Label("Show my calendar events", systemImage: "calendar.badge.plus")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            } else if store.events.isEmpty {
                Text("Nothing else today or tomorrow 🎉")
                    .font(.system(size: 12))
                    .foregroundStyle(p.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(store.events) { event in
                        EventRow(event: event)
                    }
                }
            }
        }
        .frame(width: 270, alignment: .leading)
        .onAppear { store.refresh() }
    }
}

struct EventRow: View {
    let event: EventItem
    @Environment(\.palette) var p

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2).fill(event.color).frame(width: 4, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(p.primary)
                    .lineLimit(1)
                Text(timeText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(p.secondary)
            }
            .frame(width: 240, alignment: .leading)
        }
    }

    private var timeText: String {
        let cal = Calendar.current
        let day = cal.isDateInToday(event.start) ? "Today" : (cal.isDateInTomorrow(event.start) ? "Tomorrow" : "")
        if event.allDay { return "\(day) · All day" }
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return "\(day) · \(f.string(from: event.start)) – \(f.string(from: event.end))"
    }
}

struct MonthGrid: View {
    @Environment(\.palette) var p

    private struct Cell: Identifiable {
        let id: Int
        let label: String
        let kind: Int // 0 = weekday header, 1 = blank, 2 = day, 3 = today
    }

    private var cells: [Cell] {
        let cal = Calendar.current
        let today = Date()
        let comps = cal.dateComponents([.year, .month], from: today)
        guard let first = cal.date(from: comps),
              let range = cal.range(of: .day, in: .month, for: today) else { return [] }
        let weekdayOfFirst = cal.component(.weekday, from: first)
        let offset = (weekdayOfFirst - cal.firstWeekday + 7) % 7
        let todayDay = cal.component(.day, from: today)

        let symbols = cal.veryShortWeekdaySymbols
        let shift = cal.firstWeekday - 1
        let ordered = Array(symbols[shift...] + symbols[..<shift])

        var result: [Cell] = []
        for (i, s) in ordered.enumerated() { result.append(Cell(id: -100 + i, label: s, kind: 0)) }
        for i in 0..<offset { result.append(Cell(id: -50 + i, label: "", kind: 1)) }
        for d in range { result.append(Cell(id: d, label: "\(d)", kind: d == todayDay ? 3 : 2)) }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Date(), format: .dateTime.month(.wide).year())
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(p.primary)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(32), spacing: 4), count: 7), spacing: 4) {
                ForEach(cells) { cell in
                    switch cell.kind {
                    case 0:
                        Text(cell.label)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(p.secondary)
                            .frame(height: 18)
                    case 1:
                        Color.clear.frame(height: 26)
                    default:
                        Text(cell.label)
                            .font(.system(size: 12, weight: cell.kind == 3 ? .bold : .regular, design: .rounded))
                            .foregroundStyle(cell.kind == 3 ? Color.white : p.primary)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(cell.kind == 3 ? Color.red : Color.clear))
                    }
                }
            }
        }
    }
}
