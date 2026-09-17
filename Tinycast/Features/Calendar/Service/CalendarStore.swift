import Foundation

@MainActor
@Observable
final class CalendarStore {
    private(set) var displayedMonth: Date
    private(set) var selectedDate: Date
    private(set) var days: [CalendarDay]
    private(set) var weather: WeatherSnapshot?
    private(set) var isLoadingWeather = false
    private(set) var weatherError: String?
    private(set) var city: String

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let cacheURL: URL
    @ObservationIgnored private var weatherTask: Task<Void, Never>?

    private static let cityKey = "calendarWeatherCity"
    private static let cacheLifetime: TimeInterval = 30 * 60

    init(
        defaults: UserDefaults = .standard,
        cacheDirectory: URL = AppPaths.caches(),
        now: Date = Date()
    ) {
        self.defaults = defaults
        cacheURL = cacheDirectory.appendingPathComponent("calendar-weather.json")
        city = defaults.string(forKey: Self.cityKey) ?? "北京"
        displayedMonth = CalendarEngine.startOfMonth(now)
        selectedDate = now
        days = CalendarEngine.month(containing: now, today: now)
        weather = Self.readCache(from: cacheURL, city: city)
    }

    deinit {
        weatherTask?.cancel()
    }

    func start() {
        refreshWeather()
    }

    func moveMonth(by offset: Int, now: Date = Date()) {
        let calendar = CalendarEngine.gregorian()
        guard let month = calendar.date(byAdding: .month, value: offset, to: displayedMonth) else {
            return
        }
        displayedMonth = CalendarEngine.startOfMonth(month, calendar: calendar)
        days = CalendarEngine.month(containing: displayedMonth, today: now, calendar: calendar)
    }

    func show(_ date: Date, now: Date = Date()) {
        selectedDate = date
        displayedMonth = CalendarEngine.startOfMonth(date)
        days = CalendarEngine.month(containing: displayedMonth, today: now)
    }

    func select(_ date: Date) {
        selectedDate = date
    }

    func showToday(now: Date = Date()) {
        show(now, now: now)
    }

    func weather(on date: Date) -> WeatherDay? {
        weather?.weather(on: date)
    }

    func updateCity(_ value: String) {
        let next = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !next.isEmpty else {
            weatherError = "请输入城市名称"
            return
        }
        city = next
        defaults.set(next, forKey: Self.cityKey)
        weather = Self.readCache(from: cacheURL, city: next)
        refreshWeather(force: true)
    }

    func refreshWeather(force: Bool = false) {
        if !force, let weather,
            Date().timeIntervalSince(weather.fetchedAt) < Self.cacheLifetime
        {
            return
        }
        weatherTask?.cancel()
        isLoadingWeather = true
        weatherError = nil
        let requestedCity = city
        weatherTask = Task {
            do {
                let snapshot = try await WeatherService.fetch(city: requestedCity)
                guard !Task.isCancelled, city == requestedCity else { return }
                weather = snapshot
                Self.writeCache(snapshot, to: cacheURL)
            } catch is CancellationError {
                return
            } catch {
                guard city == requestedCity else { return }
                weatherError = error.localizedDescription
            }
            guard city == requestedCity else { return }
            isLoadingWeather = false
        }
    }

    private nonisolated static func readCache(from url: URL, city: String) -> WeatherSnapshot? {
        guard let data = try? Data(contentsOf: url),
            let snapshot = try? JSONDecoder().decode(WeatherSnapshot.self, from: data),
            snapshot.city == city
        else { return nil }
        return snapshot
    }

    private nonisolated static func writeCache(_ snapshot: WeatherSnapshot, to url: URL) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
