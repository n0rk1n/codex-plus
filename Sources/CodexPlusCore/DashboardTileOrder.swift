import Foundation

public enum DashboardTile: String, CaseIterable, Equatable, Hashable, Sendable {
    case battery
    case codexDesktop
    case codexUsage
    case dailyTokens
}

public struct DashboardTileOrder: Equatable, Sendable {
    public static let defaultTiles: [DashboardTile] = [.codexDesktop, .codexUsage, .dailyTokens]

    public let tiles: [DashboardTile]

    public init(rawValue: String?) {
        guard let rawValue else {
            self.tiles = Self.defaultTiles
            return
        }

        let parsedTiles = rawValue
            .split(separator: ",")
            .compactMap { DashboardTile(rawValue: String($0)) }

        self.tiles = Self.validated(parsedTiles)
    }

    public init(tiles: [DashboardTile]) {
        self.tiles = Self.validated(tiles)
    }

    public var rawValue: String {
        tiles.map(\.rawValue).joined(separator: ",")
    }

    public func swapping(_ source: DashboardTile, with target: DashboardTile) -> DashboardTileOrder {
        guard source != target,
              let sourceIndex = tiles.firstIndex(of: source),
              let targetIndex = tiles.firstIndex(of: target)
        else {
            return self
        }

        var nextTiles = tiles
        nextTiles.swapAt(sourceIndex, targetIndex)
        return DashboardTileOrder(tiles: nextTiles)
    }

    public func previewingDrag(
        _ source: DashboardTile,
        translationWidth: Double,
        threshold: Double
    ) -> DashboardTileOrder {
        guard abs(translationWidth) >= abs(threshold),
              let sourceIndex = tiles.firstIndex(of: source)
        else {
            return self
        }

        let targetIndex = previewTargetIndex(
            from: sourceIndex,
            translationWidth: translationWidth
        )
        guard targetIndex != sourceIndex else {
            return self
        }

        var nextTiles = tiles
        let movedTile = nextTiles.remove(at: sourceIndex)
        nextTiles.insert(movedTile, at: targetIndex)
        return DashboardTileOrder(tiles: nextTiles)
    }

    private func previewTargetIndex(from sourceIndex: Int, translationWidth: Double) -> Int {
        let placements = DashboardTileLayoutPolicy.placements(for: tiles)
        guard let sourcePlacement = placements.first(where: { $0.tile == tiles[sourceIndex] }) else {
            return sourceIndex
        }

        let draggedCenterX = sourcePlacement.centerX + translationWidth

        if translationWidth > 0 {
            var targetIndex = min(sourceIndex + 1, tiles.count - 1)

            guard targetIndex != sourceIndex else {
                return sourceIndex
            }

            for index in (sourceIndex + 2)..<tiles.count {
                let boundary = (placements[index - 1].centerX + placements[index].centerX) / 2
                if draggedCenterX >= boundary {
                    targetIndex = index
                }
            }

            return targetIndex
        }

        var targetIndex = max(sourceIndex - 1, 0)

        guard targetIndex != sourceIndex else {
            return sourceIndex
        }

        for index in stride(from: sourceIndex - 2, through: 0, by: -1) {
            let boundary = (placements[index].centerX + placements[index + 1].centerX) / 2
            if draggedCenterX <= boundary {
                targetIndex = index
            }
        }

        return targetIndex
    }

    public func layoutTiles(excludingDragged draggedTile: DashboardTile?) -> [DashboardTile] {
        guard let draggedTile else {
            return tiles
        }

        return tiles.filter { $0 != draggedTile }
    }

    private static func validated(_ tiles: [DashboardTile]) -> [DashboardTile] {
        var migratedTiles: [DashboardTile] = []

        for tile in tiles {
            let migratedTile = tile == .battery ? DashboardTile.codexDesktop : tile
            guard defaultTiles.contains(migratedTile),
                  !migratedTiles.contains(migratedTile)
            else {
                continue
            }

            migratedTiles.append(migratedTile)
        }

        guard !migratedTiles.isEmpty else {
            return defaultTiles
        }

        return migratedTiles + defaultTiles.filter { !migratedTiles.contains($0) }
    }
}
