import SwiftUI

final class DraggableHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool {
        true
    }
}
