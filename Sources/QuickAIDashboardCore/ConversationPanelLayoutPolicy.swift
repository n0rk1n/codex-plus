public enum ConversationPanelLayoutPolicy {
    public static let preferredWidthRatio = 0.56
    public static let preferredHeightRatio = 0.82
    public static let minWidth = 520.0
    public static let maxWidth = 860.0
    public static let minHeight = 560.0
    public static let maxHeight = 920.0
    public static let minimumMargin = 24.0

    public static func initialCenteredFrame(in screenFrame: ScreenRect) -> ScreenRect {
        let availableWidth = max(0, screenFrame.width - (minimumMargin * 2))
        let availableHeight = max(0, screenFrame.height - (minimumMargin * 2))
        let width = min(availableWidth, clamped(screenFrame.width * preferredWidthRatio, minWidth, maxWidth)).rounded()
        let height = min(availableHeight, clamped(screenFrame.height * preferredHeightRatio, minHeight, maxHeight)).rounded()

        return ScreenRect(
            x: (screenFrame.x + ((screenFrame.width - width) / 2)).rounded(),
            y: (screenFrame.y + ((screenFrame.height - height) / 2)).rounded(),
            width: width,
            height: height
        )
    }

    private static func clamped(_ value: Double, _ lowerBound: Double, _ upperBound: Double) -> Double {
        min(max(value, lowerBound), upperBound)
    }
}
