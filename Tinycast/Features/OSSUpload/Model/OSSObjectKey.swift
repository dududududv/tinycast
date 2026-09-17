import Foundation

enum OSSObjectKey {
    static let maximumFileSize: Int64 = 5 * 1_024 * 1_024 * 1_024

    static func make(
        fileName: String, prefix: String, date: Date, identifier: String,
        calendar inputCalendar: Calendar = Calendar(identifier: .gregorian)
    ) -> String {
        var calendar = inputCalendar
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let datePath = String(
            format: "%04d/%02d/%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        let safeIdentifier = identifier.lowercased().prefix(8)
        let safeName = URL(filePath: fileName).lastPathComponent
        return [prefix, datePath, "\(safeIdentifier)-\(safeName)"]
            .filter { !$0.isEmpty }
            .joined(separator: "/")
    }
}
