import AppKit
import CodexPlusCore
import QuartzCore
import SwiftUI

@MainActor
final class WindowCoordinator: NSObject, NSWindowDelegate {
    private let conversationCoordinator: ConversationCoordinator
    private let batteryMonitor: BatteryStatusMonitor
    private let codexUsageMonitor: CodexUsageMonitor
    private let runController: CodexRunController
    private let permissionPrompter = PermissionPrompter()

    private var compactPanel: GlassPanel?
    private var compactPanelFrame: NSRect?
    private var sidePanel: GlassPanel?
    private var sidePanelCustomFrame: NSRect?
    private var edgeAffordancePanel: GlassPanel?
    private var sidePanelModel: ConversationPanelModel?
    private var isSidePanelContentInstalled = false
    private let compactDismissMonitors = EventMonitorStore()
    private let mouseExitMonitors = EventMonitorStore()
    private var hasMouseEnteredSidePanel = false

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

    deinit {
        compactDismissMonitors.removeAll()
        mouseExitMonitors.removeAll()
    }

    func handleGlobalShortcut() {
        NSApp.activate(ignoringOtherApps: true)

        switch conversationCoordinator.shortcutDecision() {
        case .recallConversation, .recallDraft:
            showSidePanel()
        case .openFreshEntry:
            showCompactPanel()
        }
    }

    private func showCompactPanel() {
        sidePanel?.orderOut(nil)
        edgeAffordancePanel?.orderOut(nil)

        guard let screen = activeScreen() else {
            return
        }

        let frame = compactPanelFrame ?? defaultCompactPanelFrame(on: screen)
        let panel = compactPanel ?? makePanel(frame: frame)

        batteryMonitor.start()
        panel.isMovableByWindowBackground = false
        panel.setFrame(frame, display: true)
        let contentView = DraggableHostingView(
            rootView: CompactEntryHostView(
                batteryMonitor: batteryMonitor,
                codexUsageMonitor: codexUsageMonitor,
                onOpenDraft: { [weak self] in
                    Task { @MainActor in
                        self?.openDraftFromCompactEntry()
                    }
                },
                onSubmit: { [weak self] prompt in
                    Task { @MainActor in
                        self?.startConversation(prompt: prompt)
                    }
                }
            )
        )
        contentView.windowDragMode = .compactPrompt
        panel.contentView = contentView
        panel.makeKeyAndOrderFront(nil)
        compactPanel = panel
        installCompactDismissMonitorsIfNeeded()
    }

    private func showSidePanel() {
        dismissCompactPanel()
        edgeAffordancePanel?.orderOut(nil)

        if conversationCoordinator.activeConversation == nil,
           conversationCoordinator.snapshot.draft == nil {
            conversationCoordinator.beginDraft()
        }

        guard let screen = activeScreen() else {
            return
        }

        let frame = sidePanelFrame(on: screen)
        let panel = sidePanel ?? makePanel(frame: frame)

        panel.setFrame(frame, display: true)
        hasMouseEnteredSidePanel = false
        refreshSidePanelContent(on: panel)
        panel.makeKeyAndOrderFront(nil)
        sidePanel = panel
        installMouseExitMonitorIfNeeded()
    }

    private func makePanel(frame: NSRect) -> GlassPanel {
        let panel = GlassPanel(contentRect: frame)
        panel.acceptsMouseMovedEvents = true
        panel.delegate = self
        return panel
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
            if let sidePanel, sidePanel.isVisible {
                refreshSidePanelContent(on: sidePanel)
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

    private func openDraftFromCompactEntry() {
        conversationCoordinator.beginDraft()
        prepareCenteredSidePanelFrame()
        showSidePanel()
    }

    private func prepareCenteredSidePanelFrame() {
        guard let screen = activeScreen() else {
            sidePanelCustomFrame = nil
            return
        }

        sidePanelCustomFrame = nsRect(
            from: ConversationPanelLayoutPolicy.initialCenteredFrame(
                in: screenRect(from: screen.visibleFrame)
            )
        )
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
            sidePanel?.orderOut(nil)
            edgeAffordancePanel?.orderOut(nil)
            return
        }

        if session.state == .running {
            guard permissionPrompter.confirmStopRunningTaskOnClose() else {
                return
            }

            stopActiveRun(refreshesView: false)
        }

        sidePanel?.orderOut(nil)
        edgeAffordancePanel?.orderOut(nil)
        conversationCoordinator.closeConversation(session.id)
        sidePanelModel = nil
        isSidePanelContentInstalled = false
        hasMouseEnteredSidePanel = false
    }

    private func togglePin() {
        guard let session = conversationCoordinator.activeConversation else {
            return
        }

        conversationCoordinator.setPinned(!session.isPinned, for: session.id)
        refreshSidePanelContent()
    }

    private func togglePreferredSide() {
        sidePanelCustomFrame = nil
        conversationCoordinator.togglePreferredSide()

        if let screen = activeScreen(), let sidePanel {
            sidePanel.setFrame(sidePanelFrame(on: screen), display: true, animate: true)
            refreshSidePanelContent(on: sidePanel)
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

    private func refreshSidePanelContent(on panel: GlassPanel? = nil) {
        let snapshot = conversationCoordinator.snapshot
        let targetPanel = panel ?? sidePanel
        let model: ConversationPanelModel

        if let sidePanelModel {
            sidePanelModel.snapshot = snapshot
            model = sidePanelModel
        } else {
            model = ConversationPanelModel(snapshot: snapshot)
            sidePanelModel = model
        }

        if let targetPanel, !isSidePanelContentInstalled {
            installSidePanelContent(in: targetPanel, model: model)
        }
    }

    private func installSidePanelContent(in panel: GlassPanel, model: ConversationPanelModel) {
        panel.contentView = DraggableHostingView(
            rootView: ConversationPanelHostView(
                model: model,
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
        )
        isSidePanelContentInstalled = true
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
        guard let screen = activeScreen() else {
            showCompactPanel()
            return
        }

        let targetFrame = defaultCompactPanelFrame(on: screen)

        if let sidePanel, sidePanel.isVisible {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                sidePanel.animator().setFrame(targetFrame, display: true)
            } completionHandler: { [weak self] in
                Task { @MainActor in
                    self?.sidePanel?.orderOut(nil)
                    self?.sidePanelModel = nil
                    self?.isSidePanelContentInstalled = false
                    self?.hasMouseEnteredSidePanel = false
                    self?.showCompactPanel()
                }
            }
            return
        }

        sidePanelModel = nil
        isSidePanelContentInstalled = false
        hasMouseEnteredSidePanel = false
        showCompactPanel()
    }

    private func defaultCompactPanelFrame(on screen: NSScreen) -> NSRect {
        let size = NSSize(width: 420, height: 210)
        let visibleFrame = screen.visibleFrame
        let origin = NSPoint(
            x: visibleFrame.midX - (size.width / 2),
            y: visibleFrame.maxY - (visibleFrame.height / 3) - (size.height / 2)
        )

        return NSRect(origin: origin, size: size)
    }

    private func sidePanelFrame(on screen: NSScreen) -> NSRect {
        if let sidePanelCustomFrame {
            return sidePanelCustomFrame
        }

        let visibleFrame = screen.visibleFrame
        let width = min(CGFloat(460), visibleFrame.width)
        let x: CGFloat

        switch conversationCoordinator.preferredSide {
        case .left:
            x = visibleFrame.minX
        case .right:
            x = visibleFrame.maxX - width
        }

        return NSRect(
            x: x,
            y: visibleFrame.minY,
            width: width,
            height: visibleFrame.height
        )
    }

    private func edgeAffordanceFrame(on screen: NSScreen) -> NSRect {
        let visibleFrame = screen.visibleFrame
        let size = NSSize(width: 12, height: 96)
        let x: CGFloat

        switch conversationCoordinator.preferredSide {
        case .left:
            x = visibleFrame.minX
        case .right:
            x = visibleFrame.maxX - size.width
        }

        return NSRect(
            x: x,
            y: visibleFrame.midY - (size.height / 2),
            width: size.width,
            height: size.height
        )
    }

    private func showEdgeAffordance(on screen: NSScreen?) {
        let snapshot = conversationCoordinator.snapshot
        let canRecallConversation = snapshot.activeConversation.map { !$0.isPinned } ?? false

        guard
            canRecallConversation || snapshot.draft != nil,
            sidePanelCustomFrame == nil,
            let screen = screen ?? activeScreen()
        else {
            return
        }

        let frame = edgeAffordanceFrame(on: screen)
        let panel = edgeAffordancePanel ?? makePanel(frame: frame)
        panel.setFrame(frame, display: true)
        panel.contentView = NSHostingView(
            rootView: SideEdgeAffordanceView { [weak self] in
                Task { @MainActor in
                    self?.showSidePanel()
                }
            }
        )
        panel.orderFrontRegardless()
        edgeAffordancePanel = panel
    }

    private func installMouseExitMonitorIfNeeded() {
        guard mouseExitMonitors.isEmpty else {
            return
        }

        let localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.hideSidePanelIfMouseExited()
            return event
        }

        if let localMonitor {
            mouseExitMonitors.append(localMonitor)
        }

        if let globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved], handler: { [weak self] _ in
            Task { @MainActor in
                self?.hideSidePanelIfMouseExited()
            }
        }) {
            mouseExitMonitors.append(globalMonitor)
        }
    }

    private func hideSidePanelIfMouseExited() {
        if
            let edgeAffordancePanel,
            edgeAffordancePanel.isVisible,
            NSMouseInRect(NSEvent.mouseLocation, edgeAffordancePanel.frame.insetBy(dx: -8, dy: -8), false) {
            showSidePanel()
            return
        }

        guard
            let sidePanel,
            sidePanel.isVisible,
            sidePanelCustomFrame == nil,
            conversationCoordinator.activeConversation?.isPinned != true
        else {
            return
        }

        let sidePanelHitFrame = sidePanel.frame.insetBy(dx: -8, dy: -8)
        if NSMouseInRect(NSEvent.mouseLocation, sidePanelHitFrame, false) {
            hasMouseEnteredSidePanel = true
            return
        }

        if hasMouseEnteredSidePanel {
            let screen = sidePanel.screen ?? activeScreen()
            sidePanel.orderOut(nil)
            showEdgeAffordance(on: screen)
        }
    }

    private func dismissCompactPanel() {
        compactPanel?.orderOut(nil)
        batteryMonitor.stop()
        compactDismissMonitors.removeAll()
    }

    private func installCompactDismissMonitorsIfNeeded() {
        guard compactDismissMonitors.isEmpty else {
            return
        }

        if let keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown], handler: { [weak self] event in
            guard let self else {
                return event
            }

            guard
                self.compactPanel?.isVisible == true,
                CompactEntryDismissPolicy.shouldDismissForKeyDown(keyCode: event.keyCode)
            else {
                return event
            }

            self.dismissCompactPanel()
            return nil
        }) {
            compactDismissMonitors.append(keyMonitor)
        }

        let mouseDownMask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseDownMask, handler: { [weak self] event in
            self?.dismissCompactPanelIfNeededForMouseDown(at: NSEvent.mouseLocation)
            return event
        }) {
            compactDismissMonitors.append(localMouseMonitor)
        }

        if let globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseDownMask, handler: { [weak self] _ in
            Task { @MainActor in
                self?.dismissCompactPanelIfNeededForMouseDown(at: NSEvent.mouseLocation)
            }
        }) {
            compactDismissMonitors.append(globalMouseMonitor)
        }
    }

    private func dismissCompactPanelIfNeededForMouseDown(at point: NSPoint) {
        guard let compactPanel, compactPanel.isVisible else {
            return
        }

        let shouldDismiss = CompactEntryDismissPolicy.shouldDismissForMouseDown(
            at: ScreenPoint(x: Double(point.x), y: Double(point.y)),
            panelFrame: ScreenRect(
                x: Double(compactPanel.frame.minX),
                y: Double(compactPanel.frame.minY),
                width: Double(compactPanel.frame.width),
                height: Double(compactPanel.frame.height)
            )
        )

        if shouldDismiss {
            dismissCompactPanel()
        }
    }

    func windowDidMove(_ notification: Notification) {
        guard let panel = notification.object as? GlassPanel else {
            return
        }

        if panel === compactPanel {
            compactPanelFrame = panel.frame
            return
        }

        if panel === sidePanel {
            updateSidePanelPlacement(afterMoving: panel)
        }
    }

    private func updateSidePanelPlacement(afterMoving panel: GlassPanel) {
        guard let screen = panel.screen ?? activeScreen() else {
            sidePanelCustomFrame = panel.frame
            return
        }

        switch PanelPlacementPolicy.placement(
            for: screenRect(from: panel.frame),
            in: screenRect(from: screen.visibleFrame)
        ) {
        case let .attached(side):
            sidePanelCustomFrame = nil
            setPreferredSide(side)
        case .free:
            sidePanelCustomFrame = panel.frame
        }
    }

    private func setPreferredSide(_ side: SideAttachment) {
        guard conversationCoordinator.preferredSide != side else {
            return
        }

        conversationCoordinator.togglePreferredSide()
    }

    private func screenRect(from rect: NSRect) -> ScreenRect {
        ScreenRect(
            x: Double(rect.minX),
            y: Double(rect.minY),
            width: Double(rect.width),
            height: Double(rect.height)
        )
    }

    private func nsRect(from rect: ScreenRect) -> NSRect {
        NSRect(
            x: rect.x,
            y: rect.y,
            width: rect.width,
            height: rect.height
        )
    }

    private func failureMessage(from result: CodexRunResult) -> String {
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderr.isEmpty {
            return stderr
        }

        return "Codex exited with code \(result.exitCode)."
    }

    private func activeScreen() -> NSScreen? {
        if let screen = NSApp.keyWindow?.screen {
            return screen
        }

        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { screen in
            NSMouseInRect(mouseLocation, screen.frame, false)
        } ?? NSScreen.main ?? NSScreen.screens.first
    }
}
