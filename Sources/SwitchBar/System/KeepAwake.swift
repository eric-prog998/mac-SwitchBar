import Foundation
import IOKit.pwr_mgt

/// 保持亮屏：向系统申请「阻止显示器因闲置而休眠」，和系统自带的 caffeinate -d 是同一个机制
final class KeepAwake {
    private var assertionID = IOPMAssertionID(0)
    private var timer: Timer?
    private(set) var isActive = false
    private(set) var endDate: Date?

    /// 定时结束时通知外部刷新
    var onChange: (() -> Void)?

    /// minutes 为 0 表示一直保持
    @discardableResult
    func start(minutes: Int) -> Bool {
        stop(notify: false)
        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "SwitchBar 保持亮屏" as CFString,
            &id
        )
        guard result == kIOReturnSuccess else { return false }
        assertionID = id
        isActive = true
        if minutes > 0 {
            let interval = TimeInterval(minutes * 60)
            endDate = Date().addingTimeInterval(interval)
            timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
                self?.stop()
            }
        }
        return true
    }

    func stop(notify: Bool = true) {
        timer?.invalidate()
        timer = nil
        endDate = nil
        guard isActive else { return }
        IOPMAssertionRelease(assertionID)
        isActive = false
        if notify { onChange?() }
    }

    var remainingMinutes: Int? {
        guard let endDate else { return nil }
        return max(0, Int((endDate.timeIntervalSinceNow / 60).rounded(.up)))
    }
}
