import AppKit
import CodexPlusCore
import SwiftUI

@MainActor
final class WindowCoordinator: NSObject, NSWindowDelegate {
    private let conversationCoordinator: ConversationCoordinator
    private let batteryMonitor: BatteryStatusMonitor
    private let codexUsageMonitor: CodexUsageMonitor
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
        hasActiveConversation: { [conversationCoordinator] in
            conversationCoordinator.activeConversation != nil
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
        panelDelegate: self
    )

    init(
        conversationCoordinator: ConversationCoordinator,
        batteryProvider: any BatteryStatusProviding,
        codexRunner: ProcessCodexRunner
    ) {
        self.conversationCoordinator = conversationCoordinator
        self.batteryMonitor = BatteryStatusMonitor(provider: batteryProvider)
        self.codexUsageMonitor = CodexUsageMonitor(provider: LocalCodexUsageProvider())
        self.runController = CodexRunController(runner: codexRunner)

        super.init()
        codexUsageMonitor.start()
    }

    func handleGlobalShortcut() {
        NSApp.activate(ignoringOtherApps: true)

        switch conversationCoordinator.shortcutDecision() {
        case .recallExisting:
            showSidePanel()
        case .openFreshEntry:
            showCompactPanel()
        }
    }

    private func showCompactPanel() {
        sidePanelController.orderOutAll()

        compactPanelController.show { [weak self] prompt in
            Task { @MainActor in
                self?.startConversation(prompt: prompt)
            }
        }
    }

    private func showSidePanel() {
        dismissCompactPanel()

        guard let session = conversationCoordinator.activeConversation else {
            showCompactPanel()
            return
        }

        sidePanelController.show(session: session, actions: sidePanelActions())
    }

    private func startConversation(prompt: String) {
        let session = conversationCoordinator.startConversation(prompt: prompt)
        prepareCenteredSidePanelFrame()
        showSidePanel()
        startCodexRun(prompt: prompt, sessionID: session.id)
    }

    private func prepareCenteredSidePanelFrame() {
        sidePanelController.prepareCenteredFrame()
    }

    private func handleFollowUp(_ prompt: String) {
        guard let session = conversationCoordinator.activeConversation else {
            return
        }

        guard !runController.isRunning else {
            conversationCoordinator.appendCodexEvent(
                .error("Codex is already running. Stop the current task before sending a follow-up."),
                to: session.id
            )
            refreshSidePanelContent()
            return
        }

        conversationCoordinator.appendUserPrompt(prompt, to: session.id)
        refreshSidePanelContent()
        startCodexRun(prompt: prompt, sessionID: session.id)
    }

    private func startCodexRun(prompt: String, sessionID: UUID) {
        guard !runController.isRunning else {
            conversationCoordinator.appendCodexEvent(
                .error("Codex is already running. Stop the current task before starting another one."),
                to: sessionID
            )
            refreshSidePanelContent()
            return
        }

        conversationCoordinator.markRunning(sessionID)
        refreshSidePanelContent()

        let permissionMode = conversationCoordinator.activeConversation?.permissionMode ?? .semiAutomatic
        runController.start(
            prompt: prompt,
            permissionMode: permissionMode,
            sessionID: sessionID,
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

        if let session = conversationCoordinator.activeConversation {
            sidePanelController.moveToPreferredSide(session: session, actions: sidePanelActions())
            refreshSidePanelContent()
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
        guard let session = conversationCoordinator.activeConversation else {
            return
        }

        sidePanelController.refresh(session: session, actions: sidePanelActions())
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
            onClose: { [weak self] in
                Task { @MainActor in
                    self?.closeSidePanel()
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
            }
        )
    }
}
