import AppKit
import CodexPlusCore
import SwiftUI

@MainActor
final class WorkbenchPanelController {
    private let panelFactory: PanelFactory
    private let screenProvider: ActiveScreenProvider
    private let store: WorkbenchStore
    private weak var panelDelegate: NSWindowDelegate?
    private let onShow: () -> Void
    private let onHide: () -> Void

    private var panel: GlassPanel?
    private let dismissMonitors = EventMonitorStore()
    private var wasNearMidline = false

    init(
        panelFactory: PanelFactory,
        screenProvider: ActiveScreenProvider,
        store: WorkbenchStore,
        panelDelegate: NSWindowDelegate?,
        onShow: @escaping () -> Void,
        onHide: @escaping () -> Void
    ) {
        self.panelFactory = panelFactory
        self.screenProvider = screenProvider
        self.store = store
        self.panelDelegate = panelDelegate
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
        wasNearMidline = true
        panel.contentView = WorkbenchPanelHostingView(rootView: WorkbenchView(store: store))
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
        installDismissMonitorsIfNeeded()
        onShow()
    }

    func hide() {
        let wasVisible = panel?.isVisible == true
        panel?.orderOut(nil)
        dismissMonitors.removeAll()
        if wasVisible {
            onHide()
        }
    }

    func recordMove(of movedPanel: GlassPanel) -> Bool {
        guard movedPanel === panel else {
            return false
        }

        guard let screenFrame = (
            screen(containing: movedPanel.frame) ??
                movedPanel.screen ??
                screenProvider.activeScreen()
        )?.visibleFrame else {
            wasNearMidline = false
            return true
        }

        let snappedFrame = CompactPanelSnapPolicy.snappedFrame(
            for: movedPanel.frame,
            in: screenFrame
        )
        let isNearMidline = abs(snappedFrame.midX - screenFrame.midX) < 0.5

        if isNearMidline && !wasNearMidline {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }

        wasNearMidline = isNearMidline
        return true
    }

    static func defaultFrame(in visibleFrame: NSRect) -> NSRect {
        let width = min(CGFloat(1240), visibleFrame.width > 96 ? visibleFrame.width - 96 : visibleFrame.width)
        let height = min(CGFloat(720), visibleFrame.height > 96 ? visibleFrame.height - 96 : visibleFrame.height)

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

        if let mouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp], handler: { [weak self] event in
            self?.snapWorkbenchPanelToMidlineIfNeeded()
            return event
        }) {
            dismissMonitors.append(mouseUpMonitor)
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

    private func snapWorkbenchPanelToMidlineIfNeeded() {
        guard let panel, panel.isVisible else {
            return
        }

        guard let screenFrame = (
            screen(containing: panel.frame) ??
                panel.screen ??
                screenProvider.activeScreen()
        )?.visibleFrame else {
            return
        }

        let snappedFrame = CompactPanelSnapPolicy.snappedFrame(
            for: panel.frame,
            in: screenFrame
        )

        guard snappedFrame != panel.frame else {
            return
        }

        panel.setFrame(snappedFrame, display: true)
    }

    private func screen(containing frame: NSRect) -> NSScreen? {
        NSScreen.screens.max { first, second in
            first.visibleFrame.intersection(frame).area < second.visibleFrame.intersection(frame).area
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

private extension NSRect {
    var area: CGFloat {
        width * height
    }
}
