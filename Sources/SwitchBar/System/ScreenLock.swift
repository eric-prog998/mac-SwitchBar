import Foundation

/// 立即锁定屏幕（效果等同于 ⌃⌘Q）。
/// 优先调用系统 login 框架里的 SACLockScreenImmediate（很多锁屏工具都用它）；
/// 如果将来系统去掉了这个函数，就退回到「让显示器立即休眠」，
/// 这时需要在 系统设置 › 锁定屏幕 里把「显示器关闭后需要密码」设为「立即」。
enum ScreenLock {
    static func lock() {
        let paths = [
            "/System/Library/PrivateFrameworks/login.framework/Versions/Current/login",
            "/System/Library/PrivateFrameworks/login.framework/Versions/A/login",
            "/System/Library/PrivateFrameworks/login.framework/login",
        ]
        for path in paths {
            guard let handle = dlopen(path, RTLD_LAZY),
                  let symbol = dlsym(handle, "SACLockScreenImmediate") else { continue }
            typealias LockFunction = @convention(c) () -> Int32
            _ = unsafeBitCast(symbol, to: LockFunction.self)()
            return
        }
        Power.displaySleepNow()
    }
}
