import SwiftUI
import IOKit.ps

final class StatsStore: ObservableObject {
    static let shared = StatsStore()

    @Published var cpu: Double = 0
    @Published var memUsed: Double = 0
    let memTotal = Double(ProcessInfo.processInfo.physicalMemory)
    @Published var battery: Int?
    @Published var charging = false
    @Published var diskFree: Double = 0
    @Published var diskTotal: Double = 0

    private var prevUsed: Double = 0
    private var prevTotal: Double = 0
    private var ticks = 0
    private var timer: Timer?

    init() {
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.sample() }
    }

    private func sample() {
        if let c = sampleCPU() { cpu = c }
        if let m = sampleMemory() { memUsed = m }
        if let b = sampleBattery() {
            battery = b.0
            charging = b.1
        } else {
            battery = nil
        }
        if ticks % 15 == 0 { sampleDisk() }
        ticks += 1
    }

    private func sampleCPU() -> Double? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        let user = Double(info.cpu_ticks.0)
        let system = Double(info.cpu_ticks.1)
        let idle = Double(info.cpu_ticks.2)
        let nice = Double(info.cpu_ticks.3)
        let used = user + system + nice
        let total = used + idle
        defer { prevUsed = used; prevTotal = total }
        guard prevTotal > 0, total > prevTotal else { return nil }
        return (used - prevUsed) / (total - prevTotal)
    }

    private func sampleMemory() -> Double? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        let page = Double(sysconf(_SC_PAGESIZE))
        return (Double(stats.active_count) + Double(stats.wire_count) + Double(stats.compressor_page_count)) * page
    }

    private func sampleBattery() -> (Int, Bool)? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any] else { continue }
            if let cur = desc[kIOPSCurrentCapacityKey] as? Int,
               let mx = desc[kIOPSMaxCapacityKey] as? Int, mx > 0 {
                let isCharging = (desc[kIOPSIsChargingKey] as? Bool) ?? false
                return (cur * 100 / mx, isCharging)
            }
        }
        return nil
    }

    private func sampleDisk() {
        let url = URL(fileURLWithPath: "/")
        if let v = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]) {
            diskFree = Double(v.volumeAvailableCapacityForImportantUsage ?? 0)
            diskTotal = Double(v.volumeTotalCapacity ?? 0)
        }
    }
}

private func loadColor(_ v: Double) -> Color {
    v < 0.5 ? .green : (v < 0.8 ? .yellow : .red)
}

// MARK: - Tile

struct StatsTile: View {
    @ObservedObject var s = StatsStore.shared
    @Environment(\.palette) var p

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Ring(value: s.cpu, color: loadColor(s.cpu), lineWidth: 4)
                Text("\(Int(s.cpu * 100))")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(p.primary)
            }
            .frame(width: 38, height: 38)
            .help("CPU usage")

            VStack(alignment: .leading, spacing: 4) {
                if let b = s.battery {
                    Label("\(b)%", systemImage: s.charging ? "battery.100.bolt" : batterySymbol(b))
                }
                Label("\(Int(s.memUsed / max(s.memTotal, 1) * 100))%", systemImage: "memorychip")
            }
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(p.secondary)
        }
    }
}

func batterySymbol(_ pct: Int) -> String {
    switch pct {
    case ..<13: return "battery.0"
    case ..<38: return "battery.25"
    case ..<63: return "battery.50"
    case ..<88: return "battery.75"
    default: return "battery.100"
    }
}

// MARK: - Card

struct StatsCard: View {
    @ObservedObject var s = StatsStore.shared
    @Environment(\.palette) var p

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(title: "System", subtitle: "Up \(uptime)")

            StatRow(title: "CPU", detail: "\(Int(s.cpu * 100))%", value: s.cpu, tint: loadColor(s.cpu))

            let mem = s.memUsed / max(s.memTotal, 1)
            StatRow(title: "Memory", detail: "\(Fmt.bytes(s.memUsed)) of \(Fmt.bytes(s.memTotal))",
                    value: mem, tint: loadColor(mem))

            if s.diskTotal > 0 {
                let used = 1 - s.diskFree / s.diskTotal
                StatRow(title: "Disk", detail: "\(Fmt.bytes(s.diskFree)) free", value: used, tint: .blue)
            }

            if let b = s.battery {
                StatRow(title: "Battery", detail: s.charging ? "\(b)% · Charging" : "\(b)%",
                        value: Double(b) / 100, tint: b < 20 ? .red : .green)
            }

            Button {
                let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
            } label: {
                Label("Open Activity Monitor", systemImage: "arrow.up.forward.app")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(p.secondary)
        }
        .frame(width: 270, alignment: .leading)
    }

    private var uptime: String {
        let t = Int(ProcessInfo.processInfo.systemUptime)
        let d = t / 86400, h = (t % 86400) / 3600, m = (t % 3600) / 60
        return d > 0 ? "\(d)d \(h)h" : "\(h)h \(m)m"
    }
}

struct StatRow: View {
    let title: String
    let detail: String
    let value: Double
    let tint: Color

    @Environment(\.palette) var p

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(p.primary)
                Spacer()
                Text(detail).font(.system(size: 11, weight: .medium).monospacedDigit()).foregroundStyle(p.secondary)
            }
            ProgressBar(value: value, tint: tint).frame(height: 6)
        }
        .frame(width: 270)
    }
}
