import CodexPlusCore
import SwiftUI

struct WorkbenchComposerView: View {
    let snapshot: WorkbenchSnapshot
    let actions: ComposerActions

    @State private var prompt = ""
    @State private var promptOptimizationHandle: (any ExecutionHandle)?
    @State private var promptOptimizationID: UUID?
    @State private var isOptimizingPrompt = false
    @State private var isShowingStopOptimizationConfirmation = false
    @State private var bulbPulse = false
    @State private var optimizingPromptGlow = false
    @FocusState private var isFocused: Bool

    var body: some View {
        LiquidGlassContainer(cornerRadius: WorkbenchMetrics.composerCornerRadius) {
            HStack(alignment: .center, spacing: 12) {
                if snapshot.activeConversation == nil {
                    workspacePickerButton
                }

                promptInputField

                if shouldShowPromptOptimizationButton {
                    promptOptimizationButton
                        .transition(.scale(scale: 0.82).combined(with: .opacity))
                }

                composerButton
            }
            .animation(.spring(response: 0.24, dampingFraction: 0.78), value: shouldShowPromptOptimizationButton)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .alert("当前正在优化提示词", isPresented: $isShowingStopOptimizationConfirmation) {
            Button("继续等待", role: .cancel) {}
            Button("终止并发送", role: .destructive) {
                stopPromptOptimization()
                sendPromptNow()
            }
        } message: {
            Text("终止后会停止后台优化任务，并直接发送当前输入框内容。")
        }
        .onChange(of: prompt) {
            if prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                stopPromptOptimization()
            }
        }
        .onChange(of: snapshot.composerAction) {
            if snapshot.composerAction == .stop {
                isFocused = false
            }
        }
        .onChange(of: isOptimizingPrompt) {
            optimizingPromptGlow = isOptimizingPrompt
            if isOptimizingPrompt {
                isFocused = false
            }
        }
    }

    private var promptInputField: some View {
        ZStack(alignment: .leading) {
            TextField(activePlaceholder, text: $prompt)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .lineLimit(1)
                .submitLabel(.send)
                .focused($isFocused)
                .disabled(isTextInputDisabled)
                .opacity(promptInputOpacity)
                .onSubmit(submitPrompt)

            if isOptimizingPrompt {
                optimizingPromptOverlay
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: isOptimizingPrompt)
    }

    private var optimizingPromptOverlay: some View {
        Text("正在优化提示词")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(
                LinearGradient(
                    colors: optimizingPromptGlow
                        ? [Color.yellow, Color.cyan, Color.purple]
                        : [Color.purple, Color.orange, Color.blue],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .shadow(color: Color.yellow.opacity(optimizingPromptGlow ? 0.45 : 0.15), radius: optimizingPromptGlow ? 9 : 3)
            .shadow(color: Color.cyan.opacity(optimizingPromptGlow ? 0.22 : 0.08), radius: optimizingPromptGlow ? 14 : 5)
            .opacity(optimizingPromptGlow ? 1 : 0.68)
            .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: optimizingPromptGlow)
            .allowsHitTesting(false)
    }

    private var composerButton: some View {
        switch snapshot.composerAction {
        case .stop:
            CodexButton(
                rule: .composerIconCircle,
                isDisabled: snapshot.activeConversation == nil,
                action: actions.stop
            ) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: WorkbenchMetrics.composerControlHeight, height: WorkbenchMetrics.composerControlHeight)
            }
        case .send:
            CodexButton(
                rule: .composerIconCircle,
                isDisabled: !snapshot.canSubmitPrompt
                    || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                action: submitPrompt
            ) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: WorkbenchMetrics.composerControlHeight, height: WorkbenchMetrics.composerControlHeight)
            }
        }
    }

    private var promptOptimizationButton: some View {
        CodexButton(
            rule: .composerIconCircle,
            isDisabled: isOptimizingPrompt || snapshot.composerAction != .send,
            help: isOptimizingPrompt ? "正在优化提示词" : "优化输入提示词",
            accessibilityLabel: isOptimizingPrompt ? "正在优化提示词" : "优化输入提示词",
            action: optimizePrompt
        ) {
            Image(systemName: isOptimizingPrompt ? "lightbulb.fill" : "lightbulb")
                .font(.system(size: 15, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isOptimizingPrompt ? .yellow : .secondary)
                .frame(width: WorkbenchMetrics.composerControlHeight, height: WorkbenchMetrics.composerControlHeight)
                .scaleEffect(isOptimizingPrompt && bulbPulse ? 1.12 : 1.0)
                .opacity(isOptimizingPrompt && bulbPulse ? 0.72 : 1.0)
                .animation(
                    isOptimizingPrompt
                        ? .easeInOut(duration: 0.72).repeatForever(autoreverses: true)
                        : .default,
                    value: bulbPulse
                )
        }
    }

    private var workspacePickerButton: some View {
        HStack(spacing: 0) {
            CodexButton(rule: .workspaceCapsule, action: actions.pickWorkspace) {
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
        CodexButton(
            rule: .workspaceClear,
            help: WorkbenchStrings.clearWorkspace,
            accessibilityLabel: WorkbenchStrings.clearWorkspace,
            action: actions.clearWorkspace
        ) {
            Image(systemName: "xmark.circle.fill")
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 24, height: WorkbenchMetrics.composerControlHeight)
        }
        .padding(.trailing, 6)
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

    private var isTextInputDisabled: Bool {
        snapshot.composerAction == .stop || isOptimizingPrompt
    }

    private var promptInputOpacity: Double {
        if isOptimizingPrompt {
            return 0.18
        }

        return snapshot.canSubmitPrompt ? 1 : 0.55
    }

    private var shouldShowPromptOptimizationButton: Bool {
        snapshot.composerAction == .send
            && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submitPrompt() {
        if isOptimizingPrompt {
            isShowingStopOptimizationConfirmation = true
            return
        }

        sendPromptNow()
    }

    private func sendPromptNow() {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard snapshot.composerAction == .send, snapshot.canSubmitPrompt, !trimmedPrompt.isEmpty else {
            return
        }

        stopPromptOptimization()
        actions.send(trimmedPrompt)
        prompt = ""
    }

    private func optimizePrompt() {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard snapshot.composerAction == .send, !trimmedPrompt.isEmpty, !isOptimizingPrompt else {
            return
        }

        let originalPrompt = prompt
        let optimizationID = UUID()
        promptOptimizationID = optimizationID
        isOptimizingPrompt = true
        bulbPulse = true
        optimizingPromptGlow = true

        promptOptimizationHandle = actions.optimizePrompt(trimmedPrompt) { result in
            Task { @MainActor in
                guard promptOptimizationID == optimizationID else {
                    return
                }

                promptOptimizationHandle = nil
                promptOptimizationID = nil
                isOptimizingPrompt = false
                bulbPulse = false
                optimizingPromptGlow = false

                if case let .success(optimizedPrompt) = result, prompt == originalPrompt {
                    prompt = optimizedPrompt
                    isFocused = true
                }
            }
        }

        if promptOptimizationHandle == nil {
            promptOptimizationID = nil
            isOptimizingPrompt = false
            bulbPulse = false
            optimizingPromptGlow = false
        }
    }

    private func stopPromptOptimization() {
        promptOptimizationHandle?.stop()
        promptOptimizationHandle = nil
        promptOptimizationID = nil
        isOptimizingPrompt = false
        bulbPulse = false
        optimizingPromptGlow = false
    }
}
