import Foundation

struct CalendarDay: Identifiable, Equatable, Sendable {
    let date: Date
    let key: String
    let day: Int
    let weekday: Int
    let belongsToDisplayedMonth: Bool
    let isToday: Bool
    let lunar: LunarDate
    let solarTerm: String?
    let festival: String?
    let holiday: HolidayArrangement?
    let almanac: AlmanacDay

    var id: String { key }

    var secondaryLabel: String {
        holiday?.name ?? festival ?? solarTerm ?? lunar.shortLabel
    }
}

enum CalendarEngine {
    static let chinaTimeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current

    static func gregorian(timeZone: TimeZone = chinaTimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.timeZone = timeZone
        calendar.firstWeekday = 2
        return calendar
    }

    static func month(
        containing displayedDate: Date, today: Date = Date(),
        calendar: Calendar = gregorian()
    ) -> [CalendarDay] {
        guard let month = calendar.dateInterval(of: .month, for: displayedDate) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: month.start)
        let leading = (firstWeekday + 5) % 7
        guard let first = calendar.date(byAdding: .day, value: -leading, to: month.start) else {
            return []
        }
        return (0..<42).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: first) else {
                return nil
            }
            let components = calendar.dateComponents([.year, .month, .day, .weekday], from: date)
            let lunar = LunarDate(date: date, timeZone: calendar.timeZone)
            let term = SolarTerm.name(on: date, calendar: calendar)
            return CalendarDay(
                date: date, key: dateKey(date, calendar: calendar), day: components.day ?? 0,
                weekday: components.weekday ?? 1,
                belongsToDisplayedMonth: calendar.isDate(
                    date, equalTo: month.start, toGranularity: .month),
                isToday: calendar.isDate(date, inSameDayAs: today), lunar: lunar,
                solarTerm: term, festival: Festival.name(date: date, lunar: lunar, solarTerm: term),
                holiday: ChineseHolidayPlan.arrangement(on: date, calendar: calendar),
                almanac: AlmanacDay(date: date, calendar: calendar))
        }
    }

    static func startOfMonth(_ date: Date, calendar: Calendar = gregorian()) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? date
    }

    static func dateKey(_ date: Date, calendar: Calendar = gregorian()) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func parse(_ text: String, now: Date = Date(), calendar: Calendar = gregorian()) -> Date? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return nil }
        if value == "今天" || value.localizedCaseInsensitiveCompare("today") == .orderedSame {
            return calendar.startOfDay(for: now)
        }
        let normalized = value.replacingOccurrences(of: "/", with: "-")
        let parts = normalized.split(separator: "-").compactMap { Int($0) }
        let year: Int
        let month: Int
        let day: Int
        if parts.count == 3 {
            year = parts[0]
            month = parts[1]
            day = parts[2]
        } else if parts.count == 2 {
            year = calendar.component(.year, from: now)
            month = parts[0]
            day = parts[1]
        } else {
            return nil
        }
        let date = calendar.date(from: DateComponents(year: year, month: month, day: day))
        guard let date,
            calendar.component(.year, from: date) == year,
            calendar.component(.month, from: date) == month,
            calendar.component(.day, from: date) == day
        else { return nil }
        return date
    }
}
