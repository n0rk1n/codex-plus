import AppKit
import CodexPlusCore
import SwiftUI

struct WorkbenchView: View {
    @ObservedObject var store: WorkbenchStore
    @ObservedObject var codexUsageMonitor: CodexUsageMonitor
    let promptOptimizationService: PromptOptimizationService
    let onOpenSettings: () -> Void

    @State private var infoNotice: WorkbenchInfoNotice?
    private let infoNoticeTopOffset: CGFloat = 18

    var body: some View {
        LiquidGlassScene(padding: 0, minWidth: 980, minHeight: 620) {
            VStack(spacing: WorkbenchMetrics.verticalSpacing) {
                TopProjectStripView(
                    isPinned: store.snapshot.isPinned,
                    isNewConversationDisabled: !store.snapshot.canStartNewConversation,
                    isShowingArchiveSearch: store.snapshot.isShowingArchiveSearch,
                    actions: actions.projectStrip
                )

                if let error = store.snapshot.error {
                    LiquidGlassContainer(cornerRadius: WorkbenchMetrics.errorCornerRadius) {
                        HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(CodexColors.stateWarning)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(error.title)
                                    .font(CodexTypography.statusBar)
                                Text(error.message)
                                    .font(CodexTypography.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }

                            Spacer(minLength: CodexSpacing.tightVertical)

                            CodexButton(
                                rule: .toolbarIconCircle,
                                accessibilityLabel: WorkbenchStrings.closeError,
                                action: { store.clearError() }
                            ) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(CodexTypography.tinyControlLabel)
                            }
                        }
                        .padding(.horizontal, CodexSpacing.contentInline)
                        .padding(.vertical, CodexSpacing.tightVertical)
                    }
                }

                if store.snapshot.isShowingArchiveSearch {
                    ArchivedConversationView(
                        results: store.snapshot.archiveSearchResults,
                        openedConversation: store.snapshot.openedArchiveConversation,
                        actions: actions.archive
                    )

                    WorkbenchStatusBarView(state: store.snapshot.statusBar, codexUsageStatus: codexUsageMonitor.status)
                } else {
                    conversationWorkspace
                }
            }
            .padding(WorkbenchMetrics.scenePadding)
            .overlay(alignment: .top) {
                infoNoticeArea
            }
            .alert("终止任务后归档？", isPresented: pendingArchiveConfirmationBinding) {
                Button("取消", role: .cancel) {
                    store.cancelArchiveConfirmation()
                }
                Button("停止并归档", role: .destructive) {
                    store.confirmPendingStopAndArchive()
                }
            } message: {
                Text("这个对话仍在运行。归档前需要先停止当前 Codex 任务；停止后会保存完整事件流，并将对话标记为已归档。")
            }
        }
    }

    private var conversationWorkspace: some View {
        VStack(spacing: WorkbenchMetrics.verticalSpacing) {
            HStack(spacing: WorkbenchMetrics.contentColumnSpacing) {
                WorkbenchConversationListView(
                    cards: store.snapshot.projectCards,
                    actions: actions.projectStrip
                )

                VStack(spacing: WorkbenchMetrics.verticalSpacing) {
                    WorkbenchConversationView(
                        snapshot: store.snapshot,
                        actions: actions.conversation
                    )

                    WorkbenchComposerView(
                        snapshot: store.snapshot,
                        actions: actions.composer
                    )
                }
            }

            WorkbenchStatusBarView(state: store.snapshot.statusBar, codexUsageStatus: codexUsageMonitor.status)
        }
    }

    private var actions: WorkbenchActions {
        WorkbenchActions(
            projectStrip: ProjectStripActions(
                newConversation: { store.beginNewConversationDraft() },
                returnToConversation: { store.returnToConversationPage() },
                openArchive: { store.showArchiveSearch() },
                openSettings: onOpenSettings,
                togglePin: { store.togglePin() },
                selectProject: { store.selectProject($0) },
                selectConversation: { store.selectConversation($0) }
            ),
            conversation: ConversationActions(
                archiveConversation: { _ = store.archiveConversation($0) },
                editCompressionSegment: { store.editCompressionSegment(roundID: $0, segmentKind: $1, content: $2) },
                editCompressionRound: { store.editCompressionRound(roundID: $0, userContent: $1, assistantContent: $2) },
                editCompressionRoundContent: { store.editCompressionRoundContent(roundID: $0, content: $1) },
                excludeCompressionRound: { store.excludeCompressionRound(roundID: $0) },
                restoreCompressionOriginal: { store.restoreCompressionOriginal(roundID: $0) },
                rollbackCompressionVersion: { store.rollbackCompressionVersion(versionID: $0) },
                loadCompressionTemplates: { store.loadCompressionTemplates() },
                compressSelectedRounds: { store.compressSelectedRounds(roundIDs: $0, template: $1, userInstruction: $2) }
            ),
            composer: ComposerActions(
                send: { store.submitPrompt($0) },
                systemCompress: { store.systemCompressActiveConversation(pendingPrompt: $0) },
                refreshCompressionBudget: { await store.refreshCompressionBudget(pendingPrompt: $0) },
                previewModelInput: { store.refreshModelInputPreview(pendingPrompt: $0) },
                optimizePrompt: optimizePrompt,
                pickWorkspace: pickWorkspace,
                clearWorkspace: { store.clearDraftWorkspaceSelection() },
                stop: { store.stopActiveRun() }
            ),
            archive: ArchiveActions(
                search: { store.searchArchives($0) },
                open: { store.openArchive($0) },
                delete: { store.deleteArchive($0) },
                restore: { store.restoreArchive($0) },
                showRestoredNotice: { showRestoredNotice(for: $0) }
            )
        )
    }

    @ViewBuilder
    private var infoNoticeArea: some View {
        if let infoNotice {
            infoNoticeView(infoNotice)
                .padding(.top, infoNoticeTopOffset)
                .frame(maxWidth: .infinity, alignment: .center)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .zIndex(1)
        }
    }

    private func infoNoticeView(_ notice: WorkbenchInfoNotice) -> some View {
        LiquidGlassContainer(cornerRadius: CodexRadius.badge) {
            HStack(spacing: 4) {
                Text(notice.message)
                    .foregroundStyle(.primary)

                if let actionTitle = notice.actionTitle, notice.conversationID != nil {
                    CodexButton(rule: .inlineTextLink, action: {
                        handleInfoNoticeAction(notice)
                    }) {
                        Text(actionTitle)
                            .foregroundStyle(CodexColors.stateRunning.opacity(0.72))
                    }
                }
            }
            .font(CodexTypography.restoreNoticeAction)
            .padding(.horizontal, CodexSpacing.compactInline)
            .padding(.vertical, CodexSpacing.tightInline)
        }
        .overlay(
            RoundedRectangle(cornerRadius: CodexRadius.badge, style: .continuous)
                .stroke(CodexColors.surfaceStroke, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
    }

    private var pendingArchiveConfirmationBinding: Binding<Bool> {
        Binding(
            get: { store.snapshot.pendingArchiveConfirmationConversationID != nil },
            set: { isPresented in
                if !isPresented {
                    store.cancelArchiveConfirmation()
                }
            }
        )
    }

    private func showRestoredNotice(for conversationID: UUID) {
        showInfoNotice(.restored(conversationID: conversationID))
    }

    private func showInfoNotice(_ notice: WorkbenchInfoNotice) {
        infoNotice = notice
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            if infoNotice?.id == notice.id {
                infoNotice = nil
            }
        }
    }

    private func handleInfoNoticeAction(_ notice: WorkbenchInfoNotice) {
        if let conversationID = notice.conversationID {
            store.selectConversation(conversationID)
        }
        infoNotice = nil
    }

    private func pickWorkspace() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        store.createProject(
            path: url.path,
            displayName: ConversationWorkspacePolicy.displayName(for: url.path)
        )
    }

    private func optimizePrompt(
        _ input: String,
        onFinish: @escaping @Sendable (PromptOptimizationResult) -> Void
    ) -> (any ExecutionHandle)? {
        let workspacePath: String
        if let activeProjectPath {
            workspacePath = activeProjectPath
        } else {
            do {
                workspacePath = try ConversationWorkspacePolicy.createDefaultWorkspaceDirectory()
            } catch {
                onFinish(.failure("无法准备提示词优化工作区：\(error)"))
                return nil
            }
        }

        return promptOptimizationService.startOptimization(
            input: input,
            workingDirectoryURL: URL(fileURLWithPath: workspacePath, isDirectory: true),
            onFinish: onFinish
        )
    }

    private var activeProjectPath: String? {
        store.snapshot.selectedDraftWorkspace?.projectPath ?? store.snapshot.projectCards.first { $0.isActive }?.projectPath
    }

    private struct WorkbenchInfoNotice: Equatable, Identifiable {
        let id = UUID()
        let message: String
        let actionTitle: String?
        let conversationID: UUID?

        static func restored(conversationID: UUID) -> WorkbenchInfoNotice {
            WorkbenchInfoNotice(
                message: "已经恢复，是否",
                actionTitle: "跳转对话",
                conversationID: conversationID
            )
        }
    }
}
