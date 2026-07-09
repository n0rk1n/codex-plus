import CodexPlusCore
import SwiftUI

struct CompressionRangeMarkerView: View {
    let boundary: CompressionBoundaryPresentation
    let status: CompressionStatusPresentation?
    let joinedRelationship: CompressionJoinedRelationshipPresentation?
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isShowingPopover = false

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(tint)
                .frame(width: 3, height: 22)

            CodexButton(rule: .rowRounded(cornerRadius: 12), help: status?.label ?? fallbackLabel, action: {
                onSelect()
                isShowingPopover.toggle()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: iconName)
                        .font(CodexTypography.caption2Medium)

                    Text(status?.label ?? fallbackLabel)
                        .font(CodexTypography.compactBadge)
                        .lineLimit(1)

                    if let joinedRelationship, joinedRelationship.relatedRoundIDs.count > 1 {
                        Image(systemName: "link")
                            .font(CodexTypography.caption2Medium)
                            .accessibilityLabel("拼接关系")
                    }
                }
                .foregroundStyle(tint)
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(.thinMaterial, in: Capsule(style: .continuous))
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(isSelected ? tint.opacity(0.75) : tint.opacity(0.28), lineWidth: isSelected ? 1.2 : 0.8)
                }
            }
            .popover(isPresented: $isShowingPopover, arrowEdge: .bottom) {
                CompressionStatusPopover(
                    boundary: boundary,
                    status: status,
                    joinedRelationship: joinedRelationship,
                    onShowHistory: {
                        onSelect()
                        isShowingPopover = false
                    }
                )
            }
        }
        .padding(.leading, 28)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var fallbackLabel: String {
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

    private var iconName: String {
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
