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
            if let meeting = AppCore.shared.calendarCoordinator.menuBarEvent {
                Button("Join \(meeting.title)") {
                    AppCore.shared.calendarCoordinator.join(meeting)
                }
                Divider()
            }
            Button("Open \(appName)") {
                AppCore.shared.paletteCoordinator.showPalette(mode: .launcher)
            }
            Button("Clipboard History") {
                AppCore.shared.paletteCoordinator.showPalette(mode: .clipboard)
            }
            Divider()
            Button("Check for Updates...") { AppCore.shared.updateCoordinator.checkForUpdates() }
            Button("Support \(appName)...") { AppCore.shared.supportCoordinator.showSupport() }
            Button("Settings...") { AppCore.shared.settingsCoordinator.showSettings() }
                .keyboardShortcut(",")
            Divider()
            // No ⌘Q: the app menu binds it to Close Window, and two contradictory ⌘Qs is a lie.
            Button("Quit \(appName)") { NSApp.terminate(nil) }
        } label: {
            MenuBarLabel(appName: appName)
        }
        .commands { menuBarCommands }
    }

    /// Declared, not assigned to `NSApp.mainMenu`: SwiftUI rebuilds the menu on any scene change.
    @CommandsBuilder
    private var menuBarCommands: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About \(appName)") { AppCore.shared.settingsCoordinator.showAbout() }
            Button("Check for Updates…") { AppCore.shared.updateCoordinator.checkForUpdates() }
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { AppCore.shared.settingsCoordinator.showSettings() }
                .keyboardShortcut(",")
        }
        CommandGroup(replacing: .appTermination) {
            Button("Close Window") { NSApp.keyWindow?.performClose(nil) }
                .keyboardShortcut("q")
        }
        CommandMenu("JSON") {
            Button("New JSON Document") {
                AppCore.shared.jsonEditorCoordinator.show()
                AppCore.shared.jsonEditorCoordinator.newDocument()
            }
            .keyboardShortcut("n")
            Button("Open JSON…") {
                AppCore.shared.jsonEditorCoordinator.show()
                AppCore.shared.jsonEditorCoordinator.openDocument()
            }
            .keyboardShortcut("o")
            Divider()
            Button("Save JSON") { AppCore.shared.jsonEditorCoordinator.save() }
                .keyboardShortcut("s")
            Button("Save JSON As…") { AppCore.shared.jsonEditorCoordinator.saveAs() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            Divider()
            Button("Format JSON") { AppCore.shared.jsonEditorCoordinator.format() }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            Button("Minify JSON") { AppCore.shared.jsonEditorCoordinator.minify() }
                .keyboardShortcut("m", modifiers: [.command, .option])
        }
    }
}
