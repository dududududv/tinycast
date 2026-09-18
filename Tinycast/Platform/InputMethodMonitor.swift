import AppKit

@MainActor
final class InputMethodMonitor {
    private var monitor: Any?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            Self.route(event, editor: event.window?.firstResponder as? NSTextView)
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    isolated deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    static func route(_ event: NSEvent, editor: NSTextView?) -> NSEvent? {
        guard event.type == .keyDown, !event.modifierFlags.contains(.command),
            let editor,
            editor.hasMarkedText(), let context = editor.inputContext
        else { return event }
        // Consumption belongs to the input context, even when this key ends marked text.
        return context.handleEvent(event) ? nil : event
    }
}
