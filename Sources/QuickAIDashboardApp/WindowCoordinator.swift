import AppKit
import QuickAIDashboardCore
import SwiftUI

@MainActor
final class WindowCoordinator {
    private let conversationCoordinator: ConversationCoordinator
    private let batteryProvider: any BatteryStatusProviding
    private let codexRunner: ProcessCodexRunner
    private let codexCallbackQueue = DispatchQueue(label: "QuickAIDashboardApp.WindowCoordinator.codexCallbacks")

    private var compactPanel: GlassPanel?
    private var sidePanel: GlassPanel?
    private var edgeAffordancePanel: GlassPanel?
    private var sidePanelModel: ConversationPanelModel?
    private var isSidePanelContentInstalled = false
    private var activeRunHandle: CodexRunHandle?
    private var activeRunID: UUID?
    private var activeRunSessionID: UUID?
    private var stoppedRunIDs = Set<UUID>()
    private let mouseExitMonitors = EventMonitorStore()
    private var hasMouseEnteredSidePanel = false

    private static let fullAccessWarningText = "Full Access for this conversation. Codex can make broader local changes until this task ends or you stop it."

    init(
        conversationCoordinator: ConversationCoordinator,
        batteryProvider: any BatteryStatusProviding,
        codexRunner: ProcessCodexRunner
    ) {
        self.conversationCoordinator = conversationCoordinator
        self.batteryProvider = batteryProvider
        self.codexRunner = codexRunner
    }

    deinit {
        mouseExitMonitors.removeAll()
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
        sidePanel?.orderOut(nil)
        edgeAffordancePanel?.orderOut(nil)

        let size = NSSize(width: 420, height: 210)
        guard let screen = activeScreen() else {
            return
        }

        let visibleFrame = screen.visibleFrame
        let origin = NSPoint(
            x: visibleFrame.midX - (size.width / 2),
            y: visibleFrame.maxY - (visibleFrame.height / 3) - (size.height / 2)
        )
        let frame = NSRect(origin: origin, size: size)
        let panel = compactPanel ?? makePanel(frame: frame)

        panel.setFrame(frame, display: true)
        panel.contentView = NSHostingView(
            rootView: CompactEntryView(
                batteryStatus: batteryProvider.currentStatus(),
                onSubmit: { [weak self] prompt in
                    Task { @MainActor in
                        self?.startConversation(prompt: prompt)
                    }
                }
            )
        )
        panel.makeKeyAndOrderFront(nil)
        compactPanel = panel
    }

    private func showSidePanel() {
        compactPanel?.orderOut(nil)
        edgeAffordancePanel?.orderOut(nil)

        guard conversationCoordinator.activeConversation != nil else {
            showCompactPanel()
            return
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
        return panel
    }

    private func startConversation(prompt: String) {
        compactPanel?.orderOut(nil)

        let session = conversationCoordinator.startConversation(prompt: prompt)
        conversationCoordinator.markRunning(session.id)
        showSidePanel()
        startCodexRun(prompt: prompt, sessionID: session.id)
    }

    private func handleFollowUp(_ prompt: String) {
        guard let session = conversationCoordinator.activeConversation else {
            return
        }

        guard activeRunHandle == nil else {
            conversationCoordinator.appendCodexEvent(
                .error("Codex is already running. Stop the current task before sending a follow-up."),
                to: session.id
            )
            refreshSidePanelContent()
            return
        }

        conversationCoordinator.appendUserPrompt(prompt, to: session.id)
        conversationCoordinator.markRunning(session.id)
        refreshSidePanelContent()
        startCodexRun(prompt: prompt, sessionID: session.id)
    }

    private func startCodexRun(prompt: String, sessionID: UUID) {
        guard activeRunHandle == nil else {
            conversationCoordinator.appendCodexEvent(
                .error("Codex is already running. Stop the current task before starting another one."),
                to: sessionID
            )
            refreshSidePanelContent()
            return
        }

        let permissionMode = conversationCoordinator.activeConversation?.permissionMode ?? .semiAutomatic
        let runID = UUID()
        activeRunID = runID
        activeRunSessionID = sessionID
        let callbackQueue = codexCallbackQueue
        let callbackTarget = WeakWindowCoordinatorBox(self)

        let handle = codexRunner.run(
            prompt: prompt,
            permissionMode: permissionMode,
            onEvent: { event in
                callbackQueue.async {
                    // Preserve runner callback order before entering MainActor state.
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            callbackTarget.value?.handleCodexEvent(event, sessionID: sessionID, runID: runID)
                        }
                    }
                }
            },
            onFinish: { result in
                callbackQueue.async {
                    // Preserve runner callback order before entering MainActor state.
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            callbackTarget.value?.handleCodexFinish(result, sessionID: sessionID, runID: runID)
                        }
                    }
                }
            }
        )

        activeRunHandle = handle
    }

    private func handleCodexEvent(_ event: CodexEvent, sessionID: UUID, runID: UUID) {
        guard activeRunSessionID == sessionID, activeRunID == runID else {
            return
        }

        conversationCoordinator.appendCodexEvent(event, to: sessionID)
        refreshSidePanelContent()
    }

    private func handleCodexFinish(_ result: CodexRunResult, sessionID: UUID, runID: UUID) {
        if stoppedRunIDs.remove(runID) != nil {
            if activeRunID == runID {
                activeRunHandle = nil
                activeRunID = nil
                activeRunSessionID = nil
            }
            return
        }

        guard activeRunSessionID == sessionID, activeRunID == runID else {
            return
        }

        activeRunHandle = nil
        activeRunID = nil
        activeRunSessionID = nil

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

        if let activeRunHandle, activeRunSessionID == session.id {
            if let activeRunID {
                stoppedRunIDs.insert(activeRunID)
            }
            activeRunHandle.stop()
            self.activeRunHandle = nil
            activeRunID = nil
            activeRunSessionID = nil
        }

        if session.state == .running {
            conversationCoordinator.markStopped(session.id)
        }

        if refreshesView {
            refreshSidePanelContent()
        }
    }

    private func closeSidePanel() {
        guard let session = conversationCoordinator.activeConversation else {
            sidePanel?.orderOut(nil)
            edgeAffordancePanel?.orderOut(nil)
            return
        }

        if session.state == .running {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Stop the running Codex task?"
            alert.informativeText = "Closing the side panel will stop the active run."
            alert.addButton(withTitle: "Stop and Close")
            alert.addButton(withTitle: "Cancel")

            guard alert.runModal() == .alertFirstButtonReturn else {
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
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "Full Access cannot change while Codex is running."
            alert.informativeText = Self.fullAccessWarningText
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        if session.permissionMode == .semiAutomatic {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Enable Full Access?"
            alert.informativeText = Self.fullAccessWarningText
            alert.addButton(withTitle: "Enable Full Access")
            alert.addButton(withTitle: "Cancel")

            guard alert.runModal() == .alertFirstButtonReturn else {
                return
            }
        }

        let nextMode: PermissionMode = session.permissionMode == .fullAccess ? .semiAutomatic : .fullAccess
        conversationCoordinator.setPermissionMode(nextMode, for: session.id)
        refreshSidePanelContent()
    }

    private func refreshSidePanelContent(on panel: GlassPanel? = nil) {
        guard let session = conversationCoordinator.activeConversation else {
            return
        }

        let targetPanel = panel ?? sidePanel
        let model: ConversationPanelModel

        if let sidePanelModel {
            sidePanelModel.session = session
            model = sidePanelModel
        } else {
            model = ConversationPanelModel(session: session)
            sidePanelModel = model
        }

        if let targetPanel, !isSidePanelContentInstalled {
            installSidePanelContent(in: targetPanel, model: model)
        }
    }

    private func installSidePanelContent(in panel: GlassPanel, model: ConversationPanelModel) {
        panel.contentView = NSHostingView(
            rootView: ConversationPanelHostView(
                model: model,
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
        )
        isSidePanelContentInstalled = true
    }

    private func sidePanelFrame(on screen: NSScreen) -> NSRect {
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
        guard
            conversationCoordinator.activeConversation != nil,
            conversationCoordinator.activeConversation?.isPinned != true,
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

@MainActor
private final class ConversationPanelModel: ObservableObject {
    @Published var session: ConversationSession

    init(session: ConversationSession) {
        self.session = session
    }
}

private struct ConversationPanelHostView: View {
    @ObservedObject var model: ConversationPanelModel

    let onFollowUp: (String) -> Void
    let onStop: () -> Void
    let onClose: () -> Void
    let onTogglePin: () -> Void
    let onToggleSide: () -> Void
    let onToggleFullAccess: () -> Void

    var body: some View {
        ConversationView(
            session: model.session,
            onFollowUp: onFollowUp,
            onStop: onStop,
            onClose: onClose,
            onTogglePin: onTogglePin,
            onToggleSide: onToggleSide,
            onToggleFullAccess: onToggleFullAccess
        )
        .id(model.session.id)
    }
}

private struct SideEdgeAffordanceView: View {
    let onActivate: () -> Void

    var body: some View {
        Button(action: onActivate) {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.32), lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 4)
                .padding(2)
        }
        .buttonStyle(.plain)
        .help("Show Conversation")
        .accessibilityLabel("Show Conversation")
    }
}

private final class EventMonitorStore: @unchecked Sendable {
    private var monitors: [Any] = []

    var isEmpty: Bool {
        monitors.isEmpty
    }

    func append(_ monitor: Any) {
        monitors.append(monitor)
    }

    func removeAll() {
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }

        monitors.removeAll()
    }

    deinit {
        removeAll()
    }
}

private final class WeakWindowCoordinatorBox: @unchecked Sendable {
    weak var value: WindowCoordinator?

    init(_ value: WindowCoordinator) {
        self.value = value
    }
}
