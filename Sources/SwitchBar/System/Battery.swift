import Foundation
import IOKit.ps

/// 读取电池电量（公开的 IOKit 接口，不需要任何权限）。台式机没有电池时返回 nil。
enum Battery {
    struct Status: Equatable {
        let percent: Int
        let isCharging: Bool
        let isPluggedIn: Bool
    }

    static func current() -> Status? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let max = description[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            let charging = description[kIOPSIsChargingKey] as? Bool ?? false
            let pluggedIn = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            return Status(percent: Int((Double(current) / Double(max) * 100).rounded()),
                          isCharging: charging, isPluggedIn: pluggedIn)
        }
        return nil
    }
}
