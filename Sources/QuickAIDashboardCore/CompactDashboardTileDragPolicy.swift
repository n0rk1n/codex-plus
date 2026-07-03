public enum PanelCoordinateOrigin: Sendable {
    case top
    case bottom
}

public enum CompactDashboardTileDragPolicy {
    public static let horizontalPadding = 18.0
    public static let topPadding = 18.0
    public static let tileStripHeight = 92.0
    public static let batteryTileWidth = 92.0
    public static let codexUsageTileWidth = 138.0
    public static let tileSpacing = 12.0
    public static let tileStripWidth = batteryTileWidth + codexUsageTileWidth + tileSpacing

    public static func shouldMoveWindowFromMouseDown(
        at point: ScreenPoint,
        panelBounds: ScreenRect,
        verticalOrigin: PanelCoordinateOrigin
    ) -> Bool {
        !tileStripRect(in: panelBounds, verticalOrigin: verticalOrigin).contains(point)
    }

    public static func tileStripRect(
        in panelBounds: ScreenRect,
        verticalOrigin: PanelCoordinateOrigin
    ) -> ScreenRect {
        let contentWidth = max(0, panelBounds.width - (horizontalPadding * 2))
        let stripWidth = min(tileStripWidth, contentWidth)
        let stripHeight = min(tileStripHeight, max(0, panelBounds.height - topPadding))
        let x = panelBounds.x + horizontalPadding + max(0, (contentWidth - stripWidth) / 2)

        let y: Double
        switch verticalOrigin {
        case .top:
            y = panelBounds.y + topPadding
        case .bottom:
            y = panelBounds.y + panelBounds.height - topPadding - stripHeight
        }

        return ScreenRect(x: x, y: y, width: stripWidth, height: stripHeight)
    }
}
