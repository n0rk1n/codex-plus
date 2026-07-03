public enum CompactPanelSnapPolicy {
    public static let defaultSnapDistance = 24.0

    public static func snappedFrame(
        for panelFrame: ScreenRect,
        in screenFrame: ScreenRect,
        snapDistance: Double = defaultSnapDistance
    ) -> ScreenRect {
        let screenMidX = screenFrame.x + (screenFrame.width / 2)
        let panelMidX = panelFrame.x + (panelFrame.width / 2)

        guard abs(panelMidX - screenMidX) <= snapDistance else {
            return panelFrame
        }

        return ScreenRect(
            x: screenMidX - (panelFrame.width / 2),
            y: panelFrame.y,
            width: panelFrame.width,
            height: panelFrame.height
        )
    }
}
