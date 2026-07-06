import AppKit
import CodexPlusCore
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

        performCompactPromptDrag(from: event)
    }

    private func shouldPerformManualWindowDrag(for event: NSEvent) -> Bool {
        switch windowDragMode {
        case .automatic:
            return false
        case .compactPrompt:
            return CompactDashboardTileDragPolicy.shouldMoveWindowFromMouseDown(
                at: convert(event.locationInWindow, from: nil),
                panelBounds: bounds,
                verticalOrigin: isFlipped ? .top : .bottom
            )
        }
    }

    private func performCompactPromptDrag(from initialEvent: NSEvent) {
        guard let window else {
            return
        }

        let initialFrame = window.frame
        let initialMouseLocation = window.convertPoint(toScreen: initialEvent.locationInWindow)
        var wasSnapped = false

        while true {
            guard let nextEvent = window.nextEvent(
                matching: [.leftMouseDragged, .leftMouseUp],
                until: .distantFuture,
                inMode: .eventTracking,
                dequeue: true
            ) else {
                return
            }

            switch nextEvent.type {
            case .leftMouseDragged:
                let mouseLocation = window.convertPoint(toScreen: nextEvent.locationInWindow)
                let proposedFrame = initialFrame.offsetBy(
                    dx: mouseLocation.x - initialMouseLocation.x,
                    dy: mouseLocation.y - initialMouseLocation.y
                )
                let dragResult = compactPromptDragResult(for: proposedFrame, window: window)
                if dragResult.isSnapped && !wasSnapped {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                }
                wasSnapped = dragResult.isSnapped
                window.setFrame(dragResult.frame, display: true)
            case .leftMouseUp:
                return
            default:
                break
            }
        }
    }

    private func compactPromptDragResult(for proposedFrame: NSRect, window: NSWindow) -> (frame: NSRect, isSnapped: Bool) {
        let screenFrame = (screen(containing: proposedFrame) ?? window.screen ?? NSScreen.main)?.visibleFrame
        guard let screenFrame else {
            return (proposedFrame, false)
        }

        let snappedFrame = CompactPanelSnapPolicy.snappedFrame(
            for: proposedFrame,
            in: screenFrame
        )
        let frame = snappedFrame
        return (frame, abs(frame.midX - screenFrame.midX) < 0.5)
    }

    private func screen(containing frame: NSRect) -> NSScreen? {
        NSScreen.screens.max { first, second in
            first.visibleFrame.intersection(frame).area < second.visibleFrame.intersection(frame).area
        }
    }
}

private extension NSRect {
    var area: CGFloat {
        width * height
    }
}
