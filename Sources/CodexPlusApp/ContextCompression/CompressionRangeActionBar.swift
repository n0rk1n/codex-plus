import CodexPlusCore
import SwiftUI

struct CompressionRangeActionBar: View {
    let selectedCount: Int
    let canEditSegment: Bool
    let onEdit: () -> Void
    let onDefaultCompress: () -> Void
    let onExclude: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Label("\(selectedCount) 轮", systemImage: "selection.pin.in.out")
                .font(CodexTypography.statusBar)
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            CodexButton(rule: .formHeaderCapsule, isDisabled: !canEditSegment, help: "编辑单轮中的用户段或 AI 段", action: onEdit) {
                Label("编辑", systemImage: "pencil")
                    .labelStyle(.titleAndIcon)
            }

            CodexButton(rule: .formHeaderCapsule, help: "使用默认提示词压缩选中轮次", action: onDefaultCompress) {
                Label("默认压缩", systemImage: "arrow.down.right.and.arrow.up.left")
                    .labelStyle(.titleAndIcon)
            }

            CodexButton(rule: .formHeaderCapsule, role: .destructive, help: "排除选中的单轮模型上下文", action: onExclude) {
                Label("排除", systemImage: "eye.slash")
                    .labelStyle(.titleAndIcon)
            }

            CodexButton(rule: .toolbarIconCircle, help: "不压缩", action: onClear) {
                Image(systemName: "xmark")
            }
        }
        .padding(.horizontal, CodexSpacing.contentInline)
        .padding(.vertical, CodexSpacing.tightVertical)
        .background(.thinMaterial)
    }
}
