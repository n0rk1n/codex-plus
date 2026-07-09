import CodexPlusCore
import SwiftUI

struct CompressionCustomDialog: View {
    let roundCount: Int
    let templates: [PromptTemplate]
    let onCancel: () -> Void
    let onStart: (PromptTemplate, String) -> Void

    @State private var selectedTemplateID: UUID
    @State private var userInstruction = ""

    init(
        roundCount: Int,
        templates: [PromptTemplate],
        onCancel: @escaping () -> Void,
        onStart: @escaping (PromptTemplate, String) -> Void
    ) {
        self.roundCount = roundCount
        self.templates = templates
        self.onCancel = onCancel
        self.onStart = onStart
        _selectedTemplateID = State(initialValue: templates.first?.id ?? UUID())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CodexSpacing.contentInline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("自定义压缩")
                    .font(CodexTypography.sectionTitle)
                Text("连续 \(roundCount) 轮")
                    .font(CodexTypography.caption)
                    .foregroundStyle(.secondary)
            }

            CodexPicker(
                rule: .requiredMenu,
                title: "",
                selection: $selectedTemplateID,
                isDisabled: templates.isEmpty,
                help: "选择上下文压缩提示词模板"
            ) {
                ForEach(templates) { template in
                    Text(template.name).tag(template.id)
                }
            }

            AppMultilineTextEditor(text: $userInstruction)
                .frame(minHeight: 140)
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(CodexColors.surfaceDivider, lineWidth: 1)
                }

            HStack(spacing: 8) {
                Spacer()
                CodexButton(rule: .formFooterCapsule, help: "取消自定义压缩", action: onCancel) {
                    Text("取消")
                }
                CodexButton(rule: .formFooterCapsule, isDisabled: selectedTemplate == nil, help: "开始自定义压缩", action: startCompression) {
                    Text("开始压缩")
                }
            }
        }
        .padding(CodexSpacing.contentStack)
        .frame(width: 440)
    }

    private var selectedTemplate: PromptTemplate? {
        templates.first { $0.id == selectedTemplateID }
    }

    private func startCompression() {
        guard let selectedTemplate else {
            return
        }
        onStart(selectedTemplate, userInstruction)
    }
}
