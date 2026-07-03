import AppKit
import QuickAIDashboardCore
import SwiftUI

final class DraggableHostingView<Content: View>: NSHostingView<Content> {
    var blocksWindowDragOnCompactDashboardTiles = false

    override var mouseDownCanMoveWindow: Bool {
        guard blocksWindowDragOnCompactDashboardTiles else {
            return true
        }

        return CompactDashboardTileDragPolicy.shouldMoveWindowFromMouseDown(
            at: currentLocalMousePoint(),
            panelBounds: currentLocalBounds(),
            verticalOrigin: isFlipped ? .top : .bottom
        )
    }

    private func currentLocalMousePoint() -> ScreenPoint {
        let windowPoint = NSApp.currentEvent?.locationInWindow ?? window?.mouseLocationOutsideOfEventStream ?? .zero
        let localPoint = convert(windowPoint, from: nil)

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
