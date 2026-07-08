import SwiftUI

struct WorkbenchLauncherView: View {
    let onActivate: () -> Void

    var body: some View {
        CodexButton(
            rule: .toolbarIconCircle,
            help: "打开 Codex Plus",
            accessibilityLabel: "打开 Codex Plus",
            action: onActivate
        ) {
            ZStack {
                Circle()
                    .fill(CodexColors.launcherSurface)

                Image(systemName: "command")
                    .font(CodexTypography.launcherSymbol)
                    .foregroundStyle(CodexColors.launcherSymbol)
                    .blendMode(.difference)
            }
            .frame(width: WorkbenchLauncherMetrics.sphereSize, height: WorkbenchLauncherMetrics.sphereSize)
        }
        .padding((WorkbenchLauncherMetrics.panelSize - WorkbenchLauncherMetrics.sphereSize) / 2)
    }
}
