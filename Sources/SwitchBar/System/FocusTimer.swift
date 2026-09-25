import AppKit

/// 专注计时（番茄钟）：倒计时结束时提醒你休息一下
final class FocusTimer {
    private(set) var endDate: Date?
    private(set) var duration: TimeInterval = 0
    private var ticker: Timer?

    /// 每秒调用一次（用来更新菜单栏上的倒计时）
    var onTick: (() -> Void)?
    /// 计时结束或被停止时调用；参数表示是否是正常走完
    var onEnd: ((Bool) -> Void)?

    var isRunning: Bool { endDate != nil }

    var remaining: TimeInterval {
        guard let endDate else { return 0 }
        return max(0, endDate.timeIntervalSinceNow)
    }

    /// 已经走过的比例（0…1）
    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, 1 - remaining / duration))
    }

    func start(minutes: Int) {
        stopTicker()
        duration = TimeInterval(max(1, minutes) * 60)
        endDate = Date().addingTimeInterval(duration)
        startTicker()
        onTick?()
    }

    /// 再加几分钟
    func extend(minutes: Int) {
        guard let endDate else { return }
        let extra = TimeInterval(minutes * 60)
        self.endDate = endDate.addingTimeInterval(extra)
        duration += extra
        onTick?()
    }

    func stop() {
        guard isRunning else { return }
        finish(completed: false)
    }

    private func startTicker() {
        let ticker = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.remaining <= 0 {
                self.finish(completed: true)
            } else {
                self.onTick?()
            }
        }
        // 放进 common 模式，打开菜单时倒计时也不会停
        RunLoop.main.add(ticker, forMode: .common)
        self.ticker = ticker
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func finish(completed: Bool) {
        stopTicker()
        endDate = nil
        duration = 0
        onTick?()
        onEnd?(completed)
    }

    /// 倒计时文字，例如 24:59
    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
