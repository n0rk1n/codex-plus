public enum PanelCoordinateOrigin: Sendable {
    case top
    case bottom
}

public enum CompactDashboardTileDragPolicy {
    public static let horizontalPadding = 18.0
    public static let topPadding = 18.0
    public static let bottomPadding = 18.0
    public static let verticalSpacing = 14.0
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
        promptDragRect(in: panelBounds, verticalOrigin: verticalOrigin).contains(point)
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

    public static func promptDragRect(
        in panelBounds: ScreenRect,
        verticalOrigin: PanelCoordinateOrigin
    ) -> ScreenRect {
        let yFromTop = topPadding + tileStripHeight + verticalSpacing
        let height = max(0, panelBounds.height - yFromTop - bottomPadding)

        let y: Double
        switch verticalOrigin {
        case .top:
            y = panelBounds.y + yFromTop
        case .bottom:
            y = panelBounds.y + bottomPadding
        }

        return ScreenRect(
            x: panelBounds.x + horizontalPadding,
            y: y,
            width: max(0, panelBounds.width - (horizontalPadding * 2)),
            height: height
        )
    }
}
