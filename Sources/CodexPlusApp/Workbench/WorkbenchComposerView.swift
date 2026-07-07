import CodexPlusCore
import SwiftUI

struct WorkbenchComposerView: View {
    let snapshot: WorkbenchSnapshot
    let actions: ComposerActions

    @State private var prompt = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        LiquidGlassContainer(cornerRadius: WorkbenchMetrics.composerCornerRadius) {
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
            Button(action: actions.stop) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: WorkbenchMetrics.composerControlHeight, height: WorkbenchMetrics.composerControlHeight)
            }
            .buttonStyle(.plain)
            .codexCircularButtonHitArea()
            .disabled(snapshot.activeConversation == nil)
        case .send:
            Button(action: submitPrompt) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: WorkbenchMetrics.composerControlHeight, height: WorkbenchMetrics.composerControlHeight)
            }
            .buttonStyle(.plain)
            .codexCircularButtonHitArea()
            .disabled(
                !snapshot.canSubmitPrompt
                    || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
        }
    }

    private var workspacePickerButton: some View {
        HStack(spacing: 0) {
            Button(action: actions.pickWorkspace) {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .font(.system(size: 12, weight: .semibold))

                    Text(activeProjectName ?? WorkbenchStrings.chooseWorkspace)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: workspacePickerTextMaxWidth, alignment: .leading)
                }
                .padding(.leading, 10)
                .padding(.trailing, activeProjectName == nil ? 10 : 6)
                .frame(height: WorkbenchMetrics.composerControlHeight)
                .fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(.plain)
            .codexCapsuleButtonHitArea()

            if activeProjectName != nil {
                workspaceClearButton
            }
        }
        .glassEffect(.regular, in: Capsule(style: .continuous))
        .compositingGroup()
        .mask(Capsule(style: .continuous))
        .help(activeProjectPath ?? WorkbenchStrings.chooseWorkspace)
        .accessibilityLabel(WorkbenchStrings.chooseWorkspace)
    }

    private var workspaceClearButton: some View {
        Button(action: actions.clearWorkspace) {
            Image(systemName: "xmark.circle.fill")
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 24, height: WorkbenchMetrics.composerControlHeight)
        }
        .buttonStyle(.plain)
        .codexRectangleButtonHitArea()
        .padding(.trailing, 6)
        .help(WorkbenchStrings.clearWorkspace)
        .accessibilityLabel(WorkbenchStrings.clearWorkspace)
    }

    private var activePlaceholder: String {
        snapshot.activeConversation == nil ? WorkbenchStrings.emptyConversationSubtitle : WorkbenchStrings.continueInput
    }

    private var activeProjectName: String? {
        snapshot.selectedDraftWorkspace?.projectName ?? snapshot.projectCards.first { $0.isActive }?.projectName
    }

    private var activeProjectPath: String? {
        snapshot.selectedDraftWorkspace?.projectPath ?? snapshot.projectCards.first { $0.isActive }?.projectPath
    }

    private var workspacePickerTextMaxWidth: CGFloat {
        activeProjectName == nil ? 92 : 86
    }

    private func submitPrompt() {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard snapshot.composerAction == .send, snapshot.canSubmitPrompt, !trimmedPrompt.isEmpty else {
            return
        }

        actions.send(trimmedPrompt)
        prompt = ""
    }
}
