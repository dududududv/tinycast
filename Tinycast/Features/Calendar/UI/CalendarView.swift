import SwiftUI

struct CalendarView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let store: CalendarStore
    let selected: CalendarDay?
    let onSelect: (CalendarDay) -> Void
    let onPreviousMonth: () -> Void
    let onNextMonth: () -> Void
    let onToday: () -> Void
    let onJump: (Date) -> Void
    let onCityChange: (String) -> Void
    let onRefreshWeather: () -> Void

    @State private var isChoosingMonth = false
    @State private var monthInput = ""
    @State private var monthError = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private let weekdayNames = ["一", "二", "三", "四", "五", "六", "日"]

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.xl) {
            monthPanel
                .frame(maxWidth: .infinity)
            detailPanel
                .frame(width: Theme.Size.calendarDetailWidth)
        }
        .padding(.horizontal, Theme.Spacing.panelInset)
        .padding(.vertical, Theme.Spacing.sm)
    }

    private var monthPanel: some View {
        VStack(spacing: Theme.Spacing.lg) {
            HStack {
                BarButton {
                    monthInput = String(CalendarEngine.dateKey(store.displayedMonth).prefix(7))
                    monthError = false
                    setChoosingMonth(!isChoosingMonth)
                } label: {
                    HStack(spacing: Theme.Spacing.sm) {
                        Text(monthTitle).font(.title3.weight(.semibold))
                        SymbolImage(
                            name: isChoosingMonth ? "chevron.up" : "chevron.down", size: Theme.Size.noteGlyph
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }
                .help("点击跳转年月")
                Spacer()
                BarButton(action: onPreviousMonth) {
                    SymbolImage(name: "chevron.left", size: Theme.Size.noteGlyph)
                }
                .accessibilityLabel("上个月")
                BarButton(action: onToday) { Text("今天").font(.caption.weight(.medium)) }
                BarButton(action: onNextMonth) {
                    SymbolImage(name: "chevron.right", size: Theme.Size.noteGlyph)
                }
                .accessibilityLabel("下个月")
            }

            if isChoosingMonth {
                monthChooser
                    .transition(.asymmetric(insertion: .opacity, removal: .identity))
            } else {
                LazyVGrid(columns: columns, spacing: 3) {
                    ForEach(weekdayNames, id: \.self) { weekday in
                        Text(weekday)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                    ForEach(store.days) { day in
                        CalendarDayCell(day: day, selected: day.id == selected?.id) { onSelect(day) }
                    }
                }
                .padding(.horizontal, Theme.Spacing.sm)
                .transition(.asymmetric(insertion: .opacity, removal: .identity))
            }

            HStack(spacing: Theme.Spacing.md) {
                Text("休 假期").foregroundStyle(Theme.Colors.destructive)
                Text("班 调休").foregroundStyle(.orange)
                Spacer()
                Text("方向键选日 · 回车复制").foregroundStyle(.tertiary)
            }
            .font(.caption2)
            .padding(.horizontal, Theme.Spacing.md)
        }
        .padding(.vertical, Theme.Spacing.sm)
    }

    private var monthChooser: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            Text("跳转到年月").font(.headline)
            Text("输入年月，例如 2026-10").font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField("YYYY-MM", text: $monthInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(jumpToMonth)
                Button("前往", action: jumpToMonth).buttonStyle(.borderless)
            }
            if monthError {
                Text("请输入有效年月，如 2026-10")
                    .font(.caption).foregroundStyle(Theme.Colors.destructive)
            }
            Button("取消") { setChoosingMonth(false) }.buttonStyle(.borderless)
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.cardFill, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
    }

    private func jumpToMonth() {
        guard let date = CalendarEngine.parse(monthInput.trimmingCharacters(in: .whitespaces) + "-01") else {
            monthError = true
            return
        }
        onJump(date)
        setChoosingMonth(false)
    }

    private func setChoosingMonth(_ choosing: Bool) {
        withAnimation(reduceMotion ? nil : Theme.Motion.disclosure) {
            isChoosingMonth = choosing
        }
    }

    private var detailPanel: some View {
        Group {
            if let selected {
                CalendarDayDetail(
                    day: selected, weather: weatherState(on: selected.date),
                    city: store.city, isRefreshing: store.isLoadingWeather,
                    weatherError: store.weatherError, onCityChange: onCityChange,
                    onRefreshWeather: onRefreshWeather)
            } else {
                EmptyResults(text: String(localized: "Select a date"))
            }
        }
    }

    private func weatherState(on date: Date) -> WeatherDetailState {
        if let weather = store.weather(on: date), let snapshot = store.weather {
            return .forecast(weather, location: snapshot.locationTitle)
        }
        if store.isLoadingWeather {
            return .loading(city: store.city)
        }
        if let error = store.weatherError {
            return .failed(error)
        }
        if store.weather != nil {
            return .outsideForecast
        }
        return .loading(city: store.city)
    }

    private var monthTitle: String {
        let components = CalendarEngine.gregorian().dateComponents(
            [.year, .month], from: store.displayedMonth)
        return "\(components.year ?? 0)年\(components.month ?? 0)月"
    }
}

private struct CalendarDayCell: View {
    let day: CalendarDay
    let selected: Bool
    let onSelect: () -> Void
    @State private var hovered = false

    private var holidayColor: Color {
        guard let holiday = day.holiday else { return .primary }
        return holiday.kind == .holiday ? .red : .orange
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: Theme.Spacing.xxs) {
                Text("\(day.day)")
                    .font(.title3.weight(selected || day.isToday ? .semibold : .medium))
                    .monospacedDigit()
                    .foregroundStyle(holidayColor)
                Text(day.secondaryLabel)
                    .font(.caption2)
                    .foregroundStyle(day.festival != nil || day.solarTerm != nil ? .red : .secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: Theme.Size.calendarDayHeight)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous)
                    .fill(selected ? Theme.Colors.selection : hovered ? Theme.Colors.rowHover : .clear)
            )
            .overlay {
                if day.isToday {
                    RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous)
                        .stroke(Theme.Colors.brand, lineWidth: 1)
                }
            }
            .overlay(alignment: .topTrailing) {
                if let holiday = day.holiday {
                    Text(holiday.kind == .holiday ? "休" : "班")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(holiday.kind == .holiday ? .red : .orange)
                        .padding(.trailing, Theme.Spacing.xxs)
                }
            }
            .opacity(day.belongsToDisplayedMonth ? 1 : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.menu))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .help("\(day.key) · \(day.lunar.fullLabel)")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(day.key)，\(day.lunar.fullLabel)，\(day.secondaryLabel)")
    }
}

private struct CalendarDayDetail: View {
    let day: CalendarDay
    let weather: WeatherDetailState
    let city: String
    let isRefreshing: Bool
    let weatherError: String?
    let onCityChange: (String) -> Void
    let onRefreshWeather: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.md) {
                        Text(String(format: "%02d", day.day))
                            .font(.largeTitle.weight(.semibold)).monospacedDigit()
                        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                            Text(dateTitle).font(.headline)
                            Text(day.key).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        if day.isToday {
                            Text("今天").font(.caption).foregroundStyle(Theme.Colors.brand)
                        }
                    }
                    Text(day.lunar.fullLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let holiday = day.holiday {
                    DetailBadge(
                        symbol: holiday.kind == .holiday ? "beach.umbrella.fill" : "briefcase.fill",
                        title: holiday.name,
                        tint: holiday.kind == .holiday ? .red : .orange)
                } else if let festival = day.festival ?? day.solarTerm {
                    DetailBadge(symbol: "sparkles", title: festival, tint: Theme.Colors.brand)
                }

                CalendarWeatherDetail(
                    state: weather, city: city, isRefreshing: isRefreshing,
                    refreshError: weatherError, onCityChange: onCityChange, onRefresh: onRefreshWeather)

                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    HStack {
                        Text("黄历").font(.caption.weight(.medium))
                        Spacer()
                        Text("传统民俗参考").font(.caption2).foregroundStyle(.tertiary)
                    }
                    Text("\(day.almanac.stemBranch)日 · \(day.almanac.officer) · \(day.almanac.clash)")
                        .font(.caption).foregroundStyle(.secondary)
                    AlmanacList(title: "宜", values: day.almanac.suitable, tint: .green)
                    AlmanacList(title: "忌", values: day.almanac.avoid, tint: .red)
                    Text(day.almanac.direction).font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.xl)
        }
        .hideNativeScrollers()
        .background(Theme.Colors.cardFill, in: RoundedRectangle(cornerRadius: Theme.Radius.menuPanel))
    }

    private var dateTitle: String {
        let names = ["星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"]
        let weekday = names.indices.contains(day.weekday - 1) ? names[day.weekday - 1] : ""
        return weekday
    }
}

private enum WeatherDetailState {
    case forecast(WeatherDay, location: String)
    case loading(city: String)
    case failed(String)
    case outsideForecast
}

private struct CalendarWeatherDetail: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let state: WeatherDetailState
    let city: String
    let isRefreshing: Bool
    let refreshError: String?
    let onCityChange: (String) -> Void
    let onRefresh: () -> Void
    @State private var editingCity = false
    @State private var cityInput = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: 0) {
                BarButton {
                    cityInput = city
                    setEditingCity(!editingCity)
                } label: {
                    HStack(spacing: Theme.Spacing.xs) {
                        SymbolImage(name: "location", size: Theme.Size.noteGlyph)
                        Text(city).font(.caption.weight(.medium)).lineLimit(1)
                        SymbolImage(name: "chevron.down", size: Theme.Size.noteGlyph)
                            .rotationEffect(.degrees(editingCity ? 180 : 0))
                    }
                }
                .help("切换天气城市")
                Spacer(minLength: 0)
                BarButton(action: onRefresh) {
                    SymbolImage(name: "arrow.clockwise", size: Theme.Size.noteGlyph)
                }
                .disabled(isRefreshing)
                .accessibilityLabel("刷新天气")
            }
            if editingCity {
                HStack(spacing: Theme.Spacing.sm) {
                    TextField("城市名称", text: $cityInput)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(saveCity)
                    Button("确定", action: saveCity)
                        .buttonStyle(.borderless)
                        .disabled(cityInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .transition(.asymmetric(insertion: .opacity, removal: .identity))
            }
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                leading
                    .frame(width: Theme.Size.rowIcon, height: Theme.Size.rowIcon)
                content
            }
            if case .forecast = state {
                if isRefreshing {
                    Text("正在更新…").font(.caption2).foregroundStyle(.secondary)
                } else if refreshError != nil {
                    Text("更新失败，当前显示缓存预报")
                        .font(.caption2).foregroundStyle(.orange)
                        .help(refreshError ?? "")
                }
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.cardFill, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
    }

    private func saveCity() {
        let value = cityInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        onCityChange(value)
        setEditingCity(false)
    }

    private func setEditingCity(_ editing: Bool) {
        withAnimation(reduceMotion ? nil : Theme.Motion.disclosure) {
            editingCity = editing
        }
    }

    @ViewBuilder private var leading: some View {
        switch state {
        case .forecast(let weather, _):
            SymbolImage(name: weather.condition.symbol, size: Theme.Size.rowIcon)
                .foregroundStyle(Theme.Colors.brand)
        case .loading:
            ProgressView()
                .controlSize(.small)
        case .failed:
            SymbolImage(name: "exclamationmark.triangle.fill", size: Theme.Size.rowIcon)
                .foregroundStyle(.orange)
        case .outsideForecast:
            SymbolImage(name: "calendar.badge.exclamationmark", size: Theme.Size.rowIcon)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .forecast(let weather, let location):
            VStack(alignment: .leading, spacing: 2) {
                Text(
                    "\(weather.condition.title)  \(rounded(weather.low))° – \(rounded(weather.high))°"
                )
                .font(.headline).monospacedDigit()
                Text("\(location) · 降水概率 \(weather.precipitationProbability)%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .loading(let city):
            VStack(alignment: .leading, spacing: 2) {
                Text("正在获取天气…")
                Text(city)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 3) {
                Text("天气暂不可用")
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("重试", action: onRefresh)
                    .buttonStyle(.borderless)
            }
        case .outsideForecast:
            Text("该日期不在未来 16 天预报范围内")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func rounded(_ value: Double) -> Int { Int(value.rounded()) }
}

private struct DetailBadge: View {
    let symbol: String
    let title: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.callout.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.xs)
            .background(tint.opacity(0.1), in: Capsule())
    }
}

private struct AlmanacList: View {
    let title: String
    let values: [String]
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 18, height: 18)
                .background(tint.opacity(0.12), in: Circle())
            Text(values.joined(separator: " · "))
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
