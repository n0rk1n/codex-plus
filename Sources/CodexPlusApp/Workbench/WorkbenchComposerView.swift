import CodexPlusCore
import SwiftUI

struct WorkbenchComposerView: View {
    let snapshot: WorkbenchSnapshot
    let onSend: (String) -> Void
    let onStop: () -> Void

    @State private var prompt = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        LiquidGlassContainer(cornerRadius: 22) {
            HStack(alignment: .bottom, spacing: 12) {
                TextField(activePlaceholder, text: $prompt)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .lineLimit(1)
                    .submitLabel(.send)
                    .focused($isFocused)
                    .disabled(snapshot.composerAction == .stop)
                    .opacity(snapshot.canSubmitPrompt ? 1 : 0.55)
                    .onSubmit(submitPrompt)

                composerButton
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .onChange(of: snapshot.composerAction) {
            if snapshot.composerAction == .stop {
                isFocused = false
            }
        }
    }

    private var composerButton: some View {
        switch snapshot.composerAction {
        case .stop:
            Button(action: onStop) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .disabled(snapshot.activeConversation == nil)
        case .send:
            Button(action: submitPrompt) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .disabled(
                !snapshot.canSubmitPrompt
                    || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
        }
    }

    private var activePlaceholder: String {
        snapshot.activeConversation == nil ? "新对话" : "继续输入"
    }

    private func submitPrompt() {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard snapshot.composerAction == .send, snapshot.canSubmitPrompt, !trimmedPrompt.isEmpty else {
            return
        }

        onSend(trimmedPrompt)
        prompt = ""
    }
}
