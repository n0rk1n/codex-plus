import CoreGraphics

public enum CompactPanelSnapPolicy {
    public static let defaultSnapDistance = 24.0

    public static func snappedFrame(
        for panelFrame: CGRect,
        in screenFrame: CGRect,
        snapDistance: Double = defaultSnapDistance
    ) -> CGRect {
        let screenMidX = screenFrame.midX
        let panelMidX = panelFrame.midX

        guard abs(panelMidX - screenMidX) <= CGFloat(snapDistance) else {
            return panelFrame
        }

        return CGRect(
            x: screenMidX - (panelFrame.width / 2),
            y: panelFrame.minY,
            width: panelFrame.width,
            height: panelFrame.height
        )
    }
}
