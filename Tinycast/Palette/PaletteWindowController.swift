import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class PaletteWindowController: NSObject, NSWindowDelegate {
    private unowned let core: AppCore
    private var panel: PalettePanel?
    private var searchPanel: PalettePanel?
    private var clipboardPanel: PalettePanel?
    private var clipboardScreenFrame: CGRect?
    private var switchingPanels = false
    private(set) var previousApp: NSRunningApplication?
    /// Our key window at summon time, so hiding hands focus back to Settings, not a stale app.
    private weak var previousOwnWindow: NSWindow?
    private var popToRootTimer: Timer?
    private var clipboardResetTask: Task<Void, Never>?
    private var preservedState: PaletteState.Snapshot?
    /// The session anchor — the panel's top-left, resolved once per show, the top edge being the
    /// one that must not drift. See docs/features/palette.md#window-placement.
    private var anchor: CGPoint?
    private var resizeTarget: CGRect?
    private var resizeGeneration = UUID()
    /// Live only between mouse-down and mouse-up on a drag handle; nil means a move was ours.
    private var drag: DragSession?
    private let dropGuides = PaletteDropGuideController()

    /// What a drag in flight needs: where home is, and whether releasing now would land there.
    private struct DragSession {
        var home: CGPoint
        var screenFrame: CGRect
        var armed = false
        /// The guides wait for this, so a click that never moves the panel doesn't flash them.
        var moved = false
    }

    init(core: AppCore) {
        self.core = core
    }

    deinit { clipboardResetTask?.cancel() }

    var isVisible: Bool { panel?.isVisible ?? false }
    var isKeyWindow: Bool { panel?.isKeyWindow ?? false }
    var isClipboardVisible: Bool { clipboardPanel?.isVisible ?? false }

    func show() {
        present(clipboard: false)
    }

    func showClipboard() {
        clipboardResetTask?.cancel()
        clipboardResetTask = nil
        present(clipboard: true)
    }

    private func present(clipboard: Bool) {
        Signposts.interval("PaletteWindowController.show") {
            // Summoned over one of our own windows: there is no external paste or focus target.
            let frontmost = NSWorkspace.shared.frontmostApplication
            if frontmost?.processIdentifier == NSRunningApplication.current.processIdentifier {
                previousApp = nil
                // Never the palette itself: a mode switch re-shows it while it already holds key.
                if let key = NSApp.keyWindow, key !== panel { previousOwnWindow = key }
            } else {
                previousApp = frontmost
                previousOwnWindow = nil
            }
            // Once per summon, and from `previousApp`, so the label names the paste target.
            let panel = ensurePanel(clipboard: clipboard)
            panel.paletteState?.pasteTarget = PasteTarget(app: previousApp)
            // Open disarmed: a pointer already over a row must not highlight it.
            panel.paletteState?.disarmHoverHighlight(pointerAt: NSEvent.mouseLocation)
            let wasVisible = panel.isVisible
            if !wasVisible {
                cancelResize()
                anchor = nil
            }
            let isClipboard = panel === clipboardPanel
            if isClipboard, !wasVisible { clipboardScreenFrame = targetScreen()?.frame }
            positionPanel(panel, collapsed: core.paletteCoordinator.paletteIsCollapsed, animated: wasVisible)
            // Flush first-mount layout off-screen, so the safe-area settle isn't visible.
            panel.contentView?.layoutSubtreeIfNeeded()
            core.inputSourceSwitcher.beginSession(
                preferredInputSourceID: core.settings.autoSwitchInputSourceID)
            // Non-activating, so summoning never raises our own aux windows behind it.
            let slidesIn = isClipboard && !wasVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            if slidesIn { panel.animateClipboardEntrance() }
            panel.makeKeyAndOrderFront(nil)
            panel.orderFrontRegardless()
            // A never-activated login item can drop the first key request, so re-assert.
            DispatchQueue.main.async { [weak panel] in
                guard let panel, panel.isVisible, !panel.isKeyWindow else { return }
                panel.makeKeyAndOrderFront(nil)
            }
        }
    }

    func hide(restoreFocus: Bool) {
        let hidingClipboard = panel != nil && panel === clipboardPanel
        if isVisible, !hidingClipboard { preservedState = core.palette.snapshot() }
        cancelResize()
        panel?.orderOut(nil)
        panel?.cancelClipboardEntrance()
        clipboardScreenFrame = nil
        core.inputSourceSwitcher.endSession()
        // Drop the anchor, so the next summon re-resolves for the screen in use then.
        anchor = nil
        // The guides must never outlive the panel they point at.
        drag = nil
        dropGuides.hide()
        // Drop the multi-MB preview bitmaps, so idle RAM returns near baseline.
        ImageThumbnail.purgePreviews()
        IconCache.purgeFitted()
        if hidingClipboard { scheduleClipboardReset() } else { schedulePopToRoot() }
        guard restoreFocus else { return }
        // Our own window first: it is still open, and activating another app would bury it.
        if let own = previousOwnWindow, own.isVisible {
            own.makeKeyAndOrderFront(nil)
        } else {
            previousApp?.activate()
        }
    }

    /// Pop to Root Search: reset now, or after the delay unless a reopen consumes it.
    private func schedulePopToRoot() {
        popToRootTimer?.invalidate()
        popToRootTimer = nil
        // Don't pop to root if an extension is waiting for OAuth authorization in the browser.
        guard !core.extensions.isAuthorizing else { return }
        let timeout = core.settings.popToRootTimeout
        guard timeout != .immediately else {
            preservedState = nil
            popToRoot()
            return
        }
        popToRootTimer = Timer.scheduledTimer(withTimeInterval: timeout.interval, repeats: false) {
            [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.core.extensions.isAuthorizing else { return }
                self.popToRootTimer = nil
                self.preservedState = nil
                self.popToRoot()
            }
        }
    }

    /// Both reset paths come through here, so the screen and the conversation cannot disagree about
    /// whether the palette was left behind — a chat is a thing being done, like a typed query.
    private func popToRoot() {
        core.palette.prepare(mode: .launcher)
        core.aiChatCoordinator.popToRoot()
    }

    private func scheduleClipboardReset() {
        clipboardResetTask?.cancel()
        clipboardResetTask = nil
        let timeout = core.settings.popToRootTimeout
        guard timeout != .immediately else {
            core.clipboardPalette.prepare(mode: .clipboard)
            return
        }
        clipboardResetTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(timeout.interval)) } catch { return }
            guard let self, !Task.isCancelled else { return }
            self.core.clipboardPalette.prepare(mode: .clipboard)
            self.clipboardResetTask = nil
        }
    }

    /// Takes the hidden palette snapshot and cancels its pending reset.
    func takePreservedState() -> PaletteState.Snapshot? {
        popToRootTimer?.invalidate()
        popToRootTimer = nil
        defer { preservedState = nil }
        return preservedState
    }

    /// Paste into the previous app while the palette stays frontmost.
    @discardableResult
    func pasteKeepingWindowOpen(_ item: ClipboardItem, store: ClipboardStore) -> Bool {
        Paster.pasteInPlace(item, store: store, into: previousApp)
    }

    /// String flavor of the above, for emoji/symbol pastes.
    func pasteStringKeepingWindowOpen(_ text: String) {
        Paster.pasteStringInPlace(text, into: previousApp)
    }

    // MARK: - NSWindowDelegate

    /// Dismiss when the palette loses key status (click-away, ⌘-Tab, app switch). One of our own
    /// dialogs is none of those: hiding would pop to root, which tears down an extension command
    /// while its `confirmAlert` is still waiting for the answer.
    func windowDidResignKey(_ notification: Notification) {
        guard !switchingPanels, notification.object as? NSPanel === panel,
            isVisible, !isKeyWindow, !core.isShowingDialog else { return }
        core.paletteCoordinator.hidePalette(restoreFocus: false)
    }

    /// Re-bump a turn later: on the first show a synchronous bump lands before `onChange`.
    func windowDidBecomeKey(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            panel?.paletteState?.focusToken = UUID()
            // A re-summon leaves first responder where it was, so neither of these gets an event.
            panel?.trackComposition()
            if let context = panel?.fieldEditorContext {
                core.inputSourceSwitcher.applySession(to: context)
            }
        }
    }

    /// A drag re-anchors the session, so the next resize grows from where the user left it.
    func windowDidMove(_ notification: Notification) {
        guard let panel, panel !== clipboardPanel, !switchingPanels,
            notification.object as? NSPanel === panel, resizeTarget == nil else { return }
        let moved = sessionAnchor(for: panel.frame)
        anchor = moved
        guard drag != nil else { return }
        trackDrag(to: moved)
    }

    // MARK: - Dragging

    /// A drag handle took the mouse down. Nothing shows yet — the guides wait for a real move.
    func beginDrag() {
        guard panel !== clipboardPanel else { return }
        cancelResize()
        if let panel { anchor = sessionAnchor(for: panel.frame) }
        guard let screen = panel?.screen ?? targetScreen() else { return }
        drag = DragSession(home: defaultAnchor(on: screen), screenFrame: screen.frame)
    }

    /// Release: snap home and forget the stored position, or remember where it was dropped.
    func endDrag() {
        let session = drag
        // Cleared before the snap, so `positionPanel`'s own move isn't read as more dragging.
        drag = nil
        dropGuides.hide()
        guard let panel, let session, session.moved else { return }
        guard session.armed else {
            core.settings.palettePosition = anchor
            return
        }
        anchor = session.home
        positionPanel(panel, collapsed: core.paletteCoordinator.paletteIsCollapsed)
        core.settings.palettePosition = nil
    }

    /// Keep the guides on the panel's screen, armed only while a release would snap it home.
    private func trackDrag(to moved: CGPoint) {
        guard var session = drag else { return }
        if let screen = panel?.screen, screen.frame != session.screenFrame {
            session.screenFrame = screen.frame
            session.home = defaultAnchor(on: screen)
        }
        session.armed = PalettePlacement.isSnapping(
            moved, to: session.home, within: Theme.Size.paletteSnapDistance)
        if session.moved {
            dropGuides.move(home: session.home, screenFrame: session.screenFrame)
            dropGuides.setArmed(session.armed)
        } else {
            session.moved = true
            dropGuides.show(
                home: session.home, screenFrame: session.screenFrame, armed: session.armed)
        }
        drag = session
    }

    // MARK: - Private

    private func ensurePanel(clipboard wantsClipboard: Bool) -> PalettePanel {
        if let panel, wantsClipboard == (panel === clipboardPanel) { return panel }
        switchingPanels = true
        cancelResize()
        let wasVisible = panel?.isVisible == true
        panel?.orderOut(nil)
        panel?.cancelClipboardEntrance()
        if wasVisible, panel === searchPanel, searchPanel != nil {
            preservedState = core.palette.snapshot()
            schedulePopToRoot()
        } else if wasVisible, panel === clipboardPanel, clipboardPanel != nil {
            scheduleClipboardReset()
        }
        let destination = wantsClipboard ? ensureClipboardPanel() : ensureSearchPanel()
        panel = destination
        clipboardScreenFrame = nil
        switchingPanels = false
        return destination
    }

    private func ensureClipboardPanel() -> PalettePanel {
        if let clipboardPanel { return clipboardPanel }
        let root = ClipboardPanelView()
            .environment(core)
            .environment(core.clipboardPalette)
            .environment(core.clipboardStore)
        let panel = PalettePanel(rootView: root)
        panel.title = "剪贴板"
        panel.delegate = self
        panel.paletteState = core.clipboardPalette
        panel.setHostedContent(panel.takeHostedContent(), bottomDocked: true)
        panel.onFieldEditorFocused = { [weak self] context in
            self?.core.inputSourceSwitcher.applySession(to: context)
        }
        panel.onCommandShortcut = { [weak self] event in
            self?.core.clipboardCoordinator.handleCommandShortcut(event) ?? false
        }
        clipboardPanel = panel
        return panel
    }

    private func ensureSearchPanel() -> PalettePanel {
        if let searchPanel { return searchPanel }
        let root = RootPaletteView()
            .environment(core)
            .environment(core.settings)
            .environment(core.palette)
            .environment(core.appIndex)
            .environment(core.clipboardStore)
            .environment(core.favorites)
            .environment(core.visibility)
            .environment(core.aliases)
            .environment(core.calcHistory)
            .environment(core.currencyRates)
            .environment(core.emojiIndex)
            .environment(core.frequentEmoji)
            .environment(core.fileSearch)
            .environment(core.runningApps)
            .environment(core.hotKeys)
            .environment(core.uninstall)
            .environment(core.quicklinks)
            .environment(core.quicklinkArguments)
            .environment(core.extensions)
            .environment(core.calendarStore)
            .environment(core.ossUploadHistory)
        let panel = PalettePanel(rootView: root)
        configurePanel(panel)
        searchPanel = panel
        return panel
    }

    private func configurePanel(_ panel: PalettePanel) {
        panel.delegate = self
        panel.paletteState = core.palette
        // The switch is scoped to the palette's own editing context, never applied globally.
        panel.onFieldEditorFocused = { [weak self] context in
            self?.core.inputSourceSwitcher.applySession(to: context)
        }
        // Backspace in an empty search backs out of a sub-screen to a fresh root.
        panel.onBareBackspace = { [weak self] in
            guard let core = self?.core, core.palette.mode != .launcher, core.palette.query.isEmpty
            else { return false }
            if core.palette.mode == .jsonEditor { return false }
            // The argument form steps back through the answers first, one key per field.
            if core.palette.mode == .quicklinkArguments,
                let previous = core.quicklinkArguments.retreat()
            {
                core.palette.query = previous
                core.palette.selection = 0
                return true
            }
            if core.palette.mode == .aiHistory {
                core.palette.prepare(mode: .ai)
                return true
            }
            if core.palette.mode == .ai, core.aiChatCoordinator.removeLastAttachment() {
                return true
            }
            core.palette.prepare(mode: .launcher)
            return true
        }
        // Handled at the panel: the field editor or a missing main menu eats these first.
        panel.onCommandShortcut = { [weak self] event in
            guard let self, !event.isARepeat else { return false }
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard modifiers.contains(.command) else { return false }
            let character = event.charactersIgnoringModifiers?.lowercased()
            if self.core.palette.mode == .jsonEditor, let character,
                self.core.jsonEditorCoordinator.handleCommandShortcut(
                    character, modifiers: modifiers)
            {
                return true
            }
            guard modifiers == .command else { return false }
            if self.core.palette.mode == .launcher || self.core.palette.mode == .clipboard,
                let index = FavoriteSlots.index(forKeyCode: event.keyCode)
            {
                self.core.palette.noteFavoriteSlot(index)
                return true
            }
            // Escape has no character, so it matches by key code.
            if Int(event.keyCode) == kVK_Escape {
                self.core.palette.prepare(mode: .launcher)
                return true
            }
            // Character chords, not key codes: Dvorak transposes the two.
            guard let character else { return false }
            switch character {
            case ",":
                self.core.settingsCoordinator.showSettings()
                return true
            // Pin. Swallowed on every screen, since ⌘. only ever means cancel to a search field.
            case ".":
                self.core.palette.notePinChord()
                return true
            case "w":
                self.core.paletteCoordinator.hidePalette()
                return true
            case "v":
                if self.core.palette.mode == .ossUpload {
                    self.core.ossUploadCoordinator.uploadPasteboardFiles()
                    return true
                }
                return self.core.palette.mode == .ai && self.core.aiChatCoordinator.attachPastedImage()
            default:
                return false
            }
        }
    }

    /// Resize to the given state, top edge anchored; applied even while hidden.
    func applyCollapsed(_ collapsed: Bool) {
        guard let panel, panel !== clipboardPanel else { return }
        positionPanel(panel, collapsed: collapsed, animated: panel.isVisible)
    }

    /// Size to height and place against the session anchor, so the list grows downward.
    private func positionPanel(_ panel: NSPanel, collapsed: Bool, animated: Bool = false) {
        if panel === clipboardPanel {
            guard let clipboardScreenFrame else { return }
            let frame = PalettePlacement.clipboardFrame(screenFrame: clipboardScreenFrame)
            guard panel.frame != frame else { return }
            panel.setFrame(frame, display: false)
            return
        }
        guard let anchor = resolveAnchor() else { return }
        let expandedHeight: CGFloat
        switch core.settings.componentHeight {
        case .low: expandedHeight = Theme.Size.panelHeight
        case .medium: expandedHeight = Theme.Size.panelMediumHeight
        case .high: expandedHeight = Theme.Size.panelHighHeight
        }
        let componentHeight = core.palette.mode == .jsonEditor ? Theme.Size.panelMediumHeight : expandedHeight
        let requestedHeight = collapsed ? Theme.Size.compactHeight : componentHeight
        let visibleFrame = NSScreen.screens.first {
            $0.visibleFrame.contains(CGPoint(x: anchor.x, y: anchor.y - 1))
        }?.visibleFrame ?? targetScreen()?.visibleFrame
        let frame = PalettePlacement.sizedFrame(
            anchor: anchor, width: Theme.Size.panelWidth,
            requestedHeight: requestedHeight, visibleFrame: visibleFrame)
        let shouldAnimate = animated && drag == nil && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if shouldAnimate, resizeTarget == frame { return }
        guard shouldAnimate, panel.frame != frame else {
            cancelResize()
            panel.setFrame(frame, display: true)
            return
        }
        let generation = UUID()
        resizeGeneration = generation
        resizeTarget = frame
        self.anchor = sessionAnchor(for: frame)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Theme.Duration.paletteResize
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.32, 0.72, 0, 1)
            panel.animator().setFrame(frame, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.resizeGeneration == generation else { return }
                self.resizeTarget = nil
            }
        }
    }

    private func sessionAnchor(for frame: CGRect) -> CGPoint {
        CGPoint(x: frame.minX, y: frame.maxY)
    }

    private func cancelResize() {
        guard let panel, resizeTarget != nil else { return }
        resizeGeneration = UUID()
        let frame = panel.frame
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            panel.animator().setFrame(frame, display: true)
        }
        resizeTarget = nil
    }

    /// The display to anchor to; never `NSScreen.main`, which follows the focused window either way.
    private func targetScreen() -> NSScreen? {
        core.settings.openOnCursorScreen ? NSScreen.underCursor : NSScreen.primary
    }

    /// The session anchor, cached until hide so both placements read one `visibleFrame`. A
    /// remembered drag outranks the display setting; the default is what it falls back to.
    private func resolveAnchor() -> CGPoint? {
        if let anchor { return anchor }
        let resolved = restoredAnchor() ?? targetScreen().map(defaultAnchor(on:))
        anchor = resolved
        return resolved
    }

    /// Where the last drag left it, unless no display still shows enough of the bar to grab.
    private func restoredAnchor() -> CGPoint? {
        guard let stored = core.settings.palettePosition else { return nil }
        return PalettePlacement.restored(
            stored,
            graspable: CGSize(width: Theme.Size.panelWidth, height: Theme.Size.compactHeight),
            visibleFrames: NSScreen.screens.map(\.visibleFrame),
            minimumVisible: Theme.Size.paletteMinimumVisible)
    }

    /// The untouched placement on one display; the summon path and the drop guides share it.
    private func defaultAnchor(on screen: NSScreen) -> CGPoint {
        PalettePlacement.defaultAnchor(
            in: screen.visibleFrame, width: Theme.Size.panelWidth,
            topMarginFraction: Theme.Size.paletteTopMarginFraction)
    }
}
