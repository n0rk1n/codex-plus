import CodexPlusCore
import SwiftUI

struct CompressionStatusPopover: View {
    let boundary: CompressionBoundaryPresentation
    let status: CompressionStatusPresentation?
    let joinedRelationship: CompressionJoinedRelationshipPresentation?
    let onShowHistory: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: symbolName)
                    .font(CodexTypography.menuPrimary)
                    .foregroundStyle(tint)

                VStack(alignment: .leading, spacing: 2) {
                    Text(status?.label ?? title)
                        .font(CodexTypography.statusBar)

                    Text(rangeText)
                        .font(CodexTypography.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if let joinedRelationship, joinedRelationship.relatedRoundIDs.count > 1 {
                Label("关联 \(joinedRelationship.relatedRoundIDs.count) 轮相邻对话", systemImage: "link")
                    .font(CodexTypography.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()
                .overlay(CodexColors.surfaceDivider)

            CodexButton(rule: .inlineTextLink, action: onShowHistory) {
                Text("查看完整历史")
                    .font(CodexTypography.statusBar)
                    .foregroundStyle(.primary)
            }
        }
        .padding(14)
        .frame(width: 260, alignment: .leading)
    }

    private var title: String {
        switch boundary.kind {
        case .edited:
            return "已修订"
        case .compressed:
            return "已压缩"
        case .joined:
            return "拼接压缩"
        case .excluded:
            return "已排除模型上下文"
        case .failed:
            return "压缩失败"
        }
    }

    private var rangeText: String {
        if boundary.startRoundID == boundary.endRoundID {
            return "单轮对话"
        }
        return "多轮拼接范围"
    }

    private var symbolName: String {
        switch boundary.kind {
        case .edited:
            return "pencil.line"
        case .compressed:
            return "arrow.down.right.and.arrow.up.left"
        case .joined:
            return "point.3.connected.trianglepath.dotted"
        case .excluded:
            return "eye.slash"
        case .failed:
            return "exclamationmark.triangle"
        }
    }

    private var tint: Color {
        switch boundary.kind {
        case .edited:
            return .blue
        case .compressed:
            return .teal
        case .joined:
            return .cyan
        case .excluded:
            return .secondary
        case .failed:
            return CodexColors.stateWarning
        }
    }
}
