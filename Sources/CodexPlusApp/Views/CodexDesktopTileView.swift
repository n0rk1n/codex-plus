import AppKit
import CodexPlusCore
import SwiftUI

struct CodexDesktopTileView: View {
    let onOpen: () -> Void

    var body: some View {
        CodexButton(rule: .cardRounded(cornerRadius: CodexRadius.card), accessibilityLabel: "Open Codex Desktop", action: onOpen) {
            LiquidGlassContainer(cornerRadius: CodexRadius.card) {
                image
                    .frame(width: CGFloat(CompactDashboardTileDragPolicy.tileIconSize), height: CGFloat(CompactDashboardTileDragPolicy.tileIconSize))
                    .frame(width: CGFloat(CompactDashboardTileDragPolicy.codexDesktopTileWidth), height: CGFloat(CompactDashboardTileDragPolicy.tileStripHeight))
            }
        }
    }

    @ViewBuilder
    private var image: some View {
        if let iconImage = CodexDesktopLauncher.iconImage {
            Image(nsImage: iconImage)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        } else {
            Image(systemName: "app.fill")
                .font(CodexTypography.desktopTileFallbackSymbol)
                .foregroundStyle(.secondary)
        }
    }
}
