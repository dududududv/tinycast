import Foundation

enum SolarTerm {
    private static let names = [
        "小寒", "大寒", "立春", "雨水", "惊蛰", "春分", "清明", "谷雨", "立夏", "小满", "芒种", "夏至",
        "小暑", "大暑", "立秋", "处暑", "白露", "秋分", "寒露", "霜降", "立冬", "小雪", "大雪", "冬至"
    ]
    private static let minuteOffsets = [
        0, 21_208, 42_467, 63_593, 85_337, 107_014, 128_867, 150_921, 173_149, 195_551,
        218_072, 240_693, 263_343, 285_989, 308_563, 331_033, 353_350, 375_494, 397_447,
        419_210, 440_795, 462_224, 483_532, 504_758
    ]
    private static let tropicalYear: TimeInterval = 31_556_925.9747

    static func name(on date: Date, calendar: Calendar = CalendarEngine.gregorian()) -> String? {
        let year = calendar.component(.year, from: date)
        return terms(in: year).first {
            calendar.isDate($0.date, inSameDayAs: date)
        }?.name
    }

    static func latestJieBranch(on date: Date, calendar: Calendar) -> Int {
        let year = calendar.component(.year, from: date)
        let candidates = terms(in: year - 1) + terms(in: year)
        let latest = candidates.last { $0.index.isMultiple(of: 2) && $0.date <= date }
        guard let latest else { return 1 }
        return (latest.index / 2 + 1) % 12
    }

    private static func terms(in year: Int) -> [Entry] {
        let base = Date(timeIntervalSince1970: -2_208_544_500)
        return names.indices.map { index in
            let seconds = tropicalYear * Double(year - 1900) + Double(minuteOffsets[index]) * 60
            return Entry(index: index, name: names[index], date: base.addingTimeInterval(seconds))
        }
    }

    private struct Entry {
        let index: Int
        let name: String
        let date: Date
    }
}
