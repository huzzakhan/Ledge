import SwiftUI
import AppKit
import UniformTypeIdentifiers

final class FavoritesStore: ObservableObject {
    static let shared = FavoritesStore()

    @Published var items: [URL] = [] {
        didSet { UserDefaults.standard.set(items.map { $0.path }, forKey: key) }
    }

    private let key = "favorites.paths"
    private var iconCache: [String: NSImage] = [:]

    init() {
        if let paths = UserDefaults.standard.stringArray(forKey: key) {
            items = paths.map { URL(fileURLWithPath: $0) }
                .filter { FileManager.default.fileExists(atPath: $0.path) }
        } else {
            let defaults = ["com.apple.finder", "com.apple.Safari", "com.apple.Music", "com.apple.mail",
                            "com.apple.Notes", "com.apple.reminders", "com.apple.systempreferences"]
            items = defaults.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
        }
    }

    func open(_ url: URL) {
        if url.pathExtension == "app" {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in }
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    func add(_ url: URL) {
        guard !items.contains(url) else { return }
        items.append(url)
    }

    func remove(_ url: URL) {
        items.removeAll { $0 == url }
    }

    func addViaPanel() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add to Ledge"
        panel.message = "Choose apps, folders or files to pin in Ledge"
        if panel.runModal() == .OK {
            for url in panel.urls { add(url) }
        }
    }

    func icon(_ url: URL) -> NSImage {
        if let cached = iconCache[url.path] { return cached }
        let img = NSWorkspace.shared.icon(forFile: url.path)
        iconCache[url.path] = img
        return img
    }

    func name(_ url: URL) -> String {
        let n = FileManager.default.displayName(atPath: url.path)
        return n.hasSuffix(".app") ? String(n.dropLast(4)) : n
    }
}

// MARK: - Tile

struct AppsTile: View {
    @ObservedObject var fav = FavoritesStore.shared

    var body: some View {
        let first = Array(fav.items.prefix(4))
        VStack(spacing: 3) {
            HStack(spacing: 3) {
                icon(first, 0)
                icon(first, 1)
            }
            HStack(spacing: 3) {
                icon(first, 2)
                icon(first, 3)
            }
        }
    }

    @ViewBuilder
    private func icon(_ list: [URL], _ i: Int) -> some View {
        if i < list.count {
            Image(nsImage: fav.icon(list[i]))
                .resizable()
                .interpolation(.high)
                .frame(width: 21, height: 21)
        } else {
            Color.clear.frame(width: 21, height: 21)
        }
    }
}

// MARK: - Card

struct AppsCard: View {
    @ObservedObject var fav = FavoritesStore.shared
    @EnvironmentObject var state: DockState
    @Environment(\.palette) var p
    @State var dropTargeted = false

    private var running: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleURL != nil }
            .prefix(10)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Favorites", subtitle: "Drop apps or folders here") {
                IconButton(symbol: "plus", size: 12) { fav.addViaPanel() }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(62), spacing: 6), count: 5), spacing: 10) {
                ForEach(fav.items, id: \.self) { url in
                    AppCell(icon: fav.icon(url), name: fav.name(url))
                        .onTapGesture {
                            fav.open(url)
                            state.collapse()
                        }
                        .contextMenu {
                            Button("Open") { fav.open(url) }
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                            Divider()
                            Button("Remove from Ledge") { fav.remove(url) }
                        }
                }
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(dropTargeted ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted) { providers in
                for provider in providers {
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        if let url { DispatchQueue.main.async { fav.add(url) } }
                    }
                }
                return true
            }

            SectionLabel(text: "Running")

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(62), spacing: 6), count: 5), spacing: 10) {
                ForEach(running, id: \.processIdentifier) { app in
                    AppCell(icon: app.icon ?? NSImage(), name: app.localizedName ?? "App")
                        .onTapGesture {
                            if let url = app.bundleURL { fav.open(url) }
                            state.collapse()
                        }
                        .contextMenu {
                            if let url = app.bundleURL {
                                Button("Add to Favorites") { fav.add(url) }
                            }
                            Button("Quit") { app.terminate() }
                        }
                }
            }
            .padding(.horizontal, 6)
        }
        .frame(width: 360, alignment: .leading)
    }
}

struct AppCell: View {
    let icon: NSImage
    let name: String

    @Environment(\.palette) var p
    @State var hover = false

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 42, height: 42)
                .scaleEffect(hover ? 1.08 : 1)
            Text(name)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(p.primary)
                .lineLimit(1)
                .frame(width: 60)
        }
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { hover = h } }
    }
}
