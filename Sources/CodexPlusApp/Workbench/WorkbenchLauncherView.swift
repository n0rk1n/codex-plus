import SwiftUI

struct WorkbenchLauncherView: View {
    var body: some View {
        CodexButton(
            rule: .toolbarIconCircle,
            help: "打开 Codex Plus",
            accessibilityLabel: "打开 Codex Plus",
            action: {}
        ) {
            ZStack {
                Circle()
                    .fill(surfaceTintColor)

                Image(systemName: "command")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(symbolColor)
                    .blendMode(.difference)
            }
            .frame(width: WorkbenchLauncherMetrics.sphereSize, height: WorkbenchLauncherMetrics.sphereSize)
        }
        .padding((WorkbenchLauncherMetrics.panelSize - WorkbenchLauncherMetrics.sphereSize) / 2)
    }

    private var symbolColor: Color {
        Color.white
    }

    private var surfaceTintColor: Color {
        Color.white.opacity(0.06)
    }
}
