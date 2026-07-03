public struct DashboardTilePlacement: Equatable, Sendable {
    public let tile: DashboardTile
    public let centerX: Double
    public let width: Double

    public init(tile: DashboardTile, centerX: Double, width: Double) {
        self.tile = tile
        self.centerX = centerX
        self.width = width
    }
}

public enum DashboardTileLayoutPolicy {
    public static let defaultSpacing = CompactDashboardTileDragPolicy.tileSpacing

    public static func placements(
        for tiles: [DashboardTile],
        spacing: Double = defaultSpacing
    ) -> [DashboardTilePlacement] {
        let totalWidth = tiles.reduce(0) { partialResult, tile in
            partialResult + width(for: tile)
        } + Double(max(0, tiles.count - 1)) * spacing
        let leadingX = -totalWidth / 2

        var nextX = leadingX
        return tiles.map { tile in
            let width = width(for: tile)
            let placement = DashboardTilePlacement(
                tile: tile,
                centerX: nextX + (width / 2),
                width: width
            )
            nextX += width + spacing
            return placement
        }
    }

    public static func width(for tile: DashboardTile) -> Double {
        switch tile {
        case .battery:
            return CompactDashboardTileDragPolicy.batteryTileWidth
        case .codexUsage:
            return CompactDashboardTileDragPolicy.codexUsageTileWidth
        }
    }

    public static func tile(atX x: Double, rowWidth: Double, tiles: [DashboardTile]) -> DashboardTile? {
        let rowMidX = rowWidth / 2

        for placement in placements(for: tiles) {
            let centerX = rowMidX + placement.centerX
            let minX = centerX - (placement.width / 2)
            let maxX = centerX + (placement.width / 2)

            if x >= minX && x <= maxX {
                return placement.tile
            }
        }

        return nil
    }
}
