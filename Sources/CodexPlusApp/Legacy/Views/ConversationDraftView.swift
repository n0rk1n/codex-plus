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
            Button(action: onPickWorkspace) {
                HStack(spacing: 8) {
                    Image(systemName: "folder")
                        .font(.system(size: 13, weight: .semibold))

                    Text(workspaceText)
                        .font(.caption)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .frame(height: 34)
            }
            .buttonStyle(.plain)
            .codexRoundedButtonHitArea(cornerRadius: 8)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            }
            .help("Choose Workspace")
            .accessibilityLabel("Choose Workspace")

            if let errorMessage = draft?.errorMessage {
                Text(errorMessage)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            LiquidGlassContainer(cornerRadius: 22) {
                HStack(alignment: .bottom, spacing: 10) {
                    AppMultilineTextField(
                        placeholder: "Ask Codex...",
                        text: $prompt,
                        fontSize: 15,
                        lineLimit: MultilineInputDefaults.conversationPromptLineLimit,
                        onSubmit: submitPrompt
                    )
                        .focused($isPromptFocused)

                    Button(action: submitPrompt) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .codexCircularButtonHitArea()
                    .help("Send")
                    .accessibilityLabel("Send")
                    .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
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
