public struct ScreenPoint: Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct ScreenRect: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public func contains(_ point: ScreenPoint) -> Bool {
        point.x >= x &&
            point.x <= x + width &&
            point.y >= y &&
            point.y <= y + height
    }

    public var minX: Double {
        x
    }

    public var maxX: Double {
        x + width
    }
}

public enum CompactEntryDismissPolicy {
    public static let escapeKeyCode: UInt16 = 53

    public static func shouldDismissForKeyDown(keyCode: UInt16) -> Bool {
        keyCode == escapeKeyCode
    }

    public static func shouldDismissForMouseDown(at point: ScreenPoint, panelFrame: ScreenRect) -> Bool {
        !panelFrame.contains(point)
    }
}

public enum PanelPlacement: Equatable, Sendable {
    case attached(SideAttachment)
    case free
}

public enum PanelPlacementPolicy {
    public static let defaultSnapDistance = 36.0

    public static func placement(
        for panelFrame: ScreenRect,
        in screenFrame: ScreenRect,
        snapDistance: Double = defaultSnapDistance
    ) -> PanelPlacement {
        if abs(panelFrame.minX - screenFrame.minX) <= snapDistance {
            return .attached(.left)
        }

        if abs(screenFrame.maxX - panelFrame.maxX) <= snapDistance {
            return .attached(.right)
        }

        return .free
    }
}
