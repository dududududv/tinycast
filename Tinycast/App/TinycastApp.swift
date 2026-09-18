import SwiftUI

@main
struct TinycastApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    // `@AppStorage` republishes only on change, avoiding a scene ⇄ binding loop.
    @AppStorage(SettingsKey.showInMenuBar) private var showInMenuBar = true

    // Channel-aware: "Tinycast", "Tinycast Dev", or "Tinycast Beta".
    private let appName = Bundle.main.appDisplayName

    var body: some Scene {
        MenuBarExtra(isInserted: $showInMenuBar) {
            Button("Open \(appName)") {
                AppCore.shared.paletteCoordinator.summonPalette()
            }
            Button("Clipboard History") {
                AppCore.shared.paletteCoordinator.showPalette(mode: .clipboard)
            }
            Divider()
            Button("Settings...") { AppCore.shared.settingsCoordinator.showSettings() }
                .keyboardShortcut(",")
            Divider()
            // No ⌘Q: the app menu binds it to Close Settings, and two contradictory ⌘Qs is a lie.
            Button("Quit \(appName)") { NSApp.terminate(nil) }
        } label: {
            Label(appName, systemImage: "bolt.fill")
                .symbolRenderingMode(.monochrome)
        }
        .commands { menuBarCommands }
    }

    /// Declared, not assigned to `NSApp.mainMenu`: SwiftUI rebuilds the menu on any scene change.
    @CommandsBuilder
    private var menuBarCommands: some Commands {
        CommandGroup(replacing: .appInfo) {}
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { AppCore.shared.settingsCoordinator.showSettings() }
                .keyboardShortcut(",")
        }
        CommandGroup(replacing: .appTermination) {
            Button("Close Settings") { AppCore.shared.settingsCoordinator.closeSettings() }
                .keyboardShortcut("q")
        }
    }
}
