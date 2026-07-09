import CodexPlusCore
import SwiftUI

struct ContextBudgetBadge: View {
    let snapshot: ContextBudgetSnapshot

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)

            Text(label)
                .font(CodexTypography.statusBarValue)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(.thinMaterial, in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .stroke(tint.opacity(0.28), lineWidth: 0.8)
        }
        .help(helpText)
    }

    private var label: String {
        switch snapshot.state {
        case .safe:
            return "\(percentText) 安全"
        case .notice:
            return "\(percentText) 注意"
        case .warning:
            return "\(percentText) 接近上限"
        case .hardLimit:
            return "需要压缩"
        case .unknown:
            return "预算未知"
        }
    }

    private var percentText: String {
        "\(Int((snapshot.usageRatio * 100).rounded()))%"
    }

    private var helpText: String {
        "\(snapshot.assembledInputTokens)/\(snapshot.usableInputTokens) usable input tokens"
    }

    private var tint: Color {
        switch snapshot.state {
        case .safe:
            return CodexColors.stateCompleted
        case .notice:
            return .blue
        case .warning:
            return CodexColors.stateWarning
        case .hardLimit:
            return CodexColors.stateFailed
        case .unknown:
            return .secondary
        }
    }
}
