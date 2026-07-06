import CodexPlusCore
import SwiftUI

struct WorkbenchStatusBarView: View {
    let state: WorkbenchStatusBarState

    var body: some View {
        HStack(spacing: 18) {
            Spacer(minLength: 0)

            Text("Codex CLI 可用")
            Text("SQLite 已连接")
            Text("归档索引 待更新")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }
}
