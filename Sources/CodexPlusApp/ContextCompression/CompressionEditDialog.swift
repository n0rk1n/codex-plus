import CodexPlusCore
import SwiftUI

struct CompressionEditDialog: View {
    let roundID: UUID
    let initialText: String
    let onCancel: () -> Void
    let onSave: (CompressionSegmentKind, String) -> Void

    @State private var segmentKind: CompressionSegmentKind = .assistant
    @State private var text: String

    init(
        roundID: UUID,
        initialText: String,
        onCancel: @escaping () -> Void,
        onSave: @escaping (CompressionSegmentKind, String) -> Void
    ) {
        self.roundID = roundID
        self.initialText = initialText
        self.onCancel = onCancel
        self.onSave = onSave
        _text = State(initialValue: initialText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("编辑压缩版本")
                    .font(CodexTypography.sectionTitle)

                Spacer(minLength: 8)

                CodexPicker(rule: .segmentedFilter, title: "", selection: $segmentKind) {
                    Text("用户").tag(CompressionSegmentKind.user)
                    Text("AI").tag(CompressionSegmentKind.assistant)
                }
                .frame(width: 132)
            }

            AppMultilineTextEditor(
                text: $text,
                fontSize: 14
            )
            .frame(minHeight: 180)
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(CodexColors.surfaceStroke, lineWidth: 1)
            }

            HStack(spacing: 8) {
                Spacer(minLength: 0)

                CodexButton(rule: .formFooterCapsule, action: onCancel) {
                    Text("取消")
                }

                CodexButton(rule: .formFooterCapsule, action: {
                    onSave(segmentKind, text)
                }) {
                    Text("保存")
                }
            }
        }
        .padding(18)
        .frame(width: 520)
    }
}
