import Foundation

/// 面板中的一个开关或动作。rawValue 会存进偏好设置，不要随意改名。
enum FeatureID: String, CaseIterable, Codable, Identifiable {
    case hideDesktop
    case darkMode
    case keepAwake
    case doNotDisturb
    case nightShift
    case micMute
    case bluetoothAudio
    case hiddenFiles
    case fileExtensions
    case autoHideDock
    case autoHideMenuBar
    case lockScreen
    case displaySleep
    case screenSaver
    case sleepNow
    case cleanScreen
    case colorPicker
    case plainText
    case audioOutput

    enum Kind {
        /// 有开 / 关两种状态
        case toggle
        /// 点一下执行一次
        case action
        /// 点一下弹出菜单
        case menu
    }

    var id: String { rawValue }

    var kind: Kind {
        switch self {
        case .lockScreen, .displaySleep, .screenSaver, .sleepNow, .cleanScreen, .colorPicker, .plainText:
            return .action
        case .audioOutput:
            return .menu
        default:
            return .toggle
        }
    }

    var title: String {
        switch self {
        case .hideDesktop: return "隐藏桌面"
        case .darkMode: return "深色模式"
        case .keepAwake: return "保持亮屏"
        case .doNotDisturb: return "勿扰模式"
        case .nightShift: return "夜览"
        case .micMute: return "麦克风静音"
        case .bluetoothAudio: return "蓝牙耳机"
        case .hiddenFiles: return "显示隐藏文件"
        case .fileExtensions: return "显示扩展名"
        case .autoHideDock: return "隐藏程序坞"
        case .autoHideMenuBar: return "隐藏菜单栏"
        case .lockScreen: return "锁定屏幕"
        case .displaySleep: return "关闭显示器"
        case .screenSaver: return "屏幕保护"
        case .sleepNow: return "睡眠"
        case .cleanScreen: return "清洁屏幕"
        case .colorPicker: return "取色器"
        case .plainText: return "纯文本"
        case .audioOutput: return "声音设备"
        }
    }

    /// 设置里显示的一句话说明
    var detail: String {
        switch self {
        case .hideDesktop: return "一键隐藏桌面上的所有文件和图标"
        case .darkMode: return "在深色和浅色外观之间切换"
        case .keepAwake: return "阻止屏幕自动变暗和休眠"
        case .doNotDisturb: return "通过「快捷指令」开关勿扰模式"
        case .nightShift: return "让屏幕颜色偏暖，晚上更护眼"
        case .micMute: return "静音当前的麦克风"
        case .bluetoothAudio: return "一键连接或断开 AirPods 等耳机"
        case .hiddenFiles: return "在访达里显示以 . 开头的隐藏文件"
        case .fileExtensions: return "在访达里显示所有文件的扩展名（.pdf、.zip……）"
        case .autoHideDock: return "自动隐藏程序坞，腾出屏幕空间"
        case .autoHideMenuBar: return "自动隐藏菜单栏，刘海屏上看视频更干净"
        case .lockScreen: return "立即锁定屏幕"
        case .displaySleep: return "立即关闭显示器，电脑继续运行（下载、音乐不中断）"
        case .screenSaver: return "立即启动屏幕保护程序"
        case .sleepNow: return "让电脑立即睡眠"
        case .cleanScreen: return "黑屏并锁住键盘，放心擦屏幕"
        case .colorPicker: return "吸取屏幕上任意一点的颜色，复制色值（#RRGGBB）"
        case .plainText: return "去掉剪贴板里文字的字体、颜色、链接等格式，粘贴时只剩纯文字"
        case .audioOutput: return "切换扬声器、耳机、显示器音箱和麦克风"
        }
    }

    /// SF Symbols 图标名
    func symbol(on: Bool) -> String {
        switch self {
        case .hideDesktop: return on ? "folder.badge.minus" : "folder"
        case .darkMode: return on ? "moon.fill" : "moon"
        case .keepAwake: return on ? "cup.and.saucer.fill" : "cup.and.saucer"
        case .doNotDisturb: return on ? "bell.slash.fill" : "bell"
        case .nightShift: return on ? "sunset.fill" : "sunset"
        case .micMute: return on ? "mic.slash.fill" : "mic"
        case .bluetoothAudio: return "headphones"
        case .hiddenFiles: return on ? "eye" : "eye.slash"
        case .fileExtensions: return on ? "doc.text.fill" : "doc.text"
        case .autoHideDock: return on ? "dock.arrow.down.rectangle" : "dock.rectangle"
        case .autoHideMenuBar: return on ? "menubar.arrow.up.rectangle" : "menubar.rectangle"
        case .lockScreen: return "lock"
        case .displaySleep: return "display"
        case .screenSaver: return "photo.on.rectangle"
        case .sleepNow: return "moon.zzz"
        case .cleanScreen: return "sparkles"
        case .colorPicker: return "eyedropper"
        case .plainText: return "doc.plaintext"
        case .audioOutput: return "hifispeaker.2"
        }
    }

    /// 是否有「更多选项」菜单（面板里开关右边的「›」）
    var hasOptions: Bool {
        switch self {
        case .keepAwake, .doNotDisturb, .bluetoothAudio, .plainText:
            return true
        default:
            return false
        }
    }

    var supportsHotKey: Bool { kind != .menu }

    /// macOS 自带的快捷键（这些功能不一定需要再设置 SwitchBar 的快捷键）
    var systemShortcut: String? {
        switch self {
        case .lockScreen: return "系统自带 ⌃⌘Q"
        case .autoHideDock: return "系统自带 ⌥⌘D"
        case .hiddenFiles: return "访达里自带 ⇧⌘."
        case .doNotDisturb: return "MacBook 键盘上的 🌙 键（F6）"
        case .displaySleep: return "系统自带 ⌃⇧ + 电源键"
        case .sleepNow: return "系统自带 ⌥⌘ + 电源键"
        default: return nil
        }
    }
}
