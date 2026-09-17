import Foundation

struct WeatherSnapshot: Codable, Equatable, Sendable {
    let city: String
    let region: String?
    let latitude: Double
    let longitude: Double
    let fetchedAt: Date
    let currentTemperature: Double?
    let currentCode: Int?
    let days: [WeatherDay]

    var locationTitle: String {
        guard let region, !region.isEmpty else { return city }
        return region
    }

    func weather(on date: Date, calendar: Calendar = CalendarEngine.gregorian()) -> WeatherDay? {
        let key = CalendarEngine.dateKey(date, calendar: calendar)
        return days.first { $0.dateKey == key }
    }
}

struct WeatherDay: Codable, Equatable, Identifiable, Sendable {
    let dateKey: String
    let code: Int
    let high: Double
    let low: Double
    let precipitationProbability: Int
    let sunrise: String?
    let sunset: String?

    var id: String { dateKey }
    var condition: WeatherCondition { WeatherCondition(code: code) }
}

struct WeatherCondition: Equatable, Sendable {
    let title: String
    let symbol: String

    init(code: Int) {
        switch code {
        case 0: (title, symbol) = ("晴", "sun.max.fill")
        case 1: (title, symbol) = ("大部晴朗", "sun.min.fill")
        case 2: (title, symbol) = ("多云", "cloud.sun.fill")
        case 3: (title, symbol) = ("阴", "cloud.fill")
        case 45, 48: (title, symbol) = ("雾", "cloud.fog.fill")
        case 51, 53, 55, 56, 57: (title, symbol) = ("毛毛雨", "cloud.drizzle.fill")
        case 61, 63, 65, 66, 67: (title, symbol) = ("雨", "cloud.rain.fill")
        case 71, 73, 75, 77: (title, symbol) = ("雪", "cloud.snow.fill")
        case 80, 81, 82: (title, symbol) = ("阵雨", "cloud.heavyrain.fill")
        case 85, 86: (title, symbol) = ("阵雪", "cloud.snow.fill")
        case 95, 96, 99: (title, symbol) = ("雷雨", "cloud.bolt.rain.fill")
        default: (title, symbol) = ("未知", "cloud.fill")
        }
    }
}
