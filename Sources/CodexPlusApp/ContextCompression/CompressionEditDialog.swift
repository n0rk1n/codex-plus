import CodexPlusCore
import SwiftUI

struct CompressionEditDialog: View {
    let roundID: UUID
    let initialUserText: String
    let initialAIBlocks: [CompressionEditBlock]
    let onCancel: () -> Void
    let onSave: (String) -> Void

    @State private var userText: String
    @State private var aiBlocks: [CompressionEditBlock]
    @State private var isShowingUnsavedConfirmation = false

    init(
        roundID: UUID,
        initialUserText: String,
        initialAIBlocks: [CompressionEditBlock],
        onCancel: @escaping () -> Void,
        onSave: @escaping (String) -> Void
    ) {
        self.roundID = roundID
        self.initialUserText = initialUserText
        self.initialAIBlocks = initialAIBlocks
        self.onCancel = onCancel
        self.onSave = onSave
        _userText = State(initialValue: initialUserText)
        _aiBlocks = State(initialValue: initialAIBlocks)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.42)
                .ignoresSafeArea()
                .onTapGesture(perform: requestClose)

            editorSurface
                .padding(18)
        }
        .alert("尚未保存", isPresented: $isShowingUnsavedConfirmation) {
            Button("保存") {
                onSave(modelInputText)
            }
            Button("不保存", role: .destructive) {
                onCancel()
            }
            Button("继续编辑", role: .cancel) {}
        } message: {
            Text("是否保存当前编辑？")
        }
        .preferredColorScheme(.dark)
    }

    private var editorSurface: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("编辑压缩版本")
                    .font(CodexTypography.sectionTitle)

                Spacer(minLength: 8)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    editor(title: "用户", text: $userText, minHeight: 140)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("AI")
                            .font(CodexTypography.captionStrong)
                            .foregroundStyle(.secondary)

                        ForEach(aiBlocks.indices, id: \.self) { index in
                            switch aiBlocks[index].kind {
                            case .details:
                                detailsTextBlock(aiBlocks[index])
                            case .assistant:
                                editor(
                                    title: aiBlocks[index].title,
                                    text: $aiBlocks[index].text,
                                    minHeight: 150
                                )
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            HStack(spacing: 8) {
                Spacer(minLength: 0)

                CodexButton(rule: .formFooterCapsule, action: requestClose) {
                    Text("取消")
                }

                CodexButton(rule: .formFooterCapsule, action: {
                    onSave(modelInputText)
                }) {
                    Text("保存")
                }
            }
        }
        .padding(24)
        .frame(minWidth: 880, idealWidth: 1040, maxWidth: .infinity, minHeight: 640, idealHeight: 760, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var modelInputText: String {
        ([userText] + aiBlocks.map(\.modelInputText))
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    private var initialModelInputText: String {
        ([initialUserText] + initialAIBlocks.map(\.modelInputText))
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    private var hasUnsavedChanges: Bool {
        modelInputText != initialModelInputText
    }

    private func requestClose() {
        if hasUnsavedChanges {
            isShowingUnsavedConfirmation = true
        } else {
            onCancel()
        }
    }

    private func editor(title: String, text: Binding<String>, minHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(CodexTypography.captionStrong)
                .foregroundStyle(.secondary)

            AppMultilineTextEditor(
                text: text,
                fontSize: 14
            )
            .frame(minHeight: minHeight)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(CodexColors.surfaceSubtle)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(CodexColors.surfaceStroke, lineWidth: 1)
            }
        }
    }

    private func detailsTextBlock(_ block: CompressionEditBlock) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(block.title)
                .font(CodexTypography.captionStrong)
                .foregroundStyle(.secondary)

            if !block.subtitle.isEmpty {
                Text(block.subtitle)
                    .font(CodexTypography.compactTechnicalSummary)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
        }
        .padding(.vertical, 4)
    }
}

struct CompressionEditBlock: Identifiable, Equatable {
    enum Kind: Equatable {
        case details
        case assistant
    }

    let id: UUID
    var kind: Kind
    var title: String
    var subtitle: String
    var text: String

    var modelInputText: String {
        text
    }

    static func details(id: UUID, title: String, subtitle: String, modelInputText: String) -> CompressionEditBlock {
        CompressionEditBlock(
            id: id,
            kind: .details,
            title: title,
            subtitle: subtitle,
            text: modelInputText
        )
    }

    static func assistant(id: UUID, text: String) -> CompressionEditBlock {
        CompressionEditBlock(
            id: id,
            kind: .assistant,
            title: "Assistant",
            subtitle: "",
            text: text
        )
    }
}
