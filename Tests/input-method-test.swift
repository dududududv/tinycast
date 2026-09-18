import AppKit
import Carbon.HIToolbox

@MainActor
private final class CompositionEditor: NSTextView {
    var composing = true
    var nativeKeys = 0
    lazy var context = CompositionContext(client: self)
    override var inputContext: NSTextInputContext? { context }
    override func hasMarkedText() -> Bool { composing }
    override func keyDown(with event: NSEvent) { nativeKeys += 1 }
}

@MainActor
private final class CompositionContext: NSTextInputContext {
    var calls = 0
    var accepts = true
    override func handleEvent(_ event: NSEvent) -> Bool {
        calls += 1
        if accepts { (client as? CompositionEditor)?.composing = false }
        return accepts
    }
}

@main
@MainActor
struct InputMethodTests {
    static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let editor = CompositionEditor()
        var failures = 0
        func check(_ condition: Bool, _ message: String) {
            if !condition { failures += 1; print("FAIL: \(message)") }
        }
        func event(_ code: Int, flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
                isARepeat: false, keyCode: UInt16(code))!
        }
        for code in [kVK_Return, kVK_ANSI_KeypadEnter, kVK_Escape, kVK_Delete,
                     kVK_Tab, kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow, kVK_Space] {
            editor.composing = true
            let key = event(code)
            let before = editor.context.calls
            check(InputMethodMonitor.route(key, editor: editor) == nil, "IME consumes key \(code)")
            check(!editor.composing, "commit may clear marked text within the same event")
            check(editor.context.calls == before + 1, "input context receives key exactly once")
            check(InputMethodMonitor.route(key, editor: editor) === key, "next key uses normal routing")
        }
        editor.composing = true
        let command = event(kVK_Return, flags: .command)
        let before = editor.context.calls
        check(InputMethodMonitor.route(command, editor: editor) === command, "Command chords stay unchanged")
        check(editor.context.calls == before, "Command chords are not offered twice")
        editor.context.accepts = false
        let unhandled = event(kVK_ANSI_A)
        check(InputMethodMonitor.route(unhandled, editor: editor) === unhandled, "unhandled input is preserved")
        check(InputMethodMonitor.route(unhandled, editor: nil) === unhandled, "non-text controls are unchanged")
        let panel = NotesPanel(content: NSView(), size: CGSize(width: 300, height: 200),
                               styleMask: [.borderless], acceptsMain: false)
        panel.contentView?.addSubview(editor)
        panel.makeFirstResponder(editor)
        var escapes = 0
        panel.onEscape = { escapes += 1 }
        let nativeBefore = editor.nativeKeys
        panel.sendEvent(event(kVK_Escape))
        check(escapes == 0, "Escape during note composition does not dismiss the window")
        check(editor.nativeKeys == nativeBefore + 1, "unhandled composition stays with the native editor")
        editor.composing = false
        panel.sendEvent(event(kVK_Escape))
        check(escapes == 1, "Escape outside composition keeps its existing action")
        check(!panel.isVisible, "testing never displays a window")
        print("input method tests: \(failures) failures")
        if failures > 0 { exit(1) }
    }
}
