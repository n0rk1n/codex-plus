import Foundation

public enum CodexUsageWindow: Equatable, Sendable {
    case fiveHour
    case weekly
}

public struct CodexUsageRingColor: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let opacity: Double

    public init(red: Double, green: Double, blue: Double, opacity: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }

    public static let lowUsageGreen = CodexUsageRingColor(red: 0.20, green: 0.78, blue: 0.35)
    public static let midUsageYellow = CodexUsageRingColor(red: 1.00, green: 0.84, blue: 0.20)
    public static let highUsageRed = CodexUsageRingColor(red: 1.00, green: 0.23, blue: 0.19)
    public static let inactive = CodexUsageRingColor(red: 0.55, green: 0.55, blue: 0.58, opacity: 0.38)
}

public struct CodexUsageStatus: Equatable, Sendable {
    public let fiveHourPercent: Int?
    public let weeklyPercent: Int?
    public let observedAt: Date?

    public init(fiveHourPercent: Int?, weeklyPercent: Int?, observedAt: Date?) {
        self.fiveHourPercent = Self.clamped(fiveHourPercent)
        self.weeklyPercent = Self.clamped(weeklyPercent)
        self.observedAt = observedAt
    }

    public static let unknown = CodexUsageStatus(
        fiveHourPercent: nil,
        weeklyPercent: nil,
        observedAt: nil
    )

    public func percent(for window: CodexUsageWindow) -> Int? {
        switch window {
        case .fiveHour:
            return fiveHourPercent
        case .weekly:
            return weeklyPercent
        }
    }

    public func displayPercentText(for window: CodexUsageWindow) -> String {
        guard let percent = percent(for: window) else {
            return "--%"
        }

        return "\(percent)%"
    }

    public func ringColor(for window: CodexUsageWindow) -> CodexUsageRingColor {
        guard let percent = percent(for: window) else {
            return .inactive
        }

        if percent <= 60 {
            return .lowUsageGreen
        }

        if percent == 80 {
            return .midUsageYellow
        }

        if percent < 80 {
            return Self.interpolate(
                from: .lowUsageGreen,
                to: .midUsageYellow,
                progress: Double(percent - 60) / 20.0
            )
        }

        if percent >= 100 {
            return .highUsageRed
        }

        return Self.interpolate(
            from: .midUsageYellow,
            to: .highUsageRed,
            progress: Double(percent - 80) / 20.0
        )
    }

    private static func clamped(_ percent: Int?) -> Int? {
        guard let percent else {
            return nil
        }

        return max(0, min(100, percent))
    }

    private static func interpolate(
        from start: CodexUsageRingColor,
        to end: CodexUsageRingColor,
        progress: Double
    ) -> CodexUsageRingColor {
        let clampedProgress = max(0, min(1, progress))

        return CodexUsageRingColor(
            red: start.red + ((end.red - start.red) * clampedProgress),
            green: start.green + ((end.green - start.green) * clampedProgress),
            blue: start.blue + ((end.blue - start.blue) * clampedProgress),
            opacity: start.opacity + ((end.opacity - start.opacity) * clampedProgress)
        )
    }
}
