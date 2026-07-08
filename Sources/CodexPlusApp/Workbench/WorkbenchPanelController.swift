import AppKit
import CodexPlusCore
import SwiftUI

@MainActor
final class WorkbenchPanelController {
    private let panelFactory: PanelFactory
    private let screenProvider: ActiveScreenProvider
    private let store: WorkbenchStore
    private let codexUsageMonitor: CodexUsageMonitor
    private let promptOptimizationService: PromptOptimizationService
    private weak var panelDelegate: NSWindowDelegate?
    private let onOpenSettings: () -> Void
    private let onShow: () -> Void
    private let onHide: () -> Void

    private var panel: GlassPanel?
    private let dismissMonitors = EventMonitorStore()

    init(
        panelFactory: PanelFactory,
        screenProvider: ActiveScreenProvider,
        store: WorkbenchStore,
        codexUsageMonitor: CodexUsageMonitor,
        promptOptimizationService: PromptOptimizationService,
        panelDelegate: NSWindowDelegate?,
        onOpenSettings: @escaping () -> Void,
        onShow: @escaping () -> Void,
        onHide: @escaping () -> Void
    ) {
        self.panelFactory = panelFactory
        self.screenProvider = screenProvider
        self.store = store
        self.codexUsageMonitor = codexUsageMonitor
        self.promptOptimizationService = promptOptimizationService
        self.panelDelegate = panelDelegate
        self.onOpenSettings = onOpenSettings
        self.onShow = onShow
        self.onHide = onHide
    }

    deinit {
        dismissMonitors.removeAll()
    }

    func toggle() {
        if panel?.isVisible == true {
            hide()
        } else {
            show()
        }
    }

    func show() {
        guard let screen = screenProvider.activeScreen() else {
            return
        }

        let frame = Self.defaultFrame(in: screen.visibleFrame)
        let panel = panel ?? panelFactory.makePanel(frame: frame, delegate: panelDelegate)
        panel.hasShadow = false
        panel.setFrame(frame, display: true)
        panel.contentView = WorkbenchPanelHostingView(
            rootView: WorkbenchView(
                store: store,
                codexUsageMonitor: codexUsageMonitor,
                promptOptimizationService: promptOptimizationService,
                onOpenSettings: onOpenSettings
            )
        )
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
        installDismissMonitorsIfNeeded()
        onShow()
    }

    func hide(showLauncher: Bool = true) {
        let wasVisible = panel?.isVisible == true
        panel?.orderOut(nil)
        dismissMonitors.removeAll()
        if wasVisible && showLauncher {
            onHide()
        }
    }

    func recordMove(of movedPanel: GlassPanel) -> Bool {
        guard movedPanel === panel else {
            return false
        }

        return true
    }

    static func defaultFrame(in visibleFrame: NSRect) -> NSRect {
        let width = (visibleFrame.width * 0.90).rounded()
        let height = (visibleFrame.height * 0.84).rounded()

        return NSRect(
            x: visibleFrame.midX - (width / 2),
            y: visibleFrame.midY - (height / 2),
            width: width,
            height: height
        )
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

            self.hide()
            return nil
        }) {
            dismissMonitors.append(keyMonitor)
        }

        let mouseDownMask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseDownMask, handler: { [weak self] event in
            self?.hideIfNeededForOutsideClick(at: NSEvent.mouseLocation)
            return event
        }) {
            dismissMonitors.append(localMouseMonitor)
        }

        if let globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseDownMask, handler: { [weak self] _ in
            Task { @MainActor in
                self?.hideIfNeededForOutsideClick(at: NSEvent.mouseLocation)
            }
        }) {
            dismissMonitors.append(globalMouseMonitor)
        }
    }

    private func hideIfNeededForOutsideClick(at point: NSPoint) {
        guard let panel, panel.isVisible else {
            return
        }

        if WorkbenchInteractionPolicies.shouldHideForOutsideClick(
            isPinned: store.snapshot.isPinned,
            clickPoint: point,
            panelFrame: panel.frame
        ) {
            hide()
        }
    }

}

private final class WorkbenchPanelHostingView<Content: View>: NSHostingView<Content> {
    required init(rootView: Content) {
        super.init(rootView: rootView)
        configureTransparentBacking()
    }

    @available(*, unavailable)
    required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureTransparentBacking() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false
        layer?.shadowOpacity = 0
        layer?.shadowColor = NSColor.clear.cgColor
    }
}
