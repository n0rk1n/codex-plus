import AppKit
import CodexPlusCore
import SwiftUI

@MainActor
final class CompactPanelController {
    private let panelFactory: PanelFactory
    private let screenProvider: ActiveScreenProvider
    private let batteryMonitor: BatteryStatusMonitor
    private let codexUsageMonitor: CodexUsageMonitor
    private let codexDesktopLauncher = CodexDesktopLauncher()
    private weak var panelDelegate: NSWindowDelegate?

    private var panel: GlassPanel?
    private var storedFrame: NSRect?
    private let dismissMonitors = EventMonitorStore()

    init(
        panelFactory: PanelFactory,
        screenProvider: ActiveScreenProvider,
        batteryMonitor: BatteryStatusMonitor,
        codexUsageMonitor: CodexUsageMonitor,
        panelDelegate: NSWindowDelegate?
    ) {
        self.panelFactory = panelFactory
        self.screenProvider = screenProvider
        self.batteryMonitor = batteryMonitor
        self.codexUsageMonitor = codexUsageMonitor
        self.panelDelegate = panelDelegate
    }

    deinit {
        dismissMonitors.removeAll()
    }

    func show(onSubmit: @escaping (String) -> Void) {
        guard let screen = screenProvider.activeScreen() else {
            return
        }

        let frame = storedFrame ?? Self.defaultFrame(on: screen)
        let panel = panel ?? panelFactory.makePanel(frame: frame, delegate: panelDelegate)

        batteryMonitor.start()
        panel.isMovableByWindowBackground = false
        panel.setFrame(frame, display: true)
        let contentView = DraggableHostingView(
            rootView: CompactEntryHostView(
                batteryMonitor: batteryMonitor,
                codexUsageMonitor: codexUsageMonitor,
                onOpenCodexDesktop: { [weak self] in
                    self?.openCodexDesktopAndDismiss()
                },
                onSubmit: onSubmit
            )
        )
        contentView.windowDragMode = .compactPrompt
        panel.contentView = contentView
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
        installDismissMonitorsIfNeeded()
    }

    func dismiss() {
        panel?.orderOut(nil)
        batteryMonitor.stop()
        dismissMonitors.removeAll()
    }

    func recordMove(of movedPanel: GlassPanel) -> Bool {
        guard movedPanel === panel else {
            return false
        }

        storedFrame = movedPanel.frame
        return true
    }

    private static func defaultFrame(on screen: NSScreen) -> NSRect {
        let size = NSSize(width: 420, height: 210)
        let visibleFrame = screen.visibleFrame
        let origin = NSPoint(
            x: visibleFrame.midX - (size.width / 2),
            y: visibleFrame.maxY - (visibleFrame.height / 3) - (size.height / 2)
        )

        return NSRect(origin: origin, size: size)
    }

    private func openCodexDesktopAndDismiss() {
        codexDesktopLauncher.open()
        dismiss()
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

            self.dismiss()
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

        if CompactEntryDismissPolicy.shouldDismissForMouseDown(at: point, panelFrame: panel.frame) {
            dismiss()
        }
    }
}
