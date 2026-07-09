import AppKit
import SwiftUI

struct ModelInputPreviewSheet: View {
    let text: String
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text("模型输入预览")
                    .font(CodexTypography.sectionTitle)

                Spacer(minLength: 8)

                CodexButton(rule: .formHeaderCapsule, action: copyText) {
                    Label("复制", systemImage: "doc.on.doc")
                        .labelStyle(.titleAndIcon)
                }

                CodexButton(rule: .toolbarIconCircle, help: "关闭", action: onClose) {
                    Image(systemName: "xmark")
                }
            }

            ScrollView {
                Text(text)
                    .font(CodexTypography.messageBody)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(minHeight: 360)
            .background(CodexColors.surfaceSubtleWeak, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(CodexColors.surfaceStroke, lineWidth: 1)
            }
        }
        .padding(18)
        .frame(width: 680, height: 520)
    }

    private func copyText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
