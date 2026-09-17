import Foundation

/// How long a hidden palette keeps its current screen and draft before returning to the launcher.
enum PopToRootTimeout: Int, CaseIterable, Identifiable, Sendable {
    case immediately = 0
    case afterFive = 5
    case afterFifteen = 15
    case afterThirty = 30
    case afterSixty = 60
    case afterNinety = 90
    case afterFiveMinutes = 300

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .immediately: return "Immediately"
        case .afterFiveMinutes: return "After 5 minutes"
        default: return "After \(rawValue) seconds"
        }
    }

    var interval: TimeInterval { TimeInterval(rawValue) }

    static func resolve(storedRawValue: Int?) -> PopToRootTimeout {
        storedRawValue.flatMap(PopToRootTimeout.init) ?? .afterFiveMinutes
    }
}
