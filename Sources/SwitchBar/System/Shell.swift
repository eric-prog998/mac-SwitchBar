import AppKit

/// 运行系统自带的命令行工具。
/// 直接传参数数组、不经过 shell 解释，所以不存在命令注入问题。
/// 用到的命令只有：defaults、killall、pmset、shortcuts（均为 macOS 自带，见 scripts/audit.sh 的输出）。
/// 所有参数都是写死的或来自你自己的设置，不会执行任何外部传入的内容。
enum Shell {
    struct Result {
        let status: Int32
        let output: String
    }

    @discardableResult
    static func run(_ executable: String, _ arguments: [String]) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            NSLog("SwitchBar: 无法运行 \(executable)：\(error)")
            return Result(status: -1, output: "")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Result(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }
}

/// 执行 AppleScript（只用来控制「系统事件」里的外观和程序坞设置）
enum AppleScript {
    /// 成功返回 nil，失败返回给用户看的错误信息
    static func run(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else { return "脚本无效" }
        var error: NSDictionary?
        _ = script.executeAndReturnError(&error)
        guard let error else { return nil }
        let code = (error[NSAppleScript.errorNumber] as? Int) ?? 0
        NSLog("SwitchBar: AppleScript 错误 \(error)")
        if code == -1743 || code == -1744 {
            return "SwitchBar 还没有控制「系统事件」的权限：请到 系统设置 › 隐私与安全性 › 自动化 中打开。"
        }
        return "操作失败（AppleScript 错误 \(code)）"
    }
}

/// 读取其他系统组件（访达、程序坞）的偏好设置
enum ForeignPrefs {
    static func bool(_ key: String, domain: String, default defaultValue: Bool) -> Bool {
        // 先丢掉本进程里的缓存，确保读到的是最新值
        CFPreferencesAppSynchronize(domain as CFString)
        guard let value = CFPreferencesCopyAppValue(key as CFString, domain as CFString) else {
            return defaultValue
        }
        if let number = value as? NSNumber { return number.boolValue }
        if let string = value as? String { return ["1", "true", "yes"].contains(string.lowercased()) }
        return defaultValue
    }
}

/// 访达：隐藏桌面图标、显示隐藏文件
enum Finder {
    static var isDesktopHidden: Bool {
        !ForeignPrefs.bool("CreateDesktop", domain: "com.apple.finder", default: true)
    }

    static var showsHiddenFiles: Bool {
        ForeignPrefs.bool("AppleShowAllFiles", domain: "com.apple.finder", default: false)
    }

    static func setDesktopHidden(_ hidden: Bool) {
        write("CreateDesktop", !hidden)
    }

    static func setShowsHiddenFiles(_ show: Bool) {
        write("AppleShowAllFiles", show)
    }

    /// 等价于终端里的 defaults write com.apple.finder … && killall Finder
    private static func write(_ key: String, _ value: Bool) {
        Shell.run("/usr/bin/defaults", ["write", "com.apple.finder", key, "-bool", value ? "true" : "false"])
        Shell.run("/usr/bin/killall", ["Finder"])
    }
}

/// 深色模式
enum Appearance {
    static var isDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    static func setDark(_ dark: Bool) -> String? {
        AppleScript.run("tell application \"System Events\" to tell appearance preferences to set dark mode to \(dark)")
    }
}

/// 程序坞自动隐藏
enum Dock {
    static var isAutoHidden: Bool {
        ForeignPrefs.bool("autohide", domain: "com.apple.dock", default: false)
    }

    static func setAutoHide(_ hide: Bool) -> String? {
        AppleScript.run("tell application \"System Events\" to set autohide of dock preferences to \(hide)")
    }
}

/// 菜单栏自动隐藏（和「系统设置 › 控制中心 › 自动隐藏和显示菜单栏」是同一个设置）
enum MenuBar {
    static var isAutoHidden: Bool {
        ForeignPrefs.bool("_HIHideMenuBar", domain: kCFPreferencesAnyApplication as String, default: false)
    }

    static func setAutoHide(_ hide: Bool) -> String? {
        AppleScript.run("tell application \"System Events\" to set autohide menu bar of dock preferences to \(hide)")
    }
}

/// 屏幕保护程序
enum ScreenSaver {
    static func start() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app"))
    }
}

/// 打开「系统设置」里的某个页面
enum SystemSettings {
    enum Pane: String {
        case accessibility = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case automation = "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
        case bluetoothPrivacy = "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth"
        case bluetooth = "x-apple.systempreferences:com.apple.BluetoothSettings"
        case loginItems = "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
        case screenRecording = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        case inputMonitoring = "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
    }

    static func open(_ pane: Pane) {
        if let url = URL(string: pane.rawValue) {
            NSWorkspace.shared.open(url)
        }
    }
}
