import CodexPlusCore
import SwiftUI

struct WorkbenchComposerView: View {
    let snapshot: WorkbenchSnapshot
    let onSend: (String) -> Void
    let onPickWorkspace: () -> Void
    let onClearWorkspace: () -> Void
    let onStop: () -> Void

    @State private var prompt = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        LiquidGlassContainer(cornerRadius: 22) {
            HStack(alignment: .center, spacing: 12) {
                if snapshot.activeConversation == nil {
                    workspacePickerButton
                }

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

    private var workspacePickerButton: some View {
        HStack(spacing: 0) {
            Button(action: onPickWorkspace) {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .font(.system(size: 12, weight: .semibold))

                    Text(activeProjectName ?? "选择工作目录")
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                }
                .padding(.leading, 10)
                .padding(.trailing, activeProjectName == nil ? 10 : 6)
                .frame(height: 30)
                .frame(maxWidth: 190)
                .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)

            if activeProjectName != nil {
                workspaceClearButton
            }
        }
        .glassEffect(.regular, in: Capsule(style: .continuous))
        .compositingGroup()
        .mask(Capsule(style: .continuous))
        .help(activeProjectPath ?? "选择工作目录")
        .accessibilityLabel("选择工作目录")
    }

    private var workspaceClearButton: some View {
        Button(action: onClearWorkspace) {
            Image(systemName: "xmark.circle.fill")
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 24, height: 30)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 6)
        .help("清除工作目录")
        .accessibilityLabel("清除工作目录")
    }

    private var activePlaceholder: String {
        snapshot.activeConversation == nil ? "新对话" : "继续输入"
    }

    private var activeProjectName: String? {
        snapshot.projectCards.first { $0.isActive }?.projectName
    }

    private var activeProjectPath: String? {
        snapshot.projectCards.first { $0.isActive }?.projectPath
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
