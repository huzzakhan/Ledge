import SwiftUI
import AppKit

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            WidgetSettings()
                .tabItem { Label("Widgets", systemImage: "square.grid.2x2") }
            PermissionsSettings()
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
        }
        .frame(width: 540, height: 500)
    }
}

struct GeneralSettings: View {
    @ObservedObject var s = AppSettings.shared
    @State var launchAtLogin = LoginItem.isEnabled
    @State var systemDockHidden = SystemDock.isAutohide
    @State var cityDraft = AppSettings.shared.weatherCity

    var body: some View {
        Form {
            Section("Ledge") {
                Toggle("Show Ledge  (⌥⌘D)", isOn: $s.dockVisible)
                Picker("Position", selection: $s.position) {
                    ForEach(DockPosition.allCases) { Text($0.title).tag($0) }
                }
                Picker("Style", selection: $s.theme) {
                    ForEach(DockTheme.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Slider(value: $s.scale, in: 0.75...1.25, step: 0.05) {
                    Text("Size")
                }
            }

            Section("Mac") {
                Toggle("Open Ledge when I log in", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { v in LoginItem.set(v) }
                Toggle("Auto-hide the regular macOS Dock", isOn: $systemDockHidden)
                    .onChange(of: systemDockHidden) { v in SystemDock.setAutohide(v) }
            }

            Section("Clock & Weather") {
                Toggle("24-hour clock", isOn: $s.use24h)
                Toggle("Use Celsius", isOn: $s.useCelsius)
                    .onChange(of: s.useCelsius) { _ in WeatherStore.shared.refresh() }
                HStack {
                    TextField("City", text: $cityDraft, prompt: Text("Leave empty to use your location"))
                        .onSubmit(applyCity)
                    Button("Update", action: applyCity)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func applyCity() {
        s.weatherCity = cityDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        WeatherStore.shared.refresh()
    }
}

struct WidgetSettings: View {
    @ObservedObject var s = AppSettings.shared

    var body: some View {
        Form {
            Section("In your Ledge (left to right)") {
                if s.widgets.isEmpty {
                    Text("No widgets yet — add some below.").foregroundStyle(.secondary)
                }
                ForEach(Array(s.widgets.enumerated()), id: \.element) { index, kind in
                    HStack(spacing: 10) {
                        Image(systemName: kind.symbol)
                            .frame(width: 22)
                            .foregroundStyle(Color.accentColor)
                        Text(kind.title)
                        Spacer()
                        Button { move(index, by: -1) } label: { Image(systemName: "chevron.up") }
                            .disabled(index == 0)
                        Button { move(index, by: 1) } label: { Image(systemName: "chevron.down") }
                            .disabled(index == s.widgets.count - 1)
                        Button { s.widgets.remove(at: index) } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }
                    }
                    .buttonStyle(.borderless)
                }
            }

            let available = WidgetKind.allCases.filter { !s.widgets.contains($0) }
            if !available.isEmpty {
                Section("Available") {
                    ForEach(available) { kind in
                        HStack(spacing: 10) {
                            Image(systemName: kind.symbol)
                                .frame(width: 22)
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(kind.title)
                                Text(kind.blurb).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { s.widgets.append(kind) } label: {
                                Image(systemName: "plus.circle.fill").foregroundStyle(.green)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }

            Section("Favorites") {
                Button("Add Apps or Folders…") { FavoritesStore.shared.addViaPanel() }
                Text("Tip: you can also drag apps straight onto the Apps card in Ledge.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Reset to default widgets") { s.widgets = AppSettings.defaultWidgets }
            }
        }
        .formStyle(.grouped)
    }

    private func move(_ index: Int, by delta: Int) {
        let target = index + delta
        guard s.widgets.indices.contains(target) else { return }
        s.widgets.swapAt(index, target)
    }
}

struct PermissionsSettings: View {
    var body: some View {
        Form {
            Section {
                Text("macOS asks before Ledge can use some features. If something isn't working, turn Ledge on in the matching System Settings page.")
                    .foregroundStyle(.secondary)
            }
            Section("Features") {
                row("Reminders", "Show, add and check off your reminders", "Privacy_Reminders")
                row("Calendars", "Show upcoming events in the clock card", "Privacy_Calendars")
                row("Automation", "Control Music/Spotify, Dark Mode and the macOS Dock", "Privacy_Automation")
                row("Location", "Local weather (or type a city in General)", "Privacy_LocationServices")
                row("Bluetooth", "Turn Bluetooth on and off", "Privacy_Bluetooth")
            }
            Section("About") {
                LabeledContent("Ledge", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                Text("A second dock with live widgets for your Mac. Everything stays on your Mac — weather is fetched from Open-Meteo, nothing else leaves your computer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Quit Ledge") { NSApp.terminate(nil) }
            }
        }
        .formStyle(.grouped)
    }

    private func row(_ title: String, _ detail: String, _ anchor: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open…") { SystemLinks.privacy(anchor) }
        }
    }
}
