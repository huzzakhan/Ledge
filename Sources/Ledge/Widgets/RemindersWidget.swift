import SwiftUI
import EventKit

struct TodoItem: Identifiable, Codable, Equatable {
    var id: String
    var title: String
    var done: Bool
    var due: Date?
}

/// Uses Apple Reminders (synced with iPhone/iCloud) when allowed,
/// otherwise keeps a simple to-do list stored on this Mac.
final class RemindersStore: ObservableObject {
    static let shared = RemindersStore()

    enum Source { case apple, local }

    @Published var items: [TodoItem] = []
    @Published var source: Source = .local
    @Published var canConnect = false

    private let store = EventKitHub.store
    private let localKey = "local.todos"

    init() {
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store,
                                               queue: .main) { [weak self] _ in self?.reload() }
        configure()
        if EventKitHub.isUndetermined(.reminder) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.connectApple() }
        }
    }

    func configure() {
        if EventKitHub.hasAccess(.reminder) {
            source = .apple
            canConnect = false
            reload()
        } else {
            source = .local
            canConnect = true
            loadLocal()
        }
    }

    func connectApple() {
        if EventKitHub.isUndetermined(.reminder) {
            EventKitHub.request(.reminder) { [weak self] _ in self?.configure() }
        } else {
            SystemLinks.privacy("Privacy_Reminders")
        }
    }

    func reload() {
        guard source == .apple else { return }
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        store.fetchReminders(matching: predicate) { [weak self] reminders in
            let cal = Calendar.current
            var mapped = (reminders ?? []).map { r -> TodoItem in
                let due = r.dueDateComponents.flatMap { cal.date(from: $0) }
                return TodoItem(id: r.calendarItemIdentifier, title: r.title ?? "", done: r.isCompleted, due: due)
            }
            mapped.sort { a, b in
                switch (a.due, b.due) {
                case let (x?, y?): return x < y
                case (.some, nil): return true
                case (nil, .some): return false
                default: return a.title < b.title
                }
            }
            DispatchQueue.main.async { self?.items = mapped }
        }
    }

    func toggle(_ item: TodoItem) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[i].done.toggle()
        let nowDone = items[i].done
        switch source {
        case .apple:
            // Small delay so you see the check before it disappears from the list.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                guard let self, let r = self.store.calendarItem(withIdentifier: item.id) as? EKReminder else { return }
                r.isCompleted = nowDone
                try? self.store.save(r, commit: true)
            }
        case .local:
            saveLocal()
        }
    }

    func add(_ title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        switch source {
        case .apple:
            guard let calendar = store.defaultCalendarForNewReminders() else { return }
            let r = EKReminder(eventStore: store)
            r.title = t
            r.calendar = calendar
            do {
                try store.save(r, commit: true)
            } catch {
                NSLog("Ledge: could not save reminder: \(error.localizedDescription)")
            }
            reload()
        case .local:
            items.append(TodoItem(id: UUID().uuidString, title: t, done: false, due: nil))
            saveLocal()
        }
    }

    func delete(_ item: TodoItem) {
        switch source {
        case .apple:
            if let r = store.calendarItem(withIdentifier: item.id) as? EKReminder {
                try? store.remove(r, commit: true)
            }
            items.removeAll { $0.id == item.id }
        case .local:
            items.removeAll { $0.id == item.id }
            saveLocal()
        }
    }

    func clearDone() {
        items.removeAll { $0.done }
        if source == .local { saveLocal() }
    }

    private func loadLocal() {
        guard let data = UserDefaults.standard.data(forKey: localKey),
              let list = try? JSONDecoder().decode([TodoItem].self, from: data) else {
            items = []
            return
        }
        items = list
    }

    private func saveLocal() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: localKey)
        }
    }
}

// MARK: - Tile

struct RemindersTile: View {
    @ObservedObject var store = RemindersStore.shared
    @Environment(\.palette) var p

    var body: some View {
        let open = store.items.filter { !$0.done }
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.orange.gradient)
                Image(systemName: "checklist")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(open.first?.title ?? "All done")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(p.primary)
                    .lineLimit(1)
                Text(open.count <= 1 ? (open.isEmpty ? "Nothing left 🎉" : "1 reminder")
                                     : "+\(open.count - 1) more")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(p.secondary)
                    .lineLimit(1)
            }
            .frame(width: 118, alignment: .leading)
        }
    }
}

// MARK: - Card

struct RemindersCard: View {
    @ObservedObject var store = RemindersStore.shared
    @Environment(\.palette) var p
    @State var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: "Reminders",
                       subtitle: store.source == .apple ? "Synced with Apple Reminders" : "Saved on this Mac") {
                if store.items.contains(where: { $0.done }) && store.source == .local {
                    Button("Clear done") { withAnimation { store.clearDone() } }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.orange)
                }
            }

            if store.canConnect {
                Button {
                    store.connectApple()
                } label: {
                    Label("Use Apple Reminders instead", systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }

            if store.items.isEmpty {
                Text("You're all caught up.")
                    .font(.system(size: 12))
                    .foregroundStyle(p.secondary)
                    .padding(.vertical, 6)
            } else if store.items.count > 7 {
                ScrollView {
                    list
                }
                .frame(width: 300, height: 290)
            } else {
                list
            }

            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.orange)
                TextField("New reminder", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(p.primary)
                    .onSubmit {
                        store.add(draft)
                        draft = ""
                    }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(p.tile))
        }
        .frame(width: 300, alignment: .leading)
    }

    private var list: some View {
        VStack(spacing: 2) {
            ForEach(store.items) { item in
                ReminderRow(item: item)
            }
        }
    }
}

struct ReminderRow: View {
    let item: TodoItem

    @ObservedObject var store = RemindersStore.shared
    @Environment(\.palette) var p
    @State var hover = false

    var body: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { store.toggle(item) }
            } label: {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(item.done ? Color.orange : p.secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .strikethrough(item.done)
                    .font(.system(size: 13))
                    .foregroundStyle(item.done ? p.secondary : p.primary)
                    .lineLimit(2)
                if let due = item.due {
                    Text(due.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 10.5))
                        .foregroundStyle(due < Date() ? Color.red : p.secondary)
                }
            }
            .frame(width: 214, alignment: .leading)

            Button {
                withAnimation { store.delete(item) }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(p.secondary)
            }
            .buttonStyle(.plain)
            .opacity(hover ? 1 : 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(hover ? p.tile : Color.clear))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }
}
