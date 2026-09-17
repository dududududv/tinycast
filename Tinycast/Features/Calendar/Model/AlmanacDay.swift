import Foundation

struct AlmanacDay: Equatable, Sendable {
    let stemBranch: String
    let officer: String
    let clash: String
    let direction: String
    let suitable: [String]
    let avoid: [String]

    init(date: Date, calendar: Calendar = CalendarEngine.gregorian()) {
        let reference = calendar.date(from: DateComponents(year: 2026, month: 2, day: 17)) ?? date
        let days = calendar.dateComponents([.day], from: reference, to: date).day ?? 0
        let cycle = (58 + days).positiveModulo(60)
        let stem = LunarDate.stems[cycle % 10]
        let branchIndex = cycle % 12
        stemBranch = stem + LunarDate.branches[branchIndex]

        let monthBranch = SolarTerm.latestJieBranch(on: date, calendar: calendar)
        let officerIndex = (branchIndex - monthBranch).positiveModulo(12)
        let profile = Self.profiles[officerIndex]
        officer = profile.name
        suitable = profile.suitable
        avoid = profile.avoid

        let opposite = (branchIndex + 6) % 12
        clash = "冲\(LunarDate.zodiacNames[opposite])"
        direction = Self.shaDirection(branchIndex)
    }

    private static func shaDirection(_ branch: Int) -> String {
        switch branch {
        case 8, 0, 4: return "煞南"
        case 2, 6, 10: return "煞北"
        case 11, 3, 7: return "煞西"
        default: return "煞东"
        }
    }

    private static let profiles: [(name: String, suitable: [String], avoid: [String])] = [
        ("建日", ["出行", "赴任", "祈福", "求嗣"], ["动土", "开仓"]),
        ("除日", ["祭祀", "祈福", "沐浴", "扫舍"], ["嫁娶", "远行"]),
        ("满日", ["祈福", "祭祀", "开市", "结亲"], ["服药", "栽种"]),
        ("平日", ["修饰垣墙", "平治道涂"], ["祈福", "求嗣"]),
        ("定日", ["交易", "立券", "会友", "安床"], ["诉讼", "远行"]),
        ("执日", ["祭祀", "祈福", "求嗣", "捕捉"], ["开市", "搬家"]),
        ("破日", ["破屋", "求医", "治病"], ["嫁娶", "开市", "出行"]),
        ("危日", ["祭祀", "祈福", "安床"], ["登高", "行船"]),
        ("成日", ["嫁娶", "开市", "搬家", "安葬"], ["诉讼"]),
        ("收日", ["纳财", "捕捉", "收账"], ["开市", "安葬"]),
        ("开日", ["开市", "出行", "求医", "会友"], ["安葬"]),
        ("闭日", ["祭祀", "筑堤", "塞穴"], ["开市", "出行", "嫁娶"])
    ]
}

private extension Int {
    func positiveModulo(_ divisor: Int) -> Int {
        let value = self % divisor
        return value >= 0 ? value : value + divisor
    }
}
