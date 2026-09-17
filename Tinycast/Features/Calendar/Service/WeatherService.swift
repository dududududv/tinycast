import Foundation

enum WeatherService {
    static func fetch(city: String) async throws -> WeatherSnapshot {
        let session = makeSession()
        let location = try await geocode(city: city, session: session)
        return try await forecast(city: city, location: location, session: session)
    }

    private static func geocode(city: String, session: URLSession) async throws -> Location {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")
        components?.queryItems = [
            URLQueryItem(name: "name", value: city),
            URLQueryItem(name: "count", value: "1"),
            URLQueryItem(name: "language", value: "zh"),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = components?.url else { throw WeatherError.invalidRequest }
        let response: GeocodingResponse = try await request(url, session: session)
        guard let result = response.results?.first else { throw WeatherError.cityNotFound(city) }
        return Location(
            name: result.name, region: result.admin1 ?? result.country,
            latitude: result.latitude, longitude: result.longitude)
    }

    private static func forecast(
        city: String, location: Location, session: URLSession
    ) async throws
        -> WeatherSnapshot
    {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(location.latitude)),
            URLQueryItem(name: "longitude", value: String(location.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
            URLQueryItem(
                name: "daily",
                value:
                    "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset"
            ),
            URLQueryItem(name: "forecast_days", value: "16"),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        guard let url = components?.url else { throw WeatherError.invalidRequest }
        let data = try await requestData(url, session: session)
        let forecast = try decodeForecast(data)
        return WeatherSnapshot(
            city: city, region: location.title, latitude: location.latitude,
            longitude: location.longitude, fetchedAt: Date(),
            currentTemperature: forecast.currentTemperature,
            currentCode: forecast.currentCode, days: forecast.days)
    }

    private static func request<Value: Decodable>(
        _ url: URL, session: URLSession
    ) async throws
        -> Value
    {
        let data = try await requestData(url, session: session)
        do {
            return try JSONDecoder().decode(Value.self, from: data)
        } catch {
            throw WeatherError.invalidResponse
        }
    }

    private static func requestData(_ url: URL, session: URLSession) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw WeatherError.server
        }
        return data
    }

    static func decodeForecast(_ data: Data) throws -> ForecastPayload {
        let response: ForecastResponse
        do {
            response = try JSONDecoder().decode(ForecastResponse.self, from: data)
        } catch {
            throw WeatherError.invalidResponse
        }
        let count =
            [
                response.daily.time.count, response.daily.weatherCode.count,
                response.daily.temperatureMax.count, response.daily.temperatureMin.count,
                response.daily.precipitationProbability.count
            ].min() ?? 0
        let days = (0..<count).map { index in
            WeatherDay(
                dateKey: response.daily.time[index], code: response.daily.weatherCode[index],
                high: response.daily.temperatureMax[index],
                low: response.daily.temperatureMin[index],
                precipitationProbability: response.daily.precipitationProbability[index],
                sunrise: response.daily.sunrise.indices.contains(index)
                    ? response.daily.sunrise[index] : nil,
                sunset: response.daily.sunset.indices.contains(index)
                    ? response.daily.sunset[index] : nil)
        }
        return ForecastPayload(
            currentTemperature: response.current?.temperature,
            currentCode: response.current?.weatherCode, days: days)
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 20
        return URLSession(configuration: configuration)
    }

    struct ForecastPayload: Sendable {
        let currentTemperature: Double?
        let currentCode: Int?
        let days: [WeatherDay]
    }

    private struct Location: Sendable {
        let name: String
        let region: String?
        let latitude: Double
        let longitude: Double

        var title: String {
            guard let region, !region.isEmpty, region != name else { return name }
            return "\(name) · \(region)"
        }
    }

    private struct GeocodingResponse: Decodable {
        let results: [GeocodingResult]?
    }

    private struct GeocodingResult: Decodable {
        let name: String
        let latitude: Double
        let longitude: Double
        let country: String?
        let admin1: String?
    }

    private struct ForecastResponse: Decodable {
        let current: Current?
        let daily: Daily

        struct Current: Decodable {
            let temperature: Double
            let weatherCode: Int

            enum CodingKeys: String, CodingKey {
                case temperature = "temperature_2m"
                case weatherCode = "weather_code"
            }
        }

        struct Daily: Decodable {
            let time: [String]
            let weatherCode: [Int]
            let temperatureMax: [Double]
            let temperatureMin: [Double]
            let precipitationProbability: [Int]
            let sunrise: [String]
            let sunset: [String]

            enum CodingKeys: String, CodingKey {
                case time
                case weatherCode = "weather_code"
                case temperatureMax = "temperature_2m_max"
                case temperatureMin = "temperature_2m_min"
                case precipitationProbability = "precipitation_probability_max"
                case sunrise
                case sunset
            }
        }
    }
}

enum WeatherError: LocalizedError {
    case invalidRequest
    case invalidResponse
    case cityNotFound(String)
    case server

    var errorDescription: String? {
        switch self {
        case .invalidRequest: "天气请求无效"
        case .invalidResponse: "天气数据格式异常"
        case .cityNotFound(let city): "找不到城市“\(city)”"
        case .server: "天气服务暂时不可用"
        }
    }
}
