import Foundation

public enum DashboardTile: String, CaseIterable, Equatable, Hashable, Sendable {
    case battery
    case codexUsage
}

public struct DashboardTileOrder: Equatable, Sendable {
    public static let defaultTiles: [DashboardTile] = [.battery, .codexUsage]

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

    public func layoutTiles(excludingDragged draggedTile: DashboardTile?) -> [DashboardTile] {
        guard let draggedTile else {
            return tiles
        }

        return tiles.filter { $0 != draggedTile }
    }

    private static func validated(_ tiles: [DashboardTile]) -> [DashboardTile] {
        guard tiles.count == defaultTiles.count,
              Set(tiles) == Set(defaultTiles)
        else {
            return defaultTiles
        }

        return tiles
    }
}
