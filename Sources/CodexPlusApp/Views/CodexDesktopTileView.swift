import AppKit
import SwiftUI

struct CodexDesktopTileView: View {
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            LiquidGlassContainer(cornerRadius: 22) {
                image
                    .frame(width: 48, height: 48)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, minHeight: 66)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open Codex Desktop")
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
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}
