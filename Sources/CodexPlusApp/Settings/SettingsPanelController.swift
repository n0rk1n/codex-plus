import AppKit
import CodexPlusCore
import SwiftUI

@MainActor
final class SettingsPanelController {
    private let panelFactory: PanelFactory
    private let screenProvider: ActiveScreenProvider
    private weak var panelDelegate: NSWindowDelegate?
    private let repository: any PromptTemplateRepository
    private let onDismiss: () -> Void

    private var panel: GlassPanel?
    private var hasInstalledContent = false
    private var isConfirmingClose = false
    private let dismissMonitors = EventMonitorStore()
    private lazy var store = PromptTemplateSettingsStore(repository: repository)

    init(
        panelFactory: PanelFactory,
        screenProvider: ActiveScreenProvider,
        panelDelegate: NSWindowDelegate?,
        repository: any PromptTemplateRepository,
        onDismiss: @escaping () -> Void
    ) {
        self.panelFactory = panelFactory
        self.screenProvider = screenProvider
        self.panelDelegate = panelDelegate
        self.repository = repository
        self.onDismiss = onDismiss
    }

    deinit {
        dismissMonitors.removeAll()
    }

    func show() {
        let frame = panel?.frame ?? Self.defaultFrame(in: activeVisibleFrame())
        let panel = panel ?? panelFactory.makePanel(frame: frame, delegate: panelDelegate)
        panel.isReleasedWhenClosed = false
        panel.hasShadow = false
        panel.setFrame(frame, display: true)
        if !hasInstalledContent {
            panel.contentView = SettingsHostingView(
                rootView: PromptTemplateManagerView(store: store)
            )
            hasInstalledContent = true
        }
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
        installDismissMonitorsIfNeeded()
    }

    func recordMove(of movedPanel: GlassPanel) -> Bool {
        movedPanel === panel
    }

    @discardableResult
    func dismiss() -> Bool {
        guard let panel, panel.isVisible else {
            return true
        }

        guard !isConfirmingClose, confirmDirtyCloseIfNeeded() else {
            return false
        }

        completeDismissal(orderOut: true)
        return true
    }

    func shouldClose(_ closingPanel: GlassPanel) -> Bool {
        guard closingPanel === panel else {
            return true
        }

        guard !isConfirmingClose, confirmDirtyCloseIfNeeded() else {
            return false
        }

        completeDismissal(orderOut: false)
        return true
    }

    static func defaultFrame(in visibleFrame: NSRect) -> NSRect {
        let width = min(CGFloat(1100), visibleFrame.width > 96 ? visibleFrame.width - 96 : visibleFrame.width)
        let height = min(CGFloat(700), visibleFrame.height > 96 ? visibleFrame.height - 96 : visibleFrame.height)

        return NSRect(
            x: visibleFrame.midX - (width / 2),
            y: visibleFrame.midY - (height / 2),
            width: width,
            height: height
        )
    }

    private func activeVisibleFrame() -> NSRect {
        if let screen = screenProvider.activeScreen() {
            return screen.visibleFrame
        }

        return NSScreen.main?.visibleFrame
            ?? NSScreen.screens.first?.visibleFrame
            ?? NSRect(x: 120, y: 120, width: 980, height: 620)
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
                self.panel?.isVisible == true,
                CompactEntryDismissPolicy.shouldDismissForKeyDown(keyCode: event.keyCode)
            else {
                return event
            }

            _ = self.dismiss()
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
        guard let panel, panel.isVisible, !isConfirmingClose else {
            return
        }

        if CompactEntryDismissPolicy.shouldDismissForMouseDown(at: point, panelFrame: panel.frame) {
            dismiss()
        }
    }

    private func completeDismissal(orderOut: Bool) {
        if orderOut {
            panel?.orderOut(nil)
        }

        dismissMonitors.removeAll()
        onDismiss()
    }

    private func confirmDirtyCloseIfNeeded() -> Bool {
        guard store.isDirty else {
            return true
        }

        isConfirmingClose = true
        defer {
            isConfirmingClose = false
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "保存未完成的修改？"
        alert.informativeText = "当前提示词模板有未保存修改。关闭设置前请选择保存、放弃或取消。"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "放弃修改")
        alert.addButton(withTitle: "取消")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return store.save()
        case .alertSecondButtonReturn:
            store.discardChanges()
            return true
        default:
            return false
        }
    }
}

private final class SettingsHostingView<Content: View>: NSHostingView<Content> {
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
