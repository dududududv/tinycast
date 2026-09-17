import SwiftUI

struct CalendarSettingsView: View {
    @Environment(CalendarStore.self) private var store
    @State private var city = ""

    var body: some View {
        Form {
            Section {
                HStack(spacing: Theme.Spacing.lg) {
                    TextField("City", text: $city)
                        .onSubmit(saveCity)
                    Button("Update Weather", action: saveCity)
                        .disabled(city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if store.isLoadingWeather {
                    Label("Updating weather…", systemImage: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.secondary)
                } else if let error = store.weatherError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                } else if let weather = store.weather {
                    Label(
                        "Weather location: \(weather.locationTitle)",
                        systemImage: weather.currentCode.map(WeatherCondition.init)?.symbol
                            ?? "location.fill"
                    )
                    .foregroundStyle(.secondary)
                }
            } header: {
                Text("Weather")
            } footer: {
                Text("Weather comes from Open-Meteo. No API key is required.")
            }

            CalendarCommandSection()

            Section {
                Text(
                    "Shows dates, lunar dates, weekdays, solar terms, almanac, and official 2025–2026 Chinese holidays."
                )
                .foregroundStyle(.secondary)
            } header: {
                Text("Calendar Data")
            }
        }
        .formStyle(.grouped)
        .releasesFocusOnOutsideClick()
        .onAppear { city = store.city }
    }

    private func saveCity() {
        store.updateCity(city)
    }
}

private struct CalendarCommandSection: View {
    @Environment(VisibilityStore.self) private var visibility

    private var entry: AppEntry? { CommandCatalog.entry(for: .calendar) }

    var body: some View {
        Section {
            if let entry {
                SettingsRow(title: entry.name) {
                    AppIconView(app: entry)
                        .frame(width: Theme.Size.settingsRowIcon, height: Theme.Size.settingsRowIcon)
                } trailing: {
                    AliasField(entry: entry)
                    ShortcutRecorder(action: .calendar)
                    Toggle("", isOn: visibilityBinding(entry))
                        .labelsHidden()
                        .toggleStyle(.checkbox)
                        .accessibilityLabel(
                            String(localized: "Show \(entry.name.localized) in launcher"))
                }
            }
        } header: {
            Text("Calendar")
        } footer: {
            Text("A shortcut works even when its command is hidden from the launcher.")
        }
    }

    private func visibilityBinding(_ entry: AppEntry) -> Binding<Bool> {
        Binding(
            get: { visibility.isItemVisible(entry) },
            set: { visibility.setItemVisible($0, for: entry) })
    }
}
