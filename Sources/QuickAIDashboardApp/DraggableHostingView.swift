import AppKit
import QuickAIDashboardCore
import SwiftUI

final class DraggableHostingView<Content: View>: NSHostingView<Content> {
    enum WindowDragMode {
        case automatic
        case compactPrompt
    }

    var windowDragMode = WindowDragMode.automatic

    override var mouseDownCanMoveWindow: Bool {
        switch windowDragMode {
        case .automatic:
            return true
        case .compactPrompt:
            return false
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard shouldPerformManualWindowDrag(for: event) else {
            super.mouseDown(with: event)
            return
        }

        window?.performDrag(with: event)
    }

    private func shouldPerformManualWindowDrag(for event: NSEvent) -> Bool {
        switch windowDragMode {
        case .automatic:
            return false
        case .compactPrompt:
            return CompactDashboardTileDragPolicy.shouldMoveWindowFromMouseDown(
                at: localPoint(from: event),
                panelBounds: currentLocalBounds(),
                verticalOrigin: isFlipped ? .top : .bottom
            )
        }
    }

    private func localPoint(from event: NSEvent) -> ScreenPoint {
        let localPoint = convert(event.locationInWindow, from: nil)

        return ScreenPoint(x: Double(localPoint.x), y: Double(localPoint.y))
    }

    private func currentLocalBounds() -> ScreenRect {
        ScreenRect(
            x: 0,
            y: 0,
            width: Double(bounds.width),
            height: Double(bounds.height)
        )
    }
}
