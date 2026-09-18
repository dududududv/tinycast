import CoreGraphics

/// Where the palette's top-left corner sits. Pure, with every screen fact injected, so the window
/// controller holds no placement maths of its own and this stays testable off a display.
enum PalettePlacement {
    static func clipboardFrame(screenFrame: CGRect) -> CGRect {
        CGRect(x: screenFrame.minX, y: screenFrame.minY, width: screenFrame.width,
               height: min(Theme.Size.clipboardPanelHeight, screenFrame.height))
    }

    static func footerHeight(panelHeight: CGFloat, compactHeight: CGFloat, fullHeight: CGFloat) -> CGFloat {
        min(fullHeight, max(0, panelHeight - compactHeight))
    }

    static func sizedFrame(
        anchor: CGPoint, width: CGFloat, requestedHeight: CGFloat, visibleFrame: CGRect?
    ) -> CGRect {
        let height = min(requestedHeight, visibleFrame?.height ?? requestedHeight)
        let bottom = visibleFrame.map {
            max($0.minY, min(anchor.y - height, $0.maxY - height))
        } ?? anchor.y - height
        return CGRect(x: anchor.x, y: bottom, width: width, height: height)
    }

    /// The untouched placement: centred, top edge a fraction of the way down, growing downward.
    static func defaultAnchor(
        in visibleFrame: CGRect, width: CGFloat, topMarginFraction: CGFloat
    )
        -> CGPoint
    {
        CGPoint(
            x: visibleFrame.midX - width / 2,
            y: visibleFrame.maxY - visibleFrame.height * topMarginFraction)
    }

    /// A stored anchor, or nil once no display shows enough of the compact bar to grab it back —
    /// which is what a disconnected screen or a resolution change leaves behind.
    static func restored(
        _ stored: CGPoint, graspable: CGSize, visibleFrames: [CGRect], minimumVisible: CGFloat
    ) -> CGPoint? {
        let bar = CGRect(
            x: stored.x, y: stored.y - graspable.height,
            width: graspable.width, height: graspable.height)
        let reachable = visibleFrames.contains { screen in
            let shown = screen.intersection(bar)
            return !shown.isNull && shown.width >= minimumVisible && shown.height >= minimumVisible
        }
        return reachable ? stored : nil
    }

    /// Near enough to the default placement that releasing the drag should drop it home.
    static func isSnapping(_ anchor: CGPoint, to home: CGPoint, within distance: CGFloat) -> Bool {
        abs(anchor.x - home.x) <= distance && abs(anchor.y - home.y) <= distance
    }
}
