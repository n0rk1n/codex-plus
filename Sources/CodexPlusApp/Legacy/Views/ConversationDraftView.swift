import CodexPlusCore
import SwiftUI

struct ConversationDraftView: View {
    let draft: ConversationDraft?
    let onPickWorkspace: () -> Void
    let onSubmit: (String) -> Void

    @FocusState private var isPromptFocused: Bool
    @State private var prompt = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CodexButton(
                rule: .workspaceClear,
                help: "Choose Workspace",
                accessibilityLabel: "Choose Workspace",
                action: onPickWorkspace
            ) {
                HStack(spacing: 8) {
                    Image(systemName: "folder")
                        .font(CodexTypography.menuPrimary)

                    Text(workspaceText)
                        .font(CodexTypography.caption)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, CodexSpacing.contentInline)
                .frame(height: 34)
            }
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(CodexColors.surfaceInactive)
            }

            if let errorMessage = draft?.errorMessage {
                Text(errorMessage)
                    .font(CodexTypography.caption2)
                    .foregroundStyle(CodexColors.stateFailed)
                    .lineLimit(2)
            }

            LiquidGlassContainer(cornerRadius: CodexRadius.card) {
                HStack(alignment: .bottom, spacing: 10) {
                    CodexMultilineTextField(
                        rule: .multilinePrompt,
                        placeholder: "Ask Codex...",
                        text: $prompt,
                        onSubmit: submitPrompt
                    )
                        .focused($isPromptFocused)

                    CodexButton(
                        rule: .composerIconCircle,
                        action: submitPrompt
                    ) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(CodexTypography.sectionHeader)
                    }
                    .help("Send")
                    .accessibilityLabel("Send")
                    .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                    .padding(.horizontal, CodexSpacing.compactInline)
                    .padding(.vertical, CodexSpacing.contentInline)
            }
        }
        .onAppear {
            syncPromptFromDraft()
            isPromptFocused = true
        }
        .onChange(of: draft?.prompt ?? "") {
            syncPromptFromDraft()
        }
    }

    private var workspaceText: String {
        guard let path = draft?.selectedWorkspacePath else {
            return "Choose workspace or send to create a default workspace"
        }

        return path
    }

    private func submitPrompt() {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            return
        }

        onSubmit(trimmedPrompt)
    }

    private func syncPromptFromDraft() {
        let draftPrompt = draft?.prompt ?? ""
        guard draftPrompt != prompt else {
            return
        }

        prompt = draftPrompt
    }
}
