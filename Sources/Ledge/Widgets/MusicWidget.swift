import SwiftUI
import AppKit

enum PlayerApp: String {
    case music, spotify

    var bundleID: String { self == .music ? "com.apple.Music" : "com.spotify.client" }
    var displayName: String { self == .music ? "Music" : "Spotify" }

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }
}

struct TrackInfo: Equatable {
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var position: Double
    var playing: Bool
    var app: PlayerApp
    var artworkURL: String?
}

/// Reads what's playing in Apple Music or Spotify and controls playback (via AppleScript).
final class NowPlayingStore: NSObject, ObservableObject {
    static let shared = NowPlayingStore()

    @Published var track: TrackInfo?
    @Published var artwork: NSImage?

    private var artKey = ""
    private var timer: Timer?
    private let sep = "|~|"

    override init() {
        super.init()
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(playerChanged),
                        name: NSNotification.Name("com.apple.Music.playerInfo"), object: nil)
        dnc.addObserver(self, selector: #selector(playerChanged),
                        name: NSNotification.Name("com.spotify.client.PlaybackStateChanged"), object: nil)
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.poll() }
        poll()
    }

    @objc private func playerChanged() {
        DispatchQueue.main.async { self.poll() }
    }

    func poll() {
        var found: [TrackInfo] = []
        for app in [PlayerApp.spotify, .music] where app.isRunning {
            if let t = query(app) { found.append(t) }
        }
        let best = found.first(where: { $0.playing }) ?? found.first
        if best != track { track = best }
        updateArtwork(best)
    }

    private func query(_ app: PlayerApp) -> TrackInfo? {
        let duration = app == .spotify ? "((duration of t) / 1000)" : "(duration of t)"
        let extra = app == .spotify ? " & \"\(sep)\" & (artwork url of t)" : ""
        let source = """
        tell application id "\(app.bundleID)"
            if player state is stopped then return ""
            set t to current track
            return (name of t) & "\(sep)" & (artist of t) & "\(sep)" & (album of t) & "\(sep)" & (\(duration) as string) & "\(sep)" & (player position as string) & "\(sep)" & (player state as string)\(extra)
        end tell
        """
        guard let out = AppleScript.run(source)?.stringValue, !out.isEmpty else { return nil }
        let parts = out.components(separatedBy: sep)
        guard parts.count >= 6 else { return nil }
        func num(_ s: String) -> Double { Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }
        return TrackInfo(title: parts[0], artist: parts[1], album: parts[2],
                         duration: num(parts[3]), position: num(parts[4]),
                         playing: parts[5] == "playing", app: app,
                         artworkURL: parts.count > 6 ? parts[6] : nil)
    }

    private func updateArtwork(_ t: TrackInfo?) {
        guard let t else {
            if !artKey.isEmpty { artKey = ""; artwork = nil }
            return
        }
        let key = "\(t.app.rawValue)|\(t.title)|\(t.album)"
        guard key != artKey else { return }
        artKey = key
        artwork = nil

        switch t.app {
        case .music:
            let src = "tell application id \"com.apple.Music\" to get raw data of artwork 1 of current track"
            if let data = AppleScript.run(src)?.data, let img = NSImage(data: data) {
                artwork = img
            }
        case .spotify:
            guard let s = t.artworkURL, let url = URL(string: s) else { return }
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let data, let img = NSImage(data: data) else { return }
                DispatchQueue.main.async {
                    if self?.artKey == key { self?.artwork = img }
                }
            }.resume()
        }
    }

    // MARK: Controls

    private var activeApp: PlayerApp { track?.app ?? .music }

    func playPause() { send("playpause") }
    func next() { send("next track") }
    func previous() { send("previous track") }

    func seek(fraction: Double) {
        guard let t = track, t.duration > 0 else { return }
        let seconds = Fmt.clamp01(fraction) * t.duration
        AppleScript.run("tell application id \"\(t.app.bundleID)\" to set player position to \(seconds)", cache: false)
        track?.position = seconds
    }

    private func send(_ command: String) {
        AppleScript.run("tell application id \"\(activeApp.bundleID)\" to \(command)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.poll() }
    }
}

// MARK: - Shared bits

struct ArtworkView: View {
    var image: NSImage?
    var size: CGFloat
    var radius: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    LinearGradient(colors: [Color.pink, Color.orange], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.42, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

// MARK: - Tile

struct MusicTile: View {
    @ObservedObject var np = NowPlayingStore.shared
    @Environment(\.palette) var p

    var body: some View {
        let t = np.track
        HStack(spacing: 10) {
            ArtworkView(image: np.artwork, size: 40, radius: 9)

            VStack(alignment: .leading, spacing: 3) {
                Text(t?.title ?? "Not Playing")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(p.primary)
                    .lineLimit(1)
                Text(t?.artist ?? "Music or Spotify")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(p.secondary)
                    .lineLimit(1)
                ProgressBar(value: (t?.duration ?? 0) > 0 ? (t!.position / t!.duration) : 0)
                    .frame(height: 3)
            }
            .frame(width: 118, alignment: .leading)

            HStack(spacing: 0) {
                IconButton(symbol: "backward.fill", size: 11) { np.previous() }
                IconButton(symbol: (t?.playing ?? false) ? "pause.fill" : "play.fill", size: 15) { np.playPause() }
                IconButton(symbol: "forward.fill", size: 11) { np.next() }
            }
        }
    }
}

// MARK: - Card

struct MusicCard: View {
    @ObservedObject var np = NowPlayingStore.shared
    @ObservedObject var controls = ControlsStore.shared
    @Environment(\.palette) var p

    var body: some View {
        let t = np.track
        VStack(alignment: .leading, spacing: 12) {
            ArtworkView(image: np.artwork, size: 268, radius: 14)
                .shadow(color: .black.opacity(0.35), radius: 12, y: 6)

            VStack(alignment: .leading, spacing: 2) {
                Text(t?.title ?? "Nothing playing")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(p.primary)
                    .lineLimit(1)
                Text(t.map { "\($0.artist) — \($0.album)" } ?? "Start something in Music or Spotify")
                    .font(.system(size: 12))
                    .foregroundStyle(p.secondary)
                    .lineLimit(1)
            }
            .frame(width: 268, alignment: .leading)

            VStack(spacing: 4) {
                Scrubber(value: (t?.duration ?? 0) > 0 ? (t!.position / t!.duration) : 0) { f in
                    np.seek(fraction: f)
                }
                .frame(width: 268)
                HStack {
                    Text(Fmt.mmss(t?.position ?? 0))
                    Spacer()
                    Text("-" + Fmt.mmss(max(0, (t?.duration ?? 0) - (t?.position ?? 0))))
                }
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(p.secondary)
                .frame(width: 268)
            }

            HStack(spacing: 26) {
                Spacer()
                IconButton(symbol: "backward.fill", size: 16) { np.previous() }
                IconButton(symbol: (t?.playing ?? false) ? "pause.fill" : "play.fill", size: 24) { np.playPause() }
                IconButton(symbol: "forward.fill", size: 16) { np.next() }
                Spacer()
            }
            .frame(width: 268)

            CCSlider(symbol: controls.muted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                     value: controls.volume) { v in controls.setVolume(v) }
                .frame(width: 268)

            if let t {
                Text("Playing from \(t.app.displayName)")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(p.secondary)
            }
        }
        .frame(width: 268, alignment: .leading)
    }
}
