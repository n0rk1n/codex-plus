import CoreGraphics

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
    public static let tileIconSize = 48.0
    public static let tileProgressIndicatorSize = 16.0
    public static let batteryTileWidth = 92.0
    public static let codexDesktopTileWidth = 92.0
    public static let codexUsageTileWidth = 138.0
    public static let dailyTokensTileWidth = 184.0
    public static let tileSpacing = 12.0
    public static let tileReorderThreshold = 44.0
    public static let tileStripWidth = codexDesktopTileWidth + codexUsageTileWidth + dailyTokensTileWidth + (tileSpacing * 2)
    public static let minimumPanelWidth = tileStripWidth + (horizontalPadding * 2)

    public static func panelFrameFittingTileStrip(
        _ panelFrame: CGRect,
        in screenFrame: CGRect
    ) -> CGRect {
        let width = min(
            max(panelFrame.width, CGFloat(Self.minimumPanelWidth)),
            max(0, screenFrame.width)
        )
        guard width != panelFrame.width else {
            return panelFrame
        }

        let centeredX = panelFrame.midX - (width / 2)
        let x = min(
            max(centeredX, screenFrame.minX),
            screenFrame.maxX - width
        )

        return CGRect(
            x: x,
            y: panelFrame.minY,
            width: width,
            height: panelFrame.height
        )
    }

    public static func shouldMoveWindowFromMouseDown(
        at point: CGPoint,
        panelBounds: CGRect,
        verticalOrigin: PanelCoordinateOrigin
    ) -> Bool {
        promptDragRect(in: panelBounds, verticalOrigin: verticalOrigin).containsInclusively(point)
    }

    public static func tileStripRect(
        in panelBounds: CGRect,
        verticalOrigin: PanelCoordinateOrigin
    ) -> CGRect {
        let horizontalPadding = CGFloat(Self.horizontalPadding)
        let topPadding = CGFloat(Self.topPadding)
        let tileStripWidth = CGFloat(Self.tileStripWidth)
        let tileStripHeight = CGFloat(Self.tileStripHeight)
        let contentWidth = max(0, panelBounds.width - (horizontalPadding * 2))
        let stripWidth = min(tileStripWidth, contentWidth)
        let stripHeight = min(tileStripHeight, max(0, panelBounds.height - topPadding))
        let x = panelBounds.minX + horizontalPadding + max(0, (contentWidth - stripWidth) / 2)

        let y: CGFloat
        switch verticalOrigin {
        case .top:
            y = panelBounds.minY + topPadding
        case .bottom:
            y = panelBounds.minY + panelBounds.height - topPadding - stripHeight
        }

        return CGRect(x: x, y: y, width: stripWidth, height: stripHeight)
    }

    public static func promptDragRect(
        in panelBounds: CGRect,
        verticalOrigin: PanelCoordinateOrigin
    ) -> CGRect {
        let horizontalPadding = CGFloat(Self.horizontalPadding)
        let topPadding = CGFloat(Self.topPadding)
        let bottomPadding = CGFloat(Self.bottomPadding)
        let verticalSpacing = CGFloat(Self.verticalSpacing)
        let tileStripHeight = CGFloat(Self.tileStripHeight)
        let yFromTop = topPadding + tileStripHeight + verticalSpacing
        let height = max(0, panelBounds.height - yFromTop - bottomPadding)

        let y: CGFloat
        switch verticalOrigin {
        case .top:
            y = panelBounds.minY + yFromTop
        case .bottom:
            y = panelBounds.minY + bottomPadding
        }

        return CGRect(
            x: panelBounds.minX + horizontalPadding,
            y: y,
            width: max(0, panelBounds.width - (horizontalPadding * 2)),
            height: height
        )
    }
}

private extension CGRect {
    func containsInclusively(_ point: CGPoint) -> Bool {
        point.x >= minX &&
            point.x <= maxX &&
            point.y >= minY &&
            point.y <= maxY
    }
}
