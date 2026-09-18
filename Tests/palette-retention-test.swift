import AppKit
import Foundation

@MainActor
final class AppSettings {
    var compactMode = false
}

@MainActor
final class AppIndex {
    func refresh() async {}
}

@MainActor
final class FileSearchSession {
    func cancel() {}
    func search(_ query: String) {}
}

enum PaletteMode {
    case launcher
    case clipboard
    case fileSearch
    case jsonEditor
    case emoji
}

@MainActor
final class PaletteState {
    struct Snapshot {
        let mode: PaletteMode
        let query: String
    }

    var mode: PaletteMode = .launcher
    var query = ""
    var forceExpanded = false
    private(set) var prepareCount = 0

    func prepare(mode: PaletteMode) {
        self.mode = mode
        query = ""
        prepareCount += 1
    }

    func restore(_ snapshot: Snapshot) {
        mode = snapshot.mode
        query = snapshot.query
    }
}

@MainActor
final class PaletteWindowController {
    var isVisible = false
    var isKeyWindow = false
    var isClipboardVisible = false
    var previousApp: NSRunningApplication?
    var preservedState: PaletteState.Snapshot?
    private(set) var showCount = 0

    func show() {
        isVisible = true
        isClipboardVisible = false
        isKeyWindow = true
        showCount += 1
    }

    func showClipboard() {
        isVisible = true
        isClipboardVisible = true
        isKeyWindow = true
    }

    func hide(restoreFocus: Bool) {
        isVisible = false
        isClipboardVisible = false
        isKeyWindow = false
    }

    func takePreservedState() -> PaletteState.Snapshot? {
        defer { preservedState = nil }
        return preservedState
    }

    func applyCollapsed(_ collapsed: Bool) {}
    func beginDrag() {}
    func endDrag() {}
}

@main
@MainActor
private struct PaletteRetentionTests {
    private static var failures = 0

    private static func check(_ description: String, _ condition: @autoclosure () -> Bool) {
        if condition() { return }
        failures += 1
        print("FAIL: \(description)")
    }

    private static func makeCoordinator(
        mode: PaletteMode, preserved: Bool
    ) -> (PaletteCoordinator, PaletteState, PaletteWindowController) {
        let palette = PaletteState()
        palette.mode = mode
        let window = PaletteWindowController()
        if preserved {
            window.preservedState = PaletteState.Snapshot(mode: mode, query: "saved query")
        }
        let coordinator = PaletteCoordinator(
            palette: palette,
            settings: AppSettings(),
            appIndex: AppIndex(),
            fileSearch: FileSearchSession(),
            windowController: window)
        return (coordinator, palette, window)
    }

    static func main() {
        check(
            "an unset preference keeps the current screen for five minutes",
            PopToRootTimeout.resolve(storedRawValue: nil) == .afterFiveMinutes)
        check(
            "an explicitly immediate preference stays immediate",
            PopToRootTimeout.resolve(storedRawValue: 0) == .immediately)
        check(
            "a stored duration is restored",
            PopToRootTimeout.resolve(storedRawValue: 30) == .afterThirty)
        check(
            "an unknown duration uses the current default",
            PopToRootTimeout.resolve(storedRawValue: 999) == .afterFiveMinutes)
        check("five minutes is 300 seconds", PopToRootTimeout.afterFiveMinutes.interval == 300)
        check(
            "the picker names the new duration",
            PopToRootTimeout.afterFiveMinutes.title == "After 5 minutes")

        let (summon, summonedPalette, summonedWindow) = makeCoordinator(
            mode: .jsonEditor, preserved: true)
        summon.summonPalette()
        check(
            "a generic summon restores the JSON editor hidden by deactivation",
            summonedPalette.mode == .jsonEditor)
        check("restoring does not prepare a fresh screen", summonedPalette.prepareCount == 0)
        check("restoring consumes the saved snapshot", summonedWindow.preservedState == nil)
        check("restoring recovers the saved query", summonedPalette.query == "saved query")

        let (earlySummon, earlyPalette, earlyWindow) = makeCoordinator(
            mode: .jsonEditor, preserved: false)
        earlySummon.summonPalette()
        check(
            "a summon before the hide timer is installed keeps the JSON editor",
            earlyPalette.mode == .jsonEditor)
        check(
            "a summon before the hide timer is installed does not prepare a fresh screen",
            earlyPalette.prepareCount == 0)
        check("an early summon brings the panel forward", earlyWindow.showCount == 1)

        let (reactivate, reactivatedPalette, reactivatedWindow) = makeCoordinator(
            mode: .jsonEditor, preserved: false)
        reactivatedWindow.isVisible = true
        reactivatedWindow.isKeyWindow = false
        reactivate.togglePalette()
        check(
            "reactivating a visible but non-key panel keeps the JSON editor",
            reactivatedPalette.mode == .jsonEditor)
        check(
            "reactivating a visible but non-key panel does not prepare a fresh screen",
            reactivatedPalette.prepareCount == 0)
        check("reactivating brings the panel forward", reactivatedWindow.showCount == 1)

        let (dismiss, dismissedPalette, dismissedWindow) = makeCoordinator(
            mode: .jsonEditor, preserved: false)
        dismissedWindow.isVisible = true
        dismissedWindow.isKeyWindow = true
        dismiss.togglePalette()
        check("the shortcut still hides a focused JSON editor", !dismissedWindow.isVisible)
        check("hiding does not replace the JSON editor", dismissedPalette.mode == .jsonEditor)

        let (overwritten, overwrittenPalette, overwrittenWindow) = makeCoordinator(
            mode: .jsonEditor, preserved: true)
        overwrittenPalette.prepare(mode: .launcher)
        overwritten.summonPalette()
        check(
            "a stored snapshot restores the plugin after live state was overwritten",
            overwrittenPalette.mode == .jsonEditor)
        check("a stored snapshot restores its query", overwrittenPalette.query == "saved query")
        check("restoring consumes the overwritten snapshot", overwrittenWindow.preservedState == nil)

        let (dedicated, dedicatedPalette, dedicatedWindow) = makeCoordinator(mode: .jsonEditor, preserved: true)
        dedicated.showPalette(mode: .clipboard)
        check("the clipboard entry opens its own window", dedicatedWindow.isClipboardVisible)
        check("clipboard does not replace the main plugin", dedicatedPalette.mode == .jsonEditor)
        check("clipboard does not prepare the main state", dedicatedPalette.prepareCount == 0)
        check("clipboard preserves the main snapshot", dedicatedWindow.preservedState != nil)
        dedicated.togglePalette()
        check("the default shortcut switches from clipboard to main", !dedicatedWindow.isClipboardVisible)
        check("the default shortcut shows main", dedicatedWindow.isVisible)
        check("the default shortcut restores JSON", dedicatedPalette.mode == .jsonEditor)
        check("the default shortcut restores its query", dedicatedPalette.query == "saved query")
        dedicated.togglePalette()
        check("the next default shortcut hides main", !dedicatedWindow.isVisible)
        dedicated.toggleClipboard()
        check("the clipboard shortcut opens clipboard", dedicatedWindow.isClipboardVisible)
        dedicated.toggleClipboard()
        check("the clipboard shortcut hides clipboard", !dedicatedWindow.isVisible)
        dedicated.togglePalette()
        check("main still restores JSON after hiding clipboard", dedicatedPalette.mode == .jsonEditor)
        check("main does not reopen clipboard", !dedicatedWindow.isClipboardVisible)

        let (launcher, launcherPalette, launcherWindow) = makeCoordinator(mode: .launcher, preserved: false)
        launcher.toggleClipboard()
        launcher.togglePalette()
        check("launcher stays launcher after clipboard", launcherPalette.mode == .launcher)
        check("default activation opens the main window", launcherWindow.isVisible && !launcherWindow.isClipboardVisible)

        if failures == 0 {
            print("palette retention tests passed")
        } else {
            exit(1)
        }
    }
}
