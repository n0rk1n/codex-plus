import SwiftUI

struct WorkbenchLauncherView: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(surfaceTintColor)

            Image(systemName: "command")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(symbolColor)
                .blendMode(.difference)
        }
        .frame(width: WorkbenchLauncherMetrics.sphereSize, height: WorkbenchLauncherMetrics.sphereSize)
        .glassEffect(.regular, in: Circle())
        .compositingGroup()
        .mask(Circle())
        .codexCircularButtonHitArea()
        .help("打开 Codex Plus")
        .accessibilityLabel("打开 Codex Plus")
        .accessibilityAddTraits(.isButton)
        .padding((WorkbenchLauncherMetrics.panelSize - WorkbenchLauncherMetrics.sphereSize) / 2)
    }

    private var symbolColor: Color {
        Color.white
    }

    private var surfaceTintColor: Color {
        Color.white.opacity(0.06)
    }
}
