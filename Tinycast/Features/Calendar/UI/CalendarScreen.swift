import SwiftUI

struct CalendarScreen: PaletteScreen {
    let store: CalendarStore
    let core: AppCore
    let vm: PaletteState

    var rows: [CalendarDay] { store.days }
    var primaryActionTitle: String { "Copy Date" }

    func activate(at selection: Int) {
        guard let day = day(at: selection) else { return }
        core.calendarCoordinator.copy(day)
    }

    func secondary(at selection: Int) -> Bool { false }

    func move(_ delta: Int, axis: PaletteAxis, from selection: Int) -> Int? {
        let step = axis == .horizontal ? delta : delta * 7
        guard let current = day(at: selection),
            let date = CalendarEngine.gregorian().date(byAdding: .day, value: step, to: current.date)
        else { return nil }
        if let index = index(of: date) {
            store.select(date)
            return index
        }
        store.show(date)
        return index(of: date)
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(
            CalendarView(
                store: store, selected: day(at: selection),
                onSelect: { day in
                    select(day.date)
                },
                onPreviousMonth: { changeMonth(by: -1) },
                onNextMonth: { changeMonth(by: 1) },
                onToday: {
                    store.showToday()
                    vm.selection = index(of: store.selectedDate) ?? 0
                },
                onJump: select,
                onCityChange: { store.updateCity($0) },
                onRefreshWeather: {
                    store.refreshWeather(force: true)
                }
            )
            .onAppear {
                vm.selection = index(of: store.selectedDate) ?? 0
                applyQuery(vm.query)
            }
            .onChange(of: vm.query) { _, query in applyQuery(query) })
    }

    private func day(at selection: Int) -> CalendarDay? {
        rows.indices.contains(selection) ? rows[selection] : nil
    }

    private func index(of date: Date) -> Int? {
        rows.firstIndex { CalendarEngine.gregorian().isDate($0.date, inSameDayAs: date) }
    }

    private func select(_ date: Date) {
        store.show(date)
        vm.selection = index(of: date) ?? 0
    }

    private func changeMonth(by offset: Int) {
        let calendar = CalendarEngine.gregorian()
        let dayNumber = day(at: vm.selection)?.day ?? 1
        guard let month = calendar.date(byAdding: .month, value: offset, to: store.displayedMonth),
            let range = calendar.range(of: .day, in: .month, for: month),
            let date = calendar.date(byAdding: .day, value: min(dayNumber, range.count) - 1, to: month)
        else { return }
        select(date)
    }

    private func applyQuery(_ query: String) {
        guard let date = CalendarEngine.parse(query) else { return }
        select(date)
    }
}
