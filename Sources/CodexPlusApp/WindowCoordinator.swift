import AppKit
import CodexPlusCore
import SwiftUI

@MainActor
final class WindowCoordinator: NSObject, NSWindowDelegate {
    private let conversationCoordinator: ConversationCoordinator
    private let workbenchStore: WorkbenchStore
    private let batteryMonitor: BatteryStatusMonitor
    private let codexUsageMonitor: CodexUsageMonitor
    private let dailyTokenUsageMonitor: DailyTokenUsageMonitor
    private let runController: CodexRunController
    private let permissionPrompter = PermissionPrompter()
    private let panelFactory = PanelFactory()
    private let screenProvider = ActiveScreenProvider()

    private lazy var sidePanelController = SidePanelController(
        panelFactory: panelFactory,
        screenProvider: screenProvider,
        panelDelegate: self,
        preferredSide: { [conversationCoordinator] in
            conversationCoordinator.preferredSide
        },
        setPreferredSide: { [conversationCoordinator] side in
            guard conversationCoordinator.preferredSide != side else {
                return
            }

            conversationCoordinator.togglePreferredSide()
        },
        hasRecallableContent: { [conversationCoordinator] in
            conversationCoordinator.activeConversation != nil || conversationCoordinator.snapshot.draft != nil
        },
        isPinned: { [conversationCoordinator] in
            conversationCoordinator.activeConversation?.isPinned == true
        }
    )
    private lazy var compactPanelController = CompactPanelController(
        panelFactory: panelFactory,
        screenProvider: screenProvider,
        batteryMonitor: batteryMonitor,
        codexUsageMonitor: codexUsageMonitor,
        dailyTokenUsageMonitor: dailyTokenUsageMonitor,
        panelDelegate: self
    )
    private lazy var workbenchPanelController = WorkbenchPanelController(
        panelFactory: panelFactory,
        screenProvider: screenProvider,
        store: workbenchStore,
        panelDelegate: self,
        onShow: { [weak self] in
            self?.workbenchLauncherPanelController.hide()
        },
        onHide: { [weak self] in
            self?.workbenchLauncherPanelController.show()
        }
    )
    private lazy var workbenchLauncherPanelController = WorkbenchLauncherPanelController(
        screenProvider: screenProvider,
        panelDelegate: self,
        onOpenWorkbench: { [weak self] in
            self?.showWorkbenchFromLauncher()
        }
    )

    init(
        conversationCoordinator: ConversationCoordinator,
        batteryProvider: any BatteryStatusProviding,
        codexRunner: ProcessCodexRunner,
        workbenchStore: WorkbenchStore
    ) {
        self.conversationCoordinator = conversationCoordinator
        self.workbenchStore = workbenchStore
        self.batteryMonitor = BatteryStatusMonitor(provider: batteryProvider)
        self.codexUsageMonitor = CodexUsageMonitor(provider: LocalCodexUsageProvider())
        self.dailyTokenUsageMonitor = DailyTokenUsageMonitor(provider: LocalDailyTokenUsageProvider())
        self.runController = CodexRunController(runner: codexRunner)

        super.init()
        codexUsageMonitor.start()
        dailyTokenUsageMonitor.start()
        workbenchLauncherPanelController.show()
    }

    func handleGlobalShortcut() {
        workbenchPanelController.toggle()
    }

    private func showWorkbenchFromLauncher() {
        workbenchLauncherPanelController.hide()
        workbenchPanelController.show()
    }

    private func handleLegacyGlobalShortcutRouting() {
        switch conversationCoordinator.shortcutDecision() {
        case let .recallConversation(conversationID):
            conversationCoordinator.selectConversation(conversationID)
            showSidePanel()
        case .recallDraft:
            showSidePanel()
        case .openFreshEntry:
            showCompactPanel()
        }
    }

    private func showCompactPanel() {
        sidePanelController.orderOutAll()

        compactPanelController.show(
            onOpenDraft: { [weak self] prompt in
                Task { @MainActor in
                    self?.openDraftFromCompactEntry(prompt: prompt)
                }
            },
            onSubmit: { [weak self] prompt in
                Task { @MainActor in
                    self?.startConversation(prompt: prompt)
                }
            }
        )
    }

    private func showSidePanel() {
        dismissCompactPanel()

        if conversationCoordinator.activeConversation == nil,
           conversationCoordinator.snapshot.draft == nil {
            conversationCoordinator.beginDraft()
        }

        sidePanelController.show(snapshot: conversationCoordinator.snapshot, actions: sidePanelActions())
    }

    private func startConversation(prompt: String) {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            return
        }

        conversationCoordinator.setDraftPrompt(trimmedPrompt)
        let workspacePath: String

        do {
            workspacePath = try resolveDraftWorkspacePath()
        } catch {
            conversationCoordinator.setDraftError("Unable to prepare workspace: \(error.localizedDescription)")
            if sidePanelController.isPanelVisible {
                refreshSidePanelContent()
            } else {
                prepareCenteredSidePanelFrame()
                showSidePanel()
            }
            return
        }

        let session = conversationCoordinator.startConversation(
            prompt: trimmedPrompt,
            workspacePath: workspacePath
        )
        prepareCenteredSidePanelFrame()
        showSidePanel()
        startCodexRun(prompt: trimmedPrompt, sessionID: session.id, workspacePath: session.workspacePath)
    }

    private func openDraftFromCompactEntry(prompt: String) {
        conversationCoordinator.beginDraft(prompt: prompt)
        prepareCenteredSidePanelFrame()
        showSidePanel()
    }

    private func prepareCenteredSidePanelFrame() {
        sidePanelController.prepareCenteredFrame()
    }

    private func handleFollowUp(_ prompt: String) {
        guard let session = conversationCoordinator.activeConversation else {
            return
        }

        guard !runController.isRunning(sessionID: session.id) else {
            conversationCoordinator.appendCodexEvent(
                .error("Codex is already running in this conversation. Stop the current task before sending a follow-up."),
                to: session.id
            )
            refreshSidePanelContent()
            return
        }

        conversationCoordinator.appendUserPrompt(prompt, to: session.id)
        refreshSidePanelContent()
        startCodexRun(prompt: prompt, sessionID: session.id, workspacePath: session.workspacePath)
    }

    private func startCodexRun(prompt: String, sessionID: UUID, workspacePath: String) {
        guard !runController.isRunning(sessionID: sessionID) else {
            conversationCoordinator.appendCodexEvent(
                .error("Codex is already running in this conversation. Stop the current task before starting another one."),
                to: sessionID
            )
            refreshSidePanelContent()
            return
        }

        conversationCoordinator.markRunning(sessionID)
        refreshSidePanelContent()

        let permissionMode = conversationCoordinator.conversation(with: sessionID)?.permissionMode ?? .semiAutomatic
        runController.start(
            prompt: prompt,
            permissionMode: permissionMode,
            sessionID: sessionID,
            workingDirectoryURL: URL(fileURLWithPath: workspacePath, isDirectory: true),
            onEvent: { [weak self] event, eventSessionID in
                self?.handleCodexEvent(event, sessionID: eventSessionID)
            },
            onFinish: { [weak self] result, finishSessionID in
                self?.handleCodexFinish(result, sessionID: finishSessionID)
            }
        )
    }

    private func handleCodexEvent(_ event: CodexEvent, sessionID: UUID) {
        conversationCoordinator.appendCodexEvent(event, to: sessionID)
        refreshSidePanelContent()
    }

    private func handleCodexFinish(_ result: CodexRunResult, sessionID: UUID) {
        if result.succeeded {
            conversationCoordinator.markCompleted(sessionID)
        } else {
            conversationCoordinator.markFailed(sessionID, message: failureMessage(from: result))
        }

        refreshSidePanelContent()
    }

    private func stopActiveRun(refreshesView: Bool = true) {
        guard let session = conversationCoordinator.activeConversation else {
            return
        }

        runController.stop(sessionID: session.id)

        if session.state == .running {
            conversationCoordinator.markStopped(session.id)
        }

        if refreshesView {
            refreshSidePanelContent()
        }
    }

    private func createDefaultWorkspaceDirectory() throws -> String {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path

        for _ in 0..<20 {
            let suffix = Int.random(in: 1000...9999)
            let path = ConversationWorkspacePolicy.defaultWorkspacePath(
                homeDirectoryPath: homePath,
                date: Date(),
                randomSuffix: suffix
            )
            let url = URL(fileURLWithPath: path, isDirectory: true)

            if !FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                return url.path
            }
        }

        throw CocoaError(.fileWriteFileExists)
    }

    private func resolveDraftWorkspacePath() throws -> String {
        if let selectedPath = conversationCoordinator.snapshot.draft?.selectedWorkspacePath {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: selectedPath, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else {
                throw CocoaError(.fileNoSuchFile)
            }

            return selectedPath
        }

        return try createDefaultWorkspaceDirectory()
    }

    private func pickDraftWorkspace() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        conversationCoordinator.setDraftWorkspacePath(url.path)
        refreshSidePanelContent()
    }

    private func closeSidePanel() {
        guard let session = conversationCoordinator.activeConversation else {
            sidePanelController.orderOutAll()
            return
        }

        if session.state == .running {
            guard permissionPrompter.confirmStopRunningTaskOnClose() else {
                return
            }

            stopActiveRun(refreshesView: false)
        }

        conversationCoordinator.closeConversation(session.id)
        sidePanelController.closeAndReset()
    }

    private func togglePin() {
        guard let session = conversationCoordinator.activeConversation else {
            return
        }

        conversationCoordinator.setPinned(!session.isPinned, for: session.id)
        refreshSidePanelContent()
    }

    private func togglePreferredSide() {
        sidePanelController.clearCustomFrame()
        conversationCoordinator.togglePreferredSide()

        if sidePanelController.isPanelVisible {
            sidePanelController.moveToPreferredSide(
                snapshot: conversationCoordinator.snapshot,
                actions: sidePanelActions()
            )
        }
    }

    private func toggleFullAccess() {
        guard let session = conversationCoordinator.activeConversation else {
            return
        }

        guard session.state != .running else {
            permissionPrompter.showCannotChangeWhileRunning()
            return
        }

        if session.permissionMode == .semiAutomatic {
            guard permissionPrompter.confirmEnableFullAccess() else {
                return
            }
        }

        let nextMode: PermissionMode = session.permissionMode == .fullAccess ? .semiAutomatic : .fullAccess
        conversationCoordinator.setPermissionMode(nextMode, for: session.id)
        refreshSidePanelContent()
    }

    private func refreshSidePanelContent() {
        sidePanelController.refresh(snapshot: conversationCoordinator.snapshot, actions: sidePanelActions())
    }

    private func archiveConversation(_ id: UUID) {
        guard let session = conversationCoordinator.conversation(with: id) else {
            return
        }

        if runController.isRunning(sessionID: id) {
            guard permissionPrompter.confirmStopRunningTaskOnArchive() else {
                return
            }

            _ = runController.stop(sessionID: id)
            if session.state == .running {
                conversationCoordinator.markStopped(id)
            }
        }

        _ = conversationCoordinator.archiveConversation(id)

        if !conversationCoordinator.snapshot.hasVisibleConversations {
            returnToCompactEntry()
        } else {
            refreshSidePanelContent()
        }
    }

    private func returnToCompactEntry() {
        sidePanelController.closeAndReset()
        showCompactPanel()
    }

    private func dismissCompactPanel() {
        compactPanelController.dismiss()
    }

    func windowDidMove(_ notification: Notification) {
        guard let panel = notification.object as? GlassPanel else {
            return
        }

        if compactPanelController.recordMove(of: panel) {
            return
        }

        if sidePanelController.recordMove(of: panel) {
            return
        }

        if workbenchPanelController.recordMove(of: panel) {
            return
        }
    }

    private func failureMessage(from result: CodexRunResult) -> String {
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderr.isEmpty {
            return stderr
        }

        return "Codex exited with code \(result.exitCode)."
    }

    private func sidePanelActions() -> SidePanelActions {
        SidePanelActions(
            onSubmitDraft: { [weak self] prompt in
                Task { @MainActor in
                    self?.startConversation(prompt: prompt)
                }
            },
            onFollowUp: { [weak self] prompt in
                Task { @MainActor in
                    self?.handleFollowUp(prompt)
                }
            },
            onStop: { [weak self] in
                Task { @MainActor in
                    self?.stopActiveRun()
                }
            },
            onTogglePin: { [weak self] in
                Task { @MainActor in
                    self?.togglePin()
                }
            },
            onToggleSide: { [weak self] in
                Task { @MainActor in
                    self?.togglePreferredSide()
                }
            },
            onToggleFullAccess: { [weak self] in
                Task { @MainActor in
                    self?.toggleFullAccess()
                }
            },
            onSelectWorkspace: { [weak self] id in
                Task { @MainActor in
                    self?.conversationCoordinator.selectWorkspace(id)
                    self?.refreshSidePanelContent()
                }
            },
            onSelectConversation: { [weak self] id in
                Task { @MainActor in
                    self?.conversationCoordinator.selectConversation(id)
                    self?.refreshSidePanelContent()
                }
            },
            onNewDraft: { [weak self] in
                Task { @MainActor in
                    self?.conversationCoordinator.beginDraft()
                    self?.refreshSidePanelContent()
                }
            },
            onArchiveConversation: { [weak self] id in
                Task { @MainActor in
                    self?.archiveConversation(id)
                }
            },
            onPickWorkspace: { [weak self] in
                Task { @MainActor in
                    self?.pickDraftWorkspace()
                }
            },
            onReorderWorkspace: { [weak self] id, index in
                Task { @MainActor in
                    self?.conversationCoordinator.reorderWorkspace(id, to: index)
                    self?.refreshSidePanelContent()
                }
            },
            onReorderConversation: { [weak self] id, index in
                Task { @MainActor in
                    self?.conversationCoordinator.reorderConversation(id, to: index)
                    self?.refreshSidePanelContent()
                }
            }
        )
    }
}
