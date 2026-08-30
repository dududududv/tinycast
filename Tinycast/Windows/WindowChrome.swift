import AppKit

/// Held by `AppWindowController` for the window's lifetime, so the chrome dies with the window.
@MainActor
protocol WindowChrome: AnyObject {
    func install(in window: NSWindow)
    func windowShouldClose(_ window: NSWindow) -> Bool
}

extension WindowChrome {
    func windowShouldClose(_ window: NSWindow) -> Bool { true }
}
