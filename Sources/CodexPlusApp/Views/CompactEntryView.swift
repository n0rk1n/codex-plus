import CodexPlusCore
import SwiftUI

struct CompactEntryView: View {
    let batteryStatus: BatteryStatus
    let codexUsageStatus: CodexUsageStatus
    let dailyTokenStatus: DailyTokenStatus
    let onSubmit: (String) -> Void

    @FocusState private var isPromptFocused: Bool
    @AppStorage("dashboard.tileOrder") private var dashboardTileOrderRaw = DashboardTileOrder(rawValue: nil).rawValue
    @State private var prompt = ""
    @State private var draggedTile: DashboardTile?
    @State private var dragTranslation: CGSize = .zero

    private let reorderThreshold: CGFloat = 44
    private let tileRowHeight: CGFloat = 92

    var body: some View {
        VStack(spacing: 14) {
            GeometryReader { geometry in
                ZStack {
                    ForEach(dashboardTileOrder.tiles, id: \.self) { tile in
                        tileView(for: tile)
                            .position(
                                x: (geometry.size.width / 2) + tileOffset(for: tile),
                                y: tileRowHeight / 2
                            )
                            .scaleEffect(draggedTile == tile ? 1.03 : 1)
                            .opacity(draggedTile == tile ? 0.92 : 1)
                            .zIndex(draggedTile == tile ? 1 : 0)
                            .contentShape(Rectangle())
                    }
                }
                .contentShape(Rectangle())
                .highPriorityGesture(rowDragGesture(rowWidth: geometry.size.width))
            }
            .frame(height: tileRowHeight)
            .animation(.snappy(duration: 0.18), value: draggedTile)
            .animation(.snappy(duration: 0.18), value: dashboardTileOrderRaw)

            LiquidGlassContainer(cornerRadius: 24) {
                TextField("Ask Codex...", text: $prompt, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .lineLimit(1...3)
                    .focused($isPromptFocused)
                    .onSubmit(submitPrompt)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
            }
        }
        .padding(18)
        .onAppear {
            isPromptFocused = true
        }
    }

    private func tileOffset(for tile: DashboardTile) -> CGFloat {
        if draggedTile == tile {
            return placementOffset(for: tile, in: dashboardTileOrder.tiles) + dragTranslation.width
        }

        return placementOffset(
            for: tile,
            in: dashboardTileOrder.layoutTiles(excludingDragged: draggedTile)
        )
    }

    private func placementOffset(for tile: DashboardTile, in tiles: [DashboardTile]) -> CGFloat {
        let placement = DashboardTileLayoutPolicy.placements(for: tiles).first { $0.tile == tile }
        return CGFloat(placement?.centerX ?? 0)
    }

    private var dashboardTileOrder: DashboardTileOrder {
        DashboardTileOrder(rawValue: dashboardTileOrderRaw)
    }

    @ViewBuilder
    private func tileView(for tile: DashboardTile) -> some View {
        switch tile {
        case .battery:
            BatteryTileView(status: batteryStatus)
        case .codexUsage:
            CodexUsageRingTileView(status: codexUsageStatus)
        case .dailyTokens:
            DailyTokenTileView(status: dailyTokenStatus)
        }
    }

    private func rowDragGesture(rowWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let sourceTile = draggedTile ?? DashboardTileLayoutPolicy.tile(
                    atX: Double(value.startLocation.x),
                    rowWidth: Double(rowWidth),
                    tiles: dashboardTileOrder.tiles
                )

                guard let sourceTile else {
                    return
                }

                draggedTile = sourceTile
                dragTranslation = CGSize(width: value.translation.width, height: 0)
            }
            .onEnded { value in
                guard let sourceTile = draggedTile else {
                    return
                }

                reorderIfNeeded(tile: sourceTile, translationWidth: value.translation.width)
                draggedTile = nil
                dragTranslation = .zero
            }
    }

    private func reorderIfNeeded(tile: DashboardTile, translationWidth: CGFloat) {
        guard abs(translationWidth) >= reorderThreshold else {
            return
        }

        let order = dashboardTileOrder
        guard let tileIndex = order.tiles.firstIndex(of: tile) else {
            return
        }

        let targetIndex = translationWidth > 0 ? tileIndex + 1 : tileIndex - 1
        guard order.tiles.indices.contains(targetIndex) else {
            return
        }

        let nextOrder = order.swapping(tile, with: order.tiles[targetIndex])
        dashboardTileOrderRaw = nextOrder.rawValue
    }

    private func submitPrompt() {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            return
        }

        onSubmit(trimmedPrompt)
        prompt = ""
    }
}
