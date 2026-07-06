import AppKit
import CodexPlusCore
import SwiftUI

enum WorkbenchLauncherMetrics {
    static let panelSize = CGFloat(48)
    static let sphereSize = CGFloat(38)
    static let dragThreshold = CGFloat(3)
}

@MainActor
final class WorkbenchLauncherPanelController {
    private static let cachedFrameKey = "WorkbenchLauncherPanelController.cachedFrame"

    private let screenProvider: ActiveScreenProvider
    private let defaults: UserDefaults
    private weak var panelDelegate: NSWindowDelegate?
    private let onOpenWorkbench: () -> Void

    private var panel: GlassPanel?

    init(
        screenProvider: ActiveScreenProvider,
        defaults: UserDefaults = .standard,
        panelDelegate: NSWindowDelegate?,
        onOpenWorkbench: @escaping () -> Void
    ) {
        self.screenProvider = screenProvider
        self.defaults = defaults
        self.panelDelegate = panelDelegate
        self.onOpenWorkbench = onOpenWorkbench
    }

    var isVisible: Bool {
        panel?.isVisible == true
    }

    func show() {
        guard let screen = screenProvider.activeScreen() else {
            return
        }

        let defaultFrame = Self.defaultFrame(in: screen.visibleFrame)
        let frame = WorkbenchLauncherFramePolicy.frame(
            cachedFrame: cachedFrame(),
            defaultFrame: defaultFrame,
            visibleFrames: NSScreen.screens.map(\.visibleFrame)
        )
        let panel = panel ?? makePanel(frame: frame)
        panel.isMovableByWindowBackground = false
        panel.setFrame(frame, display: true)
        panel.contentView = WorkbenchLauncherHostingView(rootView: WorkbenchLauncherView(), onClick: onOpenWorkbench)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func recordMove(of movedPanel: GlassPanel) -> Bool {
        guard movedPanel === panel else {
            return false
        }

        cacheFrame(movedPanel.frame)
        return true
    }

    static func defaultFrame(in visibleFrame: NSRect) -> NSRect {
        let size = WorkbenchLauncherMetrics.panelSize
        let inset = CGFloat(28)

        return NSRect(
            x: visibleFrame.maxX - size - inset,
            y: visibleFrame.minY + inset,
            width: size,
            height: size
        )
    }

    private func makePanel(frame: NSRect) -> GlassPanel {
        let panel = WorkbenchLauncherPanel(contentRect: frame)
        panel.acceptsMouseMovedEvents = true
        panel.delegate = panelDelegate
        return panel
    }

    private func cachedFrame() -> NSRect? {
        guard let string = defaults.string(forKey: Self.cachedFrameKey), !string.isEmpty else {
            return nil
        }

        return NSRectFromString(string)
    }

    private func cacheFrame(_ frame: NSRect) {
        defaults.set(NSStringFromRect(frame), forKey: Self.cachedFrameKey)
    }
}

private final class WorkbenchLauncherPanel: GlassPanel {
    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }
}

private final class WorkbenchLauncherHostingView<Content: View>: NSHostingView<Content> {
    private var onClick: () -> Void = {}

    required init(rootView: Content) {
        super.init(rootView: rootView)
        configureTransparentBacking()
    }

    convenience init(rootView: Content, onClick: @escaping () -> Void) {
        self.init(rootView: rootView)
        self.onClick = onClick
    }

    @available(*, unavailable)
    required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    private func configureTransparentBacking() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false
    }

    override func mouseDown(with event: NSEvent) {
        performWindowDrag(from: event)
    }

    private func performWindowDrag(from initialEvent: NSEvent) {
        guard let window else {
            onClick()
            return
        }

        let initialFrame = window.frame
        let initialMouseLocation = window.convertPoint(toScreen: initialEvent.locationInWindow)
        var didDrag = false

        while true {
            guard let nextEvent = window.nextEvent(
                matching: [.leftMouseDragged, .leftMouseUp],
                until: .distantFuture,
                inMode: .eventTracking,
                dequeue: true
            ) else {
                return
            }

            let mouseLocation = window.convertPoint(toScreen: nextEvent.locationInWindow)
            let deltaX = mouseLocation.x - initialMouseLocation.x
            let deltaY = mouseLocation.y - initialMouseLocation.y

            switch nextEvent.type {
            case .leftMouseDragged:
                if hypot(deltaX, deltaY) >= WorkbenchLauncherMetrics.dragThreshold {
                    didDrag = true
                }
                window.setFrame(initialFrame.offsetBy(dx: deltaX, dy: deltaY), display: true)
            case .leftMouseUp:
                if !didDrag {
                    onClick()
                }
                return
            default:
                break
            }
        }
    }
}
