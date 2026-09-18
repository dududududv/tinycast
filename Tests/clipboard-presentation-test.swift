import AppKit
import SwiftUI

@MainActor
private final class MarkedEditor: NSTextView {
    var composing = true
    var receivedKeys = 0
    override func hasMarkedText() -> Bool { composing }
    override func keyDown(with event: NSEvent) { receivedKeys += 1 }
}

@main
@MainActor
struct ClipboardPresentationTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let panel = PalettePanel(rootView: Color.clear)
        let hosted = panel.takeHostedContent()
        panel.setHostedContent(hosted, bottomDocked: true)
        let screens = [
            CGRect(x: 0, y: 0, width: 1440, height: 900),
            CGRect(x: 1440, y: 0, width: 2560, height: 1440),
            CGRect(x: -1920, y: -1080, width: 1920, height: 1080),
            CGRect(x: 0, y: 900, width: 1920, height: 1080)
        ]
        for screen in screens {
            let target = PalettePlacement.clipboardFrame(screenFrame: screen)
            panel.setFrame(target, display: false)
            panel.contentView?.layoutSubtreeIfNeeded()
            panel.animateClipboardEntrance()
            expect(panel.frame == target, "animation never changes the window frame")
            expect(!panel.isVisible, "preparing the animation never orders the window on screen")
            expect(panel.contentView?.layer?.masksToBounds == true, "motion is clipped to the fixed viewport")
            expect(panel.contentView?.isFlipped == false, "negative translation moves toward the screen bottom")
            expect(panel.contentView?.layer?.isGeometryFlipped == false, "layer coordinates match the viewport")
            expect(hosted?.frame == panel.contentView?.bounds, "hosting content fills the final viewport")
            let animation = panel.contentView?.layer?.animation(forKey: "clipboardEntrance") as? CABasicAnimation
            expect(animation?.keyPath == "sublayerTransform.translation.y", "only content translates")
            expect((animation?.fromValue as? NSNumber)?.doubleValue == -target.height,
                   "content starts below the viewport")
            expect((animation?.toValue as? NSNumber)?.doubleValue == 0, "content settles at its resting position")
            expect(panel.contentView?.subviews.first === hosted, "the original hosting view survives")
            panel.cancelClipboardEntrance()
            expect(panel.contentView?.layer?.animationKeys()?.isEmpty ?? true,
                   "closing cancels entrance immediately")
        }
        let viewport = panel.contentView
        panel.animateClipboardEntrance()
        let transferred = panel.takeHostedContent()
        expect(transferred === hosted, "wrapping preserves the clipboard hosting view")
        expect(viewport?.layer?.animationKeys()?.isEmpty ?? true, "detaching cancels the outgoing animation")
        panel.setHostedContent(transferred, bottomDocked: true)
        let search = PalettePanel(rootView: Color.clear)
        let searchState = PaletteState()
        let clipboardState = PaletteState()
        clipboardState.prepare(mode: .clipboard)
        search.paletteState = searchState
        panel.paletteState = clipboardState
        searchState.query = "launcher query"
        clipboardState.query = "clipboard query"
        clipboardState.query = ""
        expect(!(panel.onBareBackspace?() ?? false), "empty clipboard backspace has no launcher navigation")
        expect(clipboardState.mode == .clipboard, "empty search stays in clipboard")
        expect(searchState.query == "launcher query", "clipboard search cannot clear the launcher query")
        clipboardState.clipboardFilter = .image
        expect(searchState.clipboardFilter == .all, "filters are not shared between windows")
        expect(search.contentView !== hosted, "search and clipboard own separate hosting views")
        expect(search.hasShadow, "search retains its normal shadow")
        expect(!panel.hasShadow, "clipboard has no stationary shadow ahead of its sliding content")
        let editor = MarkedEditor(frame: CGRect(x: 0, y: 0, width: 100, height: 30))
        search.contentView?.addSubview(editor)
        search.makeFirstResponder(editor)
        var backActions = 0
        search.onBareBackspace = { backActions += 1; return true }
        let backspace = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: search.windowNumber, context: nil, characters: "\u{7f}",
            charactersIgnoringModifiers: "\u{7f}", isARepeat: false, keyCode: 51)!
        search.sendEvent(backspace)
        expect(editor.receivedKeys == 1, "composing Backspace is routed to the native editor")
        expect(backActions == 0, "composing Backspace cannot exit a plugin")
        editor.composing = false
        search.sendEvent(backspace)
        expect(backActions == 0, "a non-search editor cannot trigger empty-query navigation")
        editor.isFieldEditor = true
        let editorFrame = editor.convert(editor.bounds, to: nil)
        searchState.searchFieldFrame = CGRect(
            x: editorFrame.minX, y: (search.contentView?.bounds.height ?? 0) - editorFrame.maxY,
            width: editorFrame.width, height: editorFrame.height)
        search.sendEvent(backspace)
        expect(backActions == 1, "empty committed search still supports Backspace navigation")
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
