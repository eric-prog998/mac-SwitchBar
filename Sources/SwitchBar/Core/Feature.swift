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
    case bluetoothAudio
    case hiddenFiles
    case autoHideDock
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
        case .bluetoothAudio: return "蓝牙耳机"
        case .hiddenFiles: return "显示隐藏文件"
        case .autoHideDock: return "隐藏程序坞"
        case .lockScreen: return "锁定屏幕"
        case .lockKeyboard: return "锁定键盘"
        case .cleanScreen: return "清洁屏幕"
        case .ejectDisks: return "推出磁盘"
        case .screenSaver: return "屏幕保护"
        case .displayResolution: return "分辨率"
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
        case .bluetoothAudio: return "headphones"
        case .hiddenFiles: return on ? "eye" : "eye.slash"
        case .autoHideDock: return on ? "dock.arrow.down.rectangle" : "dock.rectangle"
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
}
