import SwiftUI
import CoreLocation

// Weather data comes from Open-Meteo (free, no API key, no account).

struct WeatherDay: Identifiable {
    let id: String
    let name: String
    let code: Int
    let hi: Double
    let lo: Double
}

private struct GeoResponse: Decodable {
    struct Result: Decodable {
        let name: String
        let latitude: Double
        let longitude: Double
    }
    let results: [Result]?
}

private struct ForecastResponse: Decodable {
    struct Current: Decodable {
        let temperature_2m: Double
        let weather_code: Int
        let is_day: Int
    }
    struct Daily: Decodable {
        let time: [String]
        let weather_code: [Int]
        let temperature_2m_max: [Double]
        let temperature_2m_min: [Double]
    }
    let current: Current
    let daily: Daily
}

enum WMO {
    static func symbol(_ code: Int, day: Bool = true) -> String {
        switch code {
        case 0: return day ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: return day ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...57: return "cloud.drizzle.fill"
        case 61...67, 80...82: return "cloud.rain.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    static func text(_ code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1: return "Mostly Clear"
        case 2: return "Partly Cloudy"
        case 3: return "Cloudy"
        case 45, 48: return "Foggy"
        case 51...57: return "Drizzle"
        case 61...67: return "Rain"
        case 71...77: return "Snow"
        case 80...82: return "Showers"
        case 85, 86: return "Snow Showers"
        case 95...99: return "Thunderstorms"
        default: return "—"
        }
    }
}

final class WeatherStore: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = WeatherStore()

    @Published var temp: Double?
    @Published var code: Int = 0
    @Published var isDay = true
    @Published var place: String = ""
    @Published var days: [WeatherDay] = []
    @Published var status: String?

    private let manager = CLLocationManager()
    private var timer: Timer?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1200, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        let raw = AppSettings.shared.weatherCity.trimmingCharacters(in: .whitespacesAndNewlines)
        let city = raw.split(separator: ",").first.map { String($0) }?.trimmingCharacters(in: .whitespaces) ?? ""
        if !city.isEmpty {
            geocode(city)
        } else {
            requestLocation()
        }
    }

    private func setStatus(_ s: String?) {
        DispatchQueue.main.async { self.status = s }
    }

    // MARK: Location

    private func requestLocation() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            setStatus("Set your city in Ledge Settings")
        default:
            manager.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let s = manager.authorizationStatus
        guard AppSettings.shared.weatherCity.isEmpty else { return }
        if s == .denied || s == .restricted {
            setStatus("Set your city in Ledge Settings")
        } else if s != .notDetermined {
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        CLGeocoder().reverseGeocodeLocation(loc) { [weak self] marks, _ in
            DispatchQueue.main.async { self?.place = marks?.first?.locality ?? "My Location" }
        }
        fetch(lat: loc.coordinate.latitude, lon: loc.coordinate.longitude)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if temp == nil { setStatus("Set your city in Ledge Settings") }
    }

    // MARK: Network

    private func geocode(_ city: String) {
        var comps = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        comps.queryItems = [URLQueryItem(name: "name", value: city), URLQueryItem(name: "count", value: "1")]
        guard let url = comps.url else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self else { return }
            guard let data, let r = try? JSONDecoder().decode(GeoResponse.self, from: data),
                  let first = r.results?.first else {
                self.setStatus("Couldn't find \"\(city)\"")
                return
            }
            DispatchQueue.main.async { self.place = first.name }
            self.fetch(lat: first.latitude, lon: first.longitude)
        }.resume()
    }

    private func fetch(lat: Double, lon: Double) {
        let unit = AppSettings.shared.useCelsius ? "celsius" : "fahrenheit"
        let s = "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)"
            + "&current=temperature_2m,weather_code,is_day"
            + "&daily=weather_code,temperature_2m_max,temperature_2m_min"
            + "&timezone=auto&forecast_days=5&temperature_unit=\(unit)"
        guard let url = URL(string: s) else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self else { return }
            guard let data, let r = try? JSONDecoder().decode(ForecastResponse.self, from: data) else {
                self.setStatus("Weather unavailable")
                return
            }
            let inF = DateFormatter()
            inF.dateFormat = "yyyy-MM-dd"
            let outF = DateFormatter()
            outF.dateFormat = "EEE"

            var days: [WeatherDay] = []
            let d = r.daily
            let n = min(d.time.count, d.weather_code.count, d.temperature_2m_max.count, d.temperature_2m_min.count)
            for i in 0..<n {
                let name = i == 0 ? "Today" : (inF.date(from: d.time[i]).map { outF.string(from: $0) } ?? d.time[i])
                days.append(WeatherDay(id: d.time[i], name: name, code: d.weather_code[i],
                                       hi: d.temperature_2m_max[i], lo: d.temperature_2m_min[i]))
            }
            DispatchQueue.main.async {
                self.temp = r.current.temperature_2m
                self.code = r.current.weather_code
                self.isDay = r.current.is_day == 1
                self.days = days
                self.status = nil
            }
        }.resume()
    }
}

private func deg(_ v: Double?) -> String {
    guard let v else { return "--°" }
    return "\(Int(v.rounded()))°"
}

// MARK: - Tile

struct WeatherTile: View {
    @ObservedObject var w = WeatherStore.shared
    @Environment(\.palette) var p

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Image(systemName: WMO.symbol(w.code, day: w.isDay))
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 15))
                    Text(deg(w.temp))
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(p.primary)
                }
                Text(w.status ?? (w.place.isEmpty ? "Today" : w.place))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(p.secondary)
                    .lineLimit(1)
                    .frame(width: 78, alignment: .leading)
            }

            ForEach(Array(w.days.dropFirst().prefix(3))) { day in
                VStack(spacing: 3) {
                    Text(day.name)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(p.secondary)
                    Image(systemName: WMO.symbol(day.code))
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 12))
                    Text(deg(day.hi))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(p.primary)
                }
            }
        }
    }
}

// MARK: - Card

struct WeatherCard: View {
    @ObservedObject var w = WeatherStore.shared
    @Environment(\.palette) var p

    var body: some View {
        let lows = w.days.map { $0.lo }
        let highs = w.days.map { $0.hi }
        let minT = lows.min() ?? 0
        let maxT = highs.max() ?? 1
        let span = max(maxT - minT, 1)

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(w.place.isEmpty ? "Weather" : w.place)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(p.primary)
                    Text(deg(w.temp))
                        .font(.system(size: 44, weight: .light, design: .rounded))
                        .foregroundStyle(p.primary)
                    Text(w.status ?? WMO.text(w.code))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(p.secondary)
                    if let today = w.days.first {
                        Text("H:\(deg(today.hi))  L:\(deg(today.lo))")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(p.secondary)
                    }
                }
                Spacer()
                Image(systemName: WMO.symbol(w.code, day: w.isDay))
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 40))
            }

            Rectangle().fill(p.stroke).frame(height: 1)

            VStack(spacing: 8) {
                ForEach(w.days) { day in
                    HStack(spacing: 10) {
                        Text(day.name)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(p.primary)
                            .frame(width: 48, alignment: .leading)
                        Image(systemName: WMO.symbol(day.code))
                            .symbolRenderingMode(.multicolor)
                            .font(.system(size: 14))
                            .frame(width: 24)
                        Text(deg(day.lo))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(p.secondary)
                            .frame(width: 34, alignment: .trailing)
                        ZStack(alignment: .leading) {
                            Capsule().fill(p.tileHover)
                            Capsule()
                                .fill(LinearGradient(colors: [.cyan, .yellow, .orange],
                                                     startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(8, 100 * CGFloat((day.hi - day.lo) / span)))
                                .offset(x: 100 * CGFloat((day.lo - minT) / span))
                        }
                        .frame(width: 100, height: 5)
                        .clipShape(Capsule())
                        Text(deg(day.hi))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(p.primary)
                            .frame(width: 34, alignment: .trailing)
                    }
                }
            }

            Button {
                w.refresh()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise").font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(p.secondary)
        }
        .frame(width: 300, alignment: .leading)
    }
}
