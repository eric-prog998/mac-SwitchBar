import Foundation

/// 面板中的一个开关或动作。rawValue 会存进偏好设置，不要随意改名。
enum FeatureID: String, CaseIterable, Codable, Identifiable {
    case hideDesktop
    case darkMode
    case keepAwake
    case doNotDisturb
    case nightShift
    case trueTone
    case micMute
    case muteSound
    case bluetoothAudio
    case hiddenFiles
    case autoHideDock
    case autoHideMenuBar
    case lockScreen
    case lockKeyboard
    case cleanScreen
    case ejectDisks
    case screenSaver
    case displayResolution

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
        case .lockScreen, .lockKeyboard, .cleanScreen, .ejectDisks, .screenSaver:
            return .action
        case .displayResolution:
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
        case .trueTone: return "原彩显示"
        case .micMute: return "麦克风静音"
        case .muteSound: return "静音"
        case .bluetoothAudio: return "蓝牙耳机"
        case .hiddenFiles: return "显示隐藏文件"
        case .autoHideDock: return "隐藏程序坞"
        case .autoHideMenuBar: return "隐藏菜单栏"
        case .lockScreen: return "锁定屏幕"
        case .lockKeyboard: return "锁定键盘"
        case .cleanScreen: return "清洁屏幕"
        case .ejectDisks: return "推出磁盘"
        case .screenSaver: return "屏幕保护"
        case .displayResolution: return "分辨率"
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
        case .trueTone: return "根据环境光自动调整屏幕色温"
        case .micMute: return "静音当前的麦克风"
        case .muteSound: return "静音当前的扬声器或耳机"
        case .bluetoothAudio: return "一键连接或断开 AirPods 等耳机"
        case .hiddenFiles: return "在访达里显示以 . 开头的隐藏文件"
        case .autoHideDock: return "自动隐藏程序坞，腾出屏幕空间"
        case .autoHideMenuBar: return "自动隐藏菜单栏，刘海屏上看视频、演示更干净"
        case .lockScreen: return "立即锁定屏幕"
        case .lockKeyboard: return "擦键盘或防猫踩时暂时锁住按键"
        case .cleanScreen: return "黑屏并锁住键盘，放心擦屏幕"
        case .ejectDisks: return "推出外接硬盘、U 盘和磁盘映像"
        case .screenSaver: return "立即启动屏幕保护程序"
        case .displayResolution: return "切换每台显示器的分辨率"
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
        case .trueTone: return on ? "sun.max.fill" : "sun.max"
        case .micMute: return on ? "mic.slash.fill" : "mic"
        case .muteSound: return on ? "speaker.slash.fill" : "speaker.wave.2"
        case .bluetoothAudio: return "headphones"
        case .hiddenFiles: return on ? "eye" : "eye.slash"
        case .autoHideDock: return on ? "dock.arrow.down.rectangle" : "dock.rectangle"
        case .autoHideMenuBar: return on ? "menubar.arrow.up.rectangle" : "menubar.rectangle"
        case .lockScreen: return "lock"
        case .lockKeyboard: return "keyboard"
        case .cleanScreen: return "sparkles"
        case .ejectDisks: return "eject"
        case .screenSaver: return "tv"
        case .displayResolution: return "aspectratio"
        }
    }

    /// 图标右上角是否有「更多选项」小箭头
    var hasOptions: Bool {
        switch self {
        case .keepAwake, .doNotDisturb, .bluetoothAudio, .ejectDisks:
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
        case .muteSound: return "键盘上的静音键（F10）"
        default: return nil
        }
    }
}
