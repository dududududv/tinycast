import Foundation

@main
@MainActor
struct CalendarTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() {
        monthGrid()
        dateParsing()
        lunarCalendar()
        festivalsAndSolarTerms()
        holidayArrangements()
        almanac()
        weatherCodes()
        weatherDecoding()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func monthGrid() {
        let date = day("2026-08-01")
        let days = CalendarEngine.month(containing: date, today: day("2026-08-31"))
        expect(days.count == 42, "a month always renders a stable six-week grid")
        expect(days.first?.key == "2026-07-27", "the grid begins on Monday")
        expect(days.last?.key == "2026-09-06", "the six-week grid ends on Sunday")
        expect(days.first(where: \.isToday)?.key == "2026-08-31", "today is identified")
        expect(
            days.filter(\.belongsToDisplayedMonth).count == 31,
            "only August's 31 cells belong to the displayed month")
    }

    static func dateParsing() {
        let now = day("2026-08-31")
        expect(
            CalendarEngine.dateKey(CalendarEngine.parse("2026-10-01")!) == "2026-10-01", "full date parses")
        expect(
            CalendarEngine.dateKey(CalendarEngine.parse("10/01", now: now)!) == "2026-10-01",
            "short date uses this year")
        expect(CalendarEngine.dateKey(CalendarEngine.parse("今天", now: now)!) == "2026-08-31", "today parses")
        expect(CalendarEngine.parse("2026-02-30") == nil, "invalid dates are rejected")
    }

    static func lunarCalendar() {
        let newYear = LunarDate(date: day("2026-02-17"))
        expect(newYear.yearName == "丙午", "2026 lunar new year is 丙午")
        expect(newYear.zodiac == "马", "2026 is the horse year")
        expect(newYear.monthName == "正月" && newYear.dayName == "初一", "new year is 正月初一")
        expect(newYear.fullLabel == "丙午年（马）正月初一", "the full lunar label interpolates values")
        expect(
            LunarDate(date: day("2026-02-16")).isNewYearsEve,
            "the day before lunar new year is New Year's Eve")
    }

    static func festivalsAndSolarTerms() {
        let dragonBoat = LunarDate(date: day("2026-06-19"))
        expect(
            Festival.name(date: day("2026-06-19"), lunar: dragonBoat, solarTerm: nil) == "端午",
            "lunar festivals are recognized")
        expect(SolarTerm.name(on: day("2026-04-05")) == "清明", "2026 Qingming is recognized")
    }

    static func holidayArrangements() {
        expect(
            ChineseHolidayPlan.arrangement(on: day("2026-02-17"))?.name == "春节",
            "Spring Festival holiday is bundled")
        expect(
            ChineseHolidayPlan.arrangement(on: day("2026-02-28"))?.kind == .adjustedWorkday,
            "Spring Festival adjusted workday is bundled")
        expect(
            ChineseHolidayPlan.arrangement(on: day("2026-06-19"))?.kind == .holiday,
            "Dragon Boat Festival holiday is bundled")
        expect(
            ChineseHolidayPlan.arrangement(on: day("2027-01-01")) == nil,
            "unsupported years do not invent official arrangements")
    }

    static func almanac() {
        let value = AlmanacDay(date: day("2026-02-17"))
        expect(value.stemBranch == "壬戌", "the day stem-branch matches the calibration date")
        expect(!value.officer.isEmpty, "the twelve-day officer is present")
        expect(!value.suitable.isEmpty && !value.avoid.isEmpty, "suitable and avoid lists are present")
    }

    static func weatherCodes() {
        expect(WeatherCondition(code: 0).title == "晴", "clear weather maps to 晴")
        expect(WeatherCondition(code: 63).symbol == "cloud.rain.fill", "rain uses the rain symbol")
        expect(WeatherCondition(code: 95).title == "雷雨", "thunderstorm maps to 雷雨")
        let snapshot = WeatherSnapshot(
            city: "北京市", region: "北京 · 北京市", latitude: 39.9, longitude: 116.4,
            fetchedAt: day("2026-08-31"), currentTemperature: 28, currentCode: 0, days: [])
        expect(snapshot.locationTitle == "北京 · 北京市", "the resolved weather location is displayed")
    }

    static func weatherDecoding() {
        let fixture = Data(
            """
            {
              "current": {"temperature_2m": 27.4, "weather_code": 2},
              "daily": {
                "time": ["2026-08-31"],
                "weather_code": [61],
                "temperature_2m_max": [30.2],
                "temperature_2m_min": [22.8],
                "precipitation_probability_max": [65],
                "sunrise": ["2026-08-31T05:40"],
                "sunset": ["2026-08-31T18:44"]
              }
            }
            """.utf8)
        let forecast = try? WeatherService.decodeForecast(fixture)
        expect(forecast?.currentTemperature == 27.4, "current temperature decodes")
        expect(forecast?.currentCode == 2, "current weather code decodes")
        expect(forecast?.days.first?.dateKey == "2026-08-31", "daily date decodes")
        expect(forecast?.days.first?.precipitationProbability == 65, "precipitation decodes")
    }

    static func day(_ value: String) -> Date {
        CalendarEngine.parse(value) ?? .distantPast
    }
}
