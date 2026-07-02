import Foundation
import IOKit.ps

public enum BatteryChargingState: String, Equatable, Sendable {
    case charging
    case discharging
    case full
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

        if powerSourceState == (kIOPSBatteryPowerValue as String) || powerSourceState == "Battery Power" {
            return BatteryStatus(percentage: percentage, state: .discharging)
        }

        return BatteryStatus(percentage: percentage, state: .unknown)
    }
}

public protocol BatteryStatusProviding: Sendable {
    func currentStatus() -> BatteryStatus
}

public struct IOKitBatteryStatusProvider: BatteryStatusProviding {
    public init() {}

    public func currentStatus() -> BatteryStatus {
        guard
            let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
            let firstSource = list.first,
            let description = IOPSGetPowerSourceDescription(info, firstSource)?.takeUnretainedValue() as? [String: Any]
        else {
            return .unknown
        }

        let current = description[kIOPSCurrentCapacityKey as String] as? Int
        let max = description[kIOPSMaxCapacityKey as String] as? Int
        let charging = description[kIOPSIsChargingKey as String] as? Bool
        let sourceState = description[kIOPSPowerSourceStateKey as String] as? String

        return BatteryStatus.from(
            currentCapacity: current,
            maxCapacity: max,
            isCharging: charging,
            powerSourceState: sourceState
        )
    }
}
