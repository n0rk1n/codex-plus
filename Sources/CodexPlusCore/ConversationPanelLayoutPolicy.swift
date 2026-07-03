import CoreGraphics

public enum ConversationPanelLayoutPolicy {
    public static let preferredWidthRatio = 0.56
    public static let preferredHeightRatio = 0.82
    public static let minWidth = 520.0
    public static let maxWidth = 860.0
    public static let minHeight = 560.0
    public static let maxHeight = 920.0
    public static let minimumMargin = 24.0

    public static func initialCenteredFrame(in screenFrame: CGRect) -> CGRect {
        let minimumMargin = CGFloat(Self.minimumMargin)
        let availableWidth = max(0, screenFrame.width - (minimumMargin * 2))
        let availableHeight = max(0, screenFrame.height - (minimumMargin * 2))
        let width = min(
            availableWidth,
            clamped(
                screenFrame.width * CGFloat(preferredWidthRatio),
                CGFloat(minWidth),
                CGFloat(maxWidth)
            )
        ).rounded()
        let height = min(
            availableHeight,
            clamped(
                screenFrame.height * CGFloat(preferredHeightRatio),
                CGFloat(minHeight),
                CGFloat(maxHeight)
            )
        ).rounded()

        return CGRect(
            x: (screenFrame.minX + ((screenFrame.width - width) / 2)).rounded(),
            y: (screenFrame.minY + ((screenFrame.height - height) / 2)).rounded(),
            width: width,
            height: height
        )
    }

    private static func clamped(_ value: CGFloat, _ lowerBound: CGFloat, _ upperBound: CGFloat) -> CGFloat {
        min(max(value, lowerBound), upperBound)
    }
}
