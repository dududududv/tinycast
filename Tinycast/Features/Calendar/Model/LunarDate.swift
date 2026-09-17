import Foundation

struct LunarDate: Equatable, Sendable {
    let cycleYear: Int
    let month: Int
    let day: Int
    let isLeapMonth: Bool
    let isNewYearsEve: Bool

    init(date: Date, timeZone: TimeZone = CalendarEngine.chinaTimeZone) {
        var calendar = Calendar(identifier: .chinese)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.timeZone = timeZone
        let values = calendar.dateComponents([.year, .month, .day, .isLeapMonth], from: date)
        cycleYear = values.year ?? 1
        month = values.month ?? 1
        day = values.day ?? 1
        isLeapMonth = values.isLeapMonth ?? false
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        let next = calendar.dateComponents([.month, .day], from: tomorrow)
        isNewYearsEve = next.month == 1 && next.day == 1 && !(month == 1 && day == 1)
    }

    var yearName: String {
        let index = max(0, cycleYear - 1)
        return Self.stems[index % Self.stems.count] + Self.branches[index % Self.branches.count]
    }

    var zodiac: String {
        let index = max(0, cycleYear - 1)
        return Self.zodiacNames[index % Self.zodiacNames.count]
    }

    var monthName: String {
        let names = ["正月", "二月", "三月", "四月", "五月", "六月", "七月", "八月", "九月", "十月", "冬月", "腊月"]
        let name = names.indices.contains(month - 1) ? names[month - 1] : "\(month)月"
        return isLeapMonth ? "闰\(name)" : name
    }

    var dayName: String {
        let names = [
            "初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
            "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
            "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十"
        ]
        return names.indices.contains(day - 1) ? names[day - 1] : "\(day)日"
    }

    var shortLabel: String { day == 1 ? monthName : dayName }
    var fullLabel: String { "\(yearName)年（\(zodiac)）\(monthName)\(dayName)" }

    static let stems = ["甲", "乙", "丙", "丁", "戊", "己", "庚", "辛", "壬", "癸"]
    static let branches = ["子", "丑", "寅", "卯", "辰", "巳", "午", "未", "申", "酉", "戌", "亥"]
    static let zodiacNames = ["鼠", "牛", "虎", "兔", "龙", "蛇", "马", "羊", "猴", "鸡", "狗", "猪"]
}

enum Festival {
    static func name(date: Date, lunar: LunarDate, solarTerm: String?) -> String? {
        if lunar.isNewYearsEve { return "除夕" }
        let lunarFestivals: [String: String] = [
            "1-1": "春节", "1-15": "元宵", "2-2": "龙抬头", "5-5": "端午",
            "7-7": "七夕", "7-15": "中元", "8-15": "中秋", "9-9": "重阳",
            "12-8": "腊八", "12-23": "小年"
        ]
        if !lunar.isLeapMonth,
            let festival = lunarFestivals["\(lunar.month)-\(lunar.day)"]
        {
            return festival
        }
        if solarTerm == "清明" { return "清明" }
        let calendar = CalendarEngine.gregorian()
        let parts = calendar.dateComponents([.month, .day], from: date)
        let solarFestivals: [String: String] = [
            "1-1": "元旦", "3-8": "妇女节", "3-12": "植树节", "5-1": "劳动节",
            "5-4": "青年节", "6-1": "儿童节", "8-1": "建军节", "9-10": "教师节",
            "10-1": "国庆节"
        ]
        return solarFestivals["\(parts.month ?? 0)-\(parts.day ?? 0)"]
    }
}
