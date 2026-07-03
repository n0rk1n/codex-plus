import Foundation

public enum BatteryChargingState: String, Equatable, Sendable {
    case charging
    case discharging
    case full
    case pluggedIn
    case unknown
}

public struct BatteryStatus: Equatable, Sendable {
    public let percentage: Int?
    public let state: BatteryChargingState

    public init(percentage: Int?, state: BatteryChargingState) {
        self.percentage = percentage
        self.state = state
    }

    public static let unknown = BatteryStatus(percentage: nil, state: .unknown)

    public static func from(
        currentCapacity: Int?,
        maxCapacity: Int?,
        isCharging: Bool?,
        powerSourceState: String?
    ) -> BatteryStatus {
        guard let currentCapacity, let maxCapacity, maxCapacity > 0 else {
            return .unknown
        }

        let rawPercentage = (Double(currentCapacity) / Double(maxCapacity)) * 100.0
        let percentage = max(0, min(100, Int(rawPercentage)))

        if percentage >= 100 {
            return BatteryStatus(percentage: percentage, state: .full)
        }

        if isCharging == true {
            return BatteryStatus(percentage: percentage, state: .charging)
        }

        if powerSourceState == "Battery Power" {
            return BatteryStatus(percentage: percentage, state: .discharging)
        }

        if powerSourceState == "AC Power" {
            return BatteryStatus(percentage: percentage, state: .pluggedIn)
        }

        return BatteryStatus(percentage: percentage, state: .unknown)
    }
}

public protocol BatteryStatusProviding: Sendable {
    func currentStatus() -> BatteryStatus
}
