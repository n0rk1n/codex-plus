import AppKit
import QuickAIDashboardCore
import SwiftUI

@MainActor
final class WindowCoordinator {
    private let conversationCoordinator: ConversationCoordinator
    private let batteryProvider: any BatteryStatusProviding
    private let codexRunner: ProcessCodexRunner

    private var compactPanel: GlassPanel?
    private var sidePanel: GlassPanel?

    init(
        conversationCoordinator: ConversationCoordinator,
        batteryProvider: any BatteryStatusProviding,
        codexRunner: ProcessCodexRunner
    ) {
        self.conversationCoordinator = conversationCoordinator
        self.batteryProvider = batteryProvider
        self.codexRunner = codexRunner
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
        panel.contentView = NSHostingView(rootView: Text("Quick AI Dashboard").padding())
        panel.makeKeyAndOrderFront(nil)
        compactPanel = panel
    }

    private func showSidePanel() {
        compactPanel?.orderOut(nil)

        guard let screen = activeScreen() else {
            return
        }

        let visibleFrame = screen.visibleFrame
        let width: CGFloat = 460
        let frame = NSRect(
            x: visibleFrame.maxX - width,
            y: visibleFrame.minY,
            width: width,
            height: visibleFrame.height
        )
        let panel = sidePanel ?? makePanel(frame: frame)

        panel.setFrame(frame, display: true)
        panel.contentView = NSHostingView(rootView: Text("Conversation").padding())
        panel.makeKeyAndOrderFront(nil)
        sidePanel = panel
    }

    private func makePanel(frame: NSRect) -> GlassPanel {
        GlassPanel(contentRect: frame)
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
