import AppKit
import Carbon.HIToolbox

/// 一个全局快捷键：虚拟键码 + Carbon 修饰键
struct HotKey: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    var displayString: String {
        KeyNames.modifierSymbols(modifiers) + KeyNames.name(for: keyCode)
    }

    /// 「打开面板」的默认快捷键 ⌃⌥⌘S。
    /// 14 英寸 MacBook Pro 的菜单栏有刘海，图标多时 SwitchBar 可能被挡住，这时可以用它打开面板。
    static let defaultPanel = HotKey(keyCode: UInt32(kVK_ANSI_S),
                                     modifiers: UInt32(controlKey) | UInt32(optionKey) | UInt32(cmdKey))

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        return result
    }
}

extension FeatureID {
    /// 推荐的快捷键：统一用 ⌃⌥ 加一个好记的字母（系统已经自带顺手快捷键的功能、「睡眠」这种按错了很麻烦的不推荐）
    var recommendedHotKey: HotKey? {
        let key: Int
        switch self {
        case .hideDesktop: key = kVK_ANSI_H      // Hide
        case .darkMode: key = kVK_ANSI_D         // Dark
        case .keepAwake: key = kVK_ANSI_C        // Caffeine
        case .doNotDisturb: key = kVK_ANSI_N     // Notifications
        case .nightShift: key = kVK_ANSI_Y       // 夜 yè
        case .micMute: key = kVK_ANSI_M          // Mic
        case .bluetoothAudio: key = kVK_ANSI_A   // AirPods
        case .fileExtensions: key = kVK_ANSI_E   // Extensions
        case .autoHideMenuBar: key = kVK_ANSI_B  // menu Bar
        case .displaySleep: key = kVK_ANSI_O     // Off
        case .cleanScreen: key = kVK_ANSI_Q      // 清 qīng
        case .colorPicker: key = kVK_ANSI_P      // Picker
        case .plainText: key = kVK_ANSI_V        // 和粘贴 ⌘V 同一个键
        default: return nil
        }
        return HotKey(keyCode: UInt32(key), modifiers: UInt32(controlKey) | UInt32(optionKey))
    }
}

/// 快捷键对应的动作
enum HotKeyTarget: Hashable {
    /// 打开 / 关闭面板
    case panel
    /// 切换某个开关
    case feature(FeatureID)
    /// 切换某个场景
    case scene(SceneID)
    /// 开始 / 停止专注计时
    case timer

    /// 除了面板和开关以外的快捷键（单独保存）
    static var extraTargets: [HotKeyTarget] {
        [.timer] + SceneID.allCases.map { .scene($0) }
    }

    /// 全部快捷键目标，顺序固定（注册时用它生成编号）
    static var allTargets: [HotKeyTarget] {
        [.panel] + extraTargets + FeatureID.allCases.map { .feature($0) }
    }

    var storageKey: String {
        switch self {
        case .panel: return "panel"
        case .feature(let feature): return "feature.\(feature.rawValue)"
        case .scene(let scene): return "scene.\(scene.rawValue)"
        case .timer: return "timer"
        }
    }

    /// 推荐快捷键：场景用 ⌃⌥1/2，专注计时用 ⌃⌥T
    var recommendedHotKey: HotKey? {
        let controlOption = UInt32(controlKey) | UInt32(optionKey)
        switch self {
        case .panel: return HotKey.defaultPanel
        case .feature(let feature): return feature.recommendedHotKey
        case .timer: return HotKey(keyCode: UInt32(kVK_ANSI_T), modifiers: controlOption)
        case .scene(let scene):
            let keys: [SceneID: Int] = [.focus: kVK_ANSI_1, .night: kVK_ANSI_2]
            return keys[scene].map { HotKey(keyCode: UInt32($0), modifiers: controlOption) }
        }
    }
}

enum KeyNames {
    static func modifierSymbols(_ modifiers: UInt32) -> String {
        var result = ""
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        return result
    }

    static func name(for keyCode: UInt32) -> String {
        names[keyCode] ?? "键\(keyCode)"
    }

    /// F1–F20 可以不带修饰键单独作为快捷键
    static func isFunctionKey(_ keyCode: UInt32) -> Bool {
        functionKeys.contains(keyCode)
    }

    private static let functionKeys: Set<UInt32> = [
        0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64, 0x65, 0x6D,
        0x67, 0x6F, 0x69, 0x6B, 0x71, 0x6A, 0x40, 0x4F, 0x50, 0x5A,
    ]

    /// 美式键盘布局下的键名（kVK_* 键码）
    private static let names: [UInt32: String] = [
        0x00: "A", 0x0B: "B", 0x08: "C", 0x02: "D", 0x0E: "E", 0x03: "F", 0x05: "G",
        0x04: "H", 0x22: "I", 0x26: "J", 0x28: "K", 0x25: "L", 0x2E: "M", 0x2D: "N",
        0x1F: "O", 0x23: "P", 0x0C: "Q", 0x0F: "R", 0x01: "S", 0x11: "T", 0x20: "U",
        0x09: "V", 0x0D: "W", 0x07: "X", 0x10: "Y", 0x06: "Z",
        0x1D: "0", 0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4",
        0x17: "5", 0x16: "6", 0x1A: "7", 0x1C: "8", 0x19: "9",
        0x18: "=", 0x1B: "-", 0x1E: "]", 0x21: "[", 0x27: "'", 0x29: ";",
        0x2A: "\\", 0x2B: ",", 0x2C: "/", 0x2F: ".", 0x32: "`",
        0x24: "↩", 0x30: "⇥", 0x31: "空格", 0x33: "⌫", 0x35: "⎋", 0x75: "⌦",
        0x73: "↖", 0x77: "↘", 0x74: "⇞", 0x79: "⇟",
        0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑",
        0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4", 0x60: "F5",
        0x61: "F6", 0x62: "F7", 0x64: "F8", 0x65: "F9", 0x6D: "F10",
        0x67: "F11", 0x6F: "F12", 0x69: "F13", 0x6B: "F14", 0x71: "F15",
        0x6A: "F16", 0x40: "F17", 0x4F: "F18", 0x50: "F19", 0x5A: "F20",
        0x52: "小键盘0", 0x53: "小键盘1", 0x54: "小键盘2", 0x55: "小键盘3", 0x56: "小键盘4",
        0x57: "小键盘5", 0x58: "小键盘6", 0x59: "小键盘7", 0x5B: "小键盘8", 0x5C: "小键盘9",
        0x41: "小键盘.", 0x43: "小键盘*", 0x45: "小键盘+", 0x4B: "小键盘/",
        0x4C: "小键盘⌅", 0x4E: "小键盘-", 0x51: "小键盘=",
    ]
}
