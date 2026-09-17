# Calendar

Tinycast ships a read-only Chinese calendar inside the command palette. It shows Gregorian dates,
weekdays, lunar dates, festivals, solar terms, traditional almanac references, official Chinese
holiday arrangements and a short-range weather forecast. It never reads or writes Calendar.app,
creates events, joins meetings or asks for calendar and camera permissions.

## Invariants

- **The calendar is a palette screen, not a separate window.** `CalendarScreen` owns the 42 selectable
  rows and `CalendarView` renders the month grid plus the selected day's detail.
- **Every month is exactly 42 Monday-first cells.** Leading and trailing days remain selectable but
  render with reduced opacity, so keyboard movement never needs a special incomplete-week path.
- **China-facing data uses `Asia/Shanghai`.** Gregorian keys, lunar conversion, festivals, solar
  terms, holiday arrangements and almanac calculations agree on the same civil day regardless of the
  Mac's current time zone.
- **`Model/` is Foundation-only.** `calendar-test` compiles the shipped calendar models and verifies
  known lunar, solar-term, holiday and almanac dates.
- **Holiday arrangements are official, finite data.** `ChineseHolidayPlan.supportedYears` names the
  bundled range. A missing future year means “no published arrangement in this build,” not a guessed
  weekend or workday.
- **Almanac 宜/忌 is a traditional folk reference.** It is deterministic local data, clearly labelled
  as such, and is not presented as factual or professional advice.
- **Weather owns one private ephemeral session per request.** `urlCache` is disabled; the feature's
  atomic JSON snapshot is the only cache on disk.

## Pure calendar layer

`CalendarEngine.month(containing:)` produces a six-week grid. Every `CalendarDay` combines:

- a Gregorian date, weekday, current-month and today flags;
- `LunarDate`, derived with Foundation's Chinese calendar;
- a 24-solar-term marker and common Gregorian or lunar festival;
- an optional `HolidayArrangement` (`休` or adjusted workday `班`);
- an `AlmanacDay` with the sexagenary day, twelve-day officer, clash/direction and 宜/忌 lists.

The search field accepts `YYYY-MM-DD`, `YYYY/MM/DD`, `MM-DD`, `MM/DD`, `today` and `今天`. A valid
date opens its month and selects that cell. Arrow keys move by one day horizontally and one week
vertically; crossing a grid edge opens the adjacent month.

Solar terms use the standard tropical-year minute-offset calculation. The almanac day cycle is
anchored to the published sexagenary day for 17 February 2026, then calculated by whole civil days.
The twelve-day officer follows the latest monthly `节` branch.

## Chinese holiday arrangements

`ChineseHolidayPlan` contains the State Council's published 2025 and 2026 holiday ranges and adjusted
workdays. Holiday cells show `休`; weekend workdays show `班`. The detail pane names the arrangement.
Ordinary weekends are not marked as statutory holidays.

Adding another year means adding the newly published ranges and workdays, extending
`supportedYears`, and adding exact boundary assertions to `calendar-test`. Do not extrapolate a
future arrangement.

## Weather

`WeatherService` first resolves the configured city through Open-Meteo geocoding, then requests the
current conditions and a 16-day daily forecast. WMO weather codes map to a small local set of Chinese
labels and SF Symbols. The selected day's detail shows conditions, low/high temperature and maximum
precipitation probability when that date is inside the forecast window.

`CalendarStore` starts with `北京`, persists the user's city under the app's defaults domain and keeps
`calendar-weather.json` under `AppPaths.caches()`. A snapshot stays fresh for 30 minutes; a failed
refresh leaves any existing forecast visible, reports the failure in the date detail and Settings,
and offers a retry from the date detail. Weather requires no API key.

## Commands and settings

There is one launcher command, `command:calendar`, and one bindable action, `hotkey.calendar`. Opening
it switches the existing palette to `.calendar`. Return copies the selected Gregorian date and lunar
label; Today restores the current month and date.

The month title expands an inline `YYYY-MM` jump field. Month arrows keep the selected day number,
clamped to the destination month's last day. Keyboard movement crosses grid edges by actual civil
days. The selected date is retained in `CalendarStore` for the current app session; reopening the
calendar does not force today. Adjacent-month cells open their own month when clicked.

Date cells are accessible buttons with separate hover, selection and today treatments. The detail
pane groups the full date, forecast and almanac. Its city button expands an inline editor, and refresh
is available even when a cached forecast is present. Failed refreshes label the cached forecast.

The month chooser and city editor use a 200 ms local disclosure transition. Outgoing controls are
removed immediately while incoming content fades in; city disclosure also rotates its chevron.
Reduce Motion makes these changes immediate. Date navigation and weather data updates do not animate.

Settings ▸ Calendar contains the weather city, refresh state, the command's alias/hotkey/visibility
controls and a concise description of the bundled data. Calendar no longer appears in Permissions.
