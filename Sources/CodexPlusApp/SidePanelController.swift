import AppKit
import CodexPlusCore
import SwiftUI

@MainActor
struct SidePanelActions {
    let onSubmitDraft: (String) -> Void
    let onFollowUp: (String) -> Void
    let onStop: () -> Void
    let onTogglePin: () -> Void
    let onToggleSide: () -> Void
    let onToggleFullAccess: () -> Void
    let onSelectWorkspace: (UUID) -> Void
    let onSelectConversation: (UUID) -> Void
    let onNewDraft: () -> Void
    let onArchiveConversation: (UUID) -> Void
    let onPickWorkspace: () -> Void
    let onReorderWorkspace: (UUID, Int) -> Void
    let onReorderConversation: (UUID, Int) -> Void
}

@MainActor
final class SidePanelController {
    private let panelFactory: PanelFactory
    private let screenProvider: ActiveScreenProvider
    private weak var panelDelegate: NSWindowDelegate?
    private let preferredSide: () -> SideAttachment
    private let setPreferredSide: (SideAttachment) -> Void
    private let hasRecallableContent: () -> Bool
    private let isPinned: () -> Bool

    private var panel: GlassPanel?
    private var customFrame: NSRect?
    private var edgeAffordancePanel: GlassPanel?
    private var model: ConversationPanelModel?
    private var isContentInstalled = false
    private let mouseExitMonitors = EventMonitorStore()
    private let dismissMonitors = EventMonitorStore()
    private var hasMouseEnteredPanel = false

    var isPanelVisible: Bool {
        panel?.isVisible == true
    }

    init(
        panelFactory: PanelFactory,
        screenProvider: ActiveScreenProvider,
        panelDelegate: NSWindowDelegate?,
        preferredSide: @escaping () -> SideAttachment,
        setPreferredSide: @escaping (SideAttachment) -> Void,
        hasRecallableContent: @escaping () -> Bool,
        isPinned: @escaping () -> Bool
    ) {
        self.panelFactory = panelFactory
        self.screenProvider = screenProvider
        self.panelDelegate = panelDelegate
        self.preferredSide = preferredSide
        self.setPreferredSide = setPreferredSide
        self.hasRecallableContent = hasRecallableContent
        self.isPinned = isPinned
    }

    deinit {
        mouseExitMonitors.removeAll()
        dismissMonitors.removeAll()
    }

    func prepareCenteredFrame() {
        guard let screen = screenProvider.activeScreen() else {
            customFrame = nil
            return
        }

        customFrame = ConversationPanelLayoutPolicy.initialCenteredFrame(in: screen.visibleFrame)
    }

    func show(snapshot: ConversationCoordinatorSnapshot, actions: SidePanelActions) {
        edgeAffordancePanel?.orderOut(nil)

        guard let screen = screenProvider.activeScreen() else {
            return
        }

        let frame = sidePanelFrame(on: screen)
        let panel = panel ?? panelFactory.makePanel(frame: frame, delegate: panelDelegate)

        panel.setFrame(frame, display: true)
        hasMouseEnteredPanel = false
        refresh(snapshot: snapshot, actions: actions, on: panel)
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
        installMouseExitMonitorIfNeeded()
        installDismissMonitorsIfNeeded()
    }

    func refresh(snapshot: ConversationCoordinatorSnapshot, actions: SidePanelActions) {
        refresh(snapshot: snapshot, actions: actions, on: panel)
    }

    func orderOutAll() {
        panel?.orderOut(nil)
        edgeAffordancePanel?.orderOut(nil)
        dismissMonitors.removeAll()
    }

    func closeAndReset() {
        orderOutAll()
        model = nil
        isContentInstalled = false
        hasMouseEnteredPanel = false
    }

    func clearCustomFrame() {
        customFrame = nil
    }

    func moveToPreferredSide(snapshot: ConversationCoordinatorSnapshot, actions: SidePanelActions) {
        guard let screen = screenProvider.activeScreen(), let panel else {
            return
        }

        panel.setFrame(sidePanelFrame(on: screen), display: true, animate: true)
        refresh(snapshot: snapshot, actions: actions, on: panel)
    }

    func recordMove(of movedPanel: GlassPanel) -> Bool {
        guard movedPanel === panel else {
            return false
        }

        updatePlacement(afterMoving: movedPanel)
        return true
    }

    private func refresh(
        snapshot: ConversationCoordinatorSnapshot,
        actions: SidePanelActions,
        on targetPanel: GlassPanel?
    ) {
        let panelModel: ConversationPanelModel

        if let model {
            model.snapshot = snapshot
            panelModel = model
        } else {
            panelModel = ConversationPanelModel(snapshot: snapshot)
            model = panelModel
        }

        if let targetPanel, !isContentInstalled {
            installContent(in: targetPanel, model: panelModel, actions: actions)
        }
    }

    private func installContent(
        in panel: GlassPanel,
        model: ConversationPanelModel,
        actions: SidePanelActions
    ) {
        let contentView = DraggableHostingView(
            rootView: ConversationPanelHostView(
                model: model,
                onSubmitDraft: actions.onSubmitDraft,
                onFollowUp: actions.onFollowUp,
                onStop: actions.onStop,
                onTogglePin: actions.onTogglePin,
                onToggleSide: actions.onToggleSide,
                onToggleFullAccess: actions.onToggleFullAccess,
                onSelectWorkspace: actions.onSelectWorkspace,
                onSelectConversation: actions.onSelectConversation,
                onNewDraft: actions.onNewDraft,
                onArchiveConversation: actions.onArchiveConversation,
                onPickWorkspace: actions.onPickWorkspace,
                onReorderWorkspace: actions.onReorderWorkspace,
                onReorderConversation: actions.onReorderConversation
            )
        )
        contentView.windowDragMode = .sidePanel
        panel.contentView = contentView
        isContentInstalled = true
    }

    private func sidePanelFrame(on screen: NSScreen) -> NSRect {
        if let customFrame {
            return customFrame
        }

        let visibleFrame = screen.visibleFrame
        let width = min(CGFloat(460), visibleFrame.width)
        let x: CGFloat

        switch preferredSide() {
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

        switch preferredSide() {
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
            hasRecallableContent(),
            !isPinned(),
            customFrame == nil,
            let screen = screen ?? screenProvider.activeScreen()
        else {
            return
        }

        let frame = edgeAffordanceFrame(on: screen)
        let panel = edgeAffordancePanel ?? panelFactory.makePanel(frame: frame, delegate: panelDelegate)
        panel.setFrame(frame, display: true)
        panel.contentView = NSHostingView(
            rootView: SideEdgeAffordanceView { [weak self] in
                Task { @MainActor [weak self] in
                    self?.revealPanelFromAffordance()
                }
            }
        )
        panel.orderFrontRegardless()
        edgeAffordancePanel = panel
    }

    private func revealPanelFromAffordance() {
        guard let panel else {
            return
        }

        edgeAffordancePanel?.orderOut(nil)
        hasMouseEnteredPanel = false
        panel.makeKeyAndOrderFront(nil)
    }

    private func installMouseExitMonitorIfNeeded() {
        guard mouseExitMonitors.isEmpty else {
            return
        }

        let localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.hideIfMouseExited()
            return event
        }

        if let localMonitor {
            mouseExitMonitors.append(localMonitor)
        }

        if let globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved], handler: { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.hideIfMouseExited()
            }
        }) {
            mouseExitMonitors.append(globalMonitor)
        }
    }

    private func installDismissMonitorsIfNeeded() {
        guard dismissMonitors.isEmpty else {
            return
        }

        if let keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown], handler: { [weak self] event in
            guard let self else {
                return event
            }

            guard
                let panel = self.panel,
                panel.isVisible,
                panel.isKeyWindow || panel.isMainWindow,
                CompactEntryDismissPolicy.shouldDismissForKeyDown(keyCode: event.keyCode)
            else {
                return event
            }

            self.orderOutAll()
            return nil
        }) {
            dismissMonitors.append(keyMonitor)
        }

        let mouseDownMask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseDownMask, handler: { [weak self] event in
            self?.dismissIfNeededForMouseDown(at: NSEvent.mouseLocation)
            return event
        }) {
            dismissMonitors.append(localMouseMonitor)
        }

        if let globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseDownMask, handler: { [weak self] _ in
            Task { @MainActor in
                self?.dismissIfNeededForMouseDown(at: NSEvent.mouseLocation)
            }
        }) {
            dismissMonitors.append(globalMouseMonitor)
        }
    }

    private func dismissIfNeededForMouseDown(at point: NSPoint) {
        guard let panel, panel.isVisible else {
            return
        }

        guard !isPinned() else {
            return
        }

        if CompactEntryDismissPolicy.shouldDismissForMouseDown(at: point, panelFrame: panel.frame) {
            orderOutAll()
        }
    }

    private func hideIfMouseExited() {
        if
            let edgeAffordancePanel,
            edgeAffordancePanel.isVisible,
            NSMouseInRect(
                NSEvent.mouseLocation,
                edgeAffordancePanel.frame.insetBy(dx: -8, dy: -8),
                false
            )
        {
            revealPanelFromAffordance()
            return
        }

        guard
            let panel,
            panel.isVisible,
            customFrame == nil,
            !isPinned()
        else {
            return
        }

        let panelHitFrame = panel.frame.insetBy(dx: -8, dy: -8)
        if NSMouseInRect(NSEvent.mouseLocation, panelHitFrame, false) {
            hasMouseEnteredPanel = true
            return
        }

        if hasMouseEnteredPanel {
            let screen = panel.screen ?? screenProvider.activeScreen()
            panel.orderOut(nil)
            showEdgeAffordance(on: screen)
        }
    }

    private func updatePlacement(afterMoving panel: GlassPanel) {
        guard let screen = panel.screen ?? screenProvider.activeScreen() else {
            customFrame = panel.frame
            return
        }

        switch PanelPlacementPolicy.placement(for: panel.frame, in: screen.visibleFrame) {
        case let .attached(side):
            customFrame = nil
            setPreferredSide(side)
        case .free:
            customFrame = panel.frame
        }
    }
}
