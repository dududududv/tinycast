import AppKit

@MainActor
final class CalendarCoordinator {
    private let store: CalendarStore
    private let paletteCoordinator: PaletteCoordinator
    private unowned let core: AppCore

    init(store: CalendarStore, paletteCoordinator: PaletteCoordinator, core: AppCore) {
        self.store = store
        self.paletteCoordinator = paletteCoordinator
        self.core = core
    }

    func showCalendar() {
        store.show(store.selectedDate)
        store.refreshWeather()
        paletteCoordinator.showPalette(mode: .calendar)
    }

    func copy(_ day: CalendarDay) {
        let text = "\(day.key) \(weekdayName(day.weekday)) · 农历\(day.lunar.fullLabel)"
        Paster.copyPlainText(text)
        core.showMessage("日期已复制".localized)
    }

    private func weekdayName(_ weekday: Int) -> String {
        let names = ["星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"]
        return names.indices.contains(weekday - 1) ? names[weekday - 1] : ""
    }
}
