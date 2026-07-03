import CoreGraphics

public enum CompactEntryDismissPolicy {
    public static let escapeKeyCode: UInt16 = 53

    public static func shouldDismissForKeyDown(keyCode: UInt16) -> Bool {
        keyCode == escapeKeyCode
    }

    public static func shouldDismissForMouseDown(at point: CGPoint, panelFrame: CGRect) -> Bool {
        !panelFrame.containsInclusively(point)
    }
}

public enum PanelPlacement: Equatable, Sendable {
    case attached(SideAttachment)
    case free
}

public enum PanelPlacementPolicy {
    public static let defaultSnapDistance = 36.0

    public static func placement(
        for panelFrame: CGRect,
        in screenFrame: CGRect,
        snapDistance: Double = defaultSnapDistance
    ) -> PanelPlacement {
        let snapDistance = CGFloat(snapDistance)

        if abs(panelFrame.minX - screenFrame.minX) <= snapDistance {
            return .attached(.left)
        }

        if abs(screenFrame.maxX - panelFrame.maxX) <= snapDistance {
            return .attached(.right)
        }

        return .free
    }
}

private extension CGRect {
    func containsInclusively(_ point: CGPoint) -> Bool {
        point.x >= minX &&
            point.x <= maxX &&
            point.y >= minY &&
            point.y <= maxY
    }
}
