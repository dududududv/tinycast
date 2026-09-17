import Foundation

struct HolidayArrangement: Equatable, Sendable {
    enum Kind: Sendable {
        case holiday
        case adjustedWorkday
    }

    let name: String
    let kind: Kind
}

enum ChineseHolidayPlan {
    static let supportedYears: ClosedRange<Int> = 2025...2026

    static func arrangement(
        on date: Date, calendar: Calendar = CalendarEngine.gregorian()
    ) -> HolidayArrangement? {
        schedule[CalendarEngine.dateKey(date, calendar: calendar)]
    }

    private static let schedule: [String: HolidayArrangement] = {
        var result: [String: HolidayArrangement] = [:]
        add("2025-01-01", "2025-01-01", "元旦", .holiday, to: &result)
        add("2025-01-28", "2025-02-04", "春节", .holiday, to: &result)
        addDays(["2025-01-26", "2025-02-08"], "春节调休", .adjustedWorkday, to: &result)
        add("2025-04-04", "2025-04-06", "清明节", .holiday, to: &result)
        add("2025-05-01", "2025-05-05", "劳动节", .holiday, to: &result)
        addDays(["2025-04-27"], "劳动节调休", .adjustedWorkday, to: &result)
        add("2025-05-31", "2025-06-02", "端午节", .holiday, to: &result)
        add("2025-10-01", "2025-10-08", "国庆节、中秋节", .holiday, to: &result)
        addDays(["2025-09-28", "2025-10-11"], "国庆节调休", .adjustedWorkday, to: &result)

        add("2026-01-01", "2026-01-03", "元旦", .holiday, to: &result)
        addDays(["2026-01-04"], "元旦调休", .adjustedWorkday, to: &result)
        add("2026-02-15", "2026-02-23", "春节", .holiday, to: &result)
        addDays(["2026-02-14", "2026-02-28"], "春节调休", .adjustedWorkday, to: &result)
        add("2026-04-04", "2026-04-06", "清明节", .holiday, to: &result)
        add("2026-05-01", "2026-05-05", "劳动节", .holiday, to: &result)
        addDays(["2026-05-09"], "劳动节调休", .adjustedWorkday, to: &result)
        add("2026-06-19", "2026-06-21", "端午节", .holiday, to: &result)
        add("2026-09-25", "2026-09-27", "中秋节", .holiday, to: &result)
        add("2026-10-01", "2026-10-07", "国庆节", .holiday, to: &result)
        addDays(["2026-09-20", "2026-10-10"], "国庆节调休", .adjustedWorkday, to: &result)
        return result
    }()

    private static func add(
        _ start: String, _ end: String, _ name: String, _ kind: HolidayArrangement.Kind,
        to result: inout [String: HolidayArrangement]
    ) {
        let calendar = CalendarEngine.gregorian()
        guard let first = CalendarEngine.parse(start, calendar: calendar),
            let last = CalendarEngine.parse(end, calendar: calendar)
        else { return }
        var date = first
        while date <= last {
            result[CalendarEngine.dateKey(date, calendar: calendar)] = HolidayArrangement(
                name: name, kind: kind)
            guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { return }
            date = next
        }
    }

    private static func addDays(
        _ days: [String], _ name: String, _ kind: HolidayArrangement.Kind,
        to result: inout [String: HolidayArrangement]
    ) {
        for day in days { result[day] = HolidayArrangement(name: name, kind: kind) }
    }
}
