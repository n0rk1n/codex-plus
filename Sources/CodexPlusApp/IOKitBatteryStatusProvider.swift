import CodexPlusCore
import IOKit.ps

struct IOKitBatteryStatusProvider: BatteryStatusProviding {
    func currentStatus() -> BatteryStatus {
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
