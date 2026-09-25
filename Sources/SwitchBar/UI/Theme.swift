import AppKit
import SwiftUI

// 外观：面板背景在 macOS 26 及以上使用系统的「液态玻璃」（Liquid Glass），更早的系统退回到毛玻璃材质；
// 开关本身是彩色的圆角方块，每个开关有自己的颜色，开启时整块变成渐变色并带一点光晕。
// 用 #if compiler 判断：用 Xcode 26 以上编译时才包含玻璃效果的代码，旧版 Xcode 也能正常编译。

enum Theme {
    /// 菜单栏面板、提示框的圆角
    static let panelRadius: CGFloat = 26
    /// 面板里一组开关的底板圆角
    static let platterRadius: CGFloat = 20
    /// 开关方块的圆角
    static let tileRadius: CGFloat = 16

    /// 圆润一点的字体，看起来更轻松
    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

// MARK: - 颜色

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

enum FeatureColors {
    static let timer: [Color] = [Color(hex: 0xFF7A59), Color(hex: 0xFF3D7F)]
    static let warning: [Color] = [Color(hex: 0xFFC53D), Color(hex: 0xFF7A2F)]
    static let neutral: [Color] = [Color(hex: 0x9AA5B8), Color(hex: 0x5B6475)]

    static func pair(_ top: UInt32, _ bottom: UInt32) -> [Color] {
        [Color(hex: top), Color(hex: bottom)]
    }
}

extension FeatureID {
    /// 每个开关自己的渐变色（从左上到右下）
    var colors: [Color] {
        switch self {
        case .hideDesktop: return FeatureColors.pair(0x4FC3FF, 0x3B6BFF)
        case .darkMode: return FeatureColors.pair(0x8C7BFF, 0x5B3BEA)
        case .keepAwake: return FeatureColors.pair(0xFFC24B, 0xFF8A1F)
        case .doNotDisturb: return FeatureColors.pair(0xC77DFF, 0x8B3DFF)
        case .nightShift: return FeatureColors.pair(0xFFB067, 0xFF6A3D)
        case .trueTone: return FeatureColors.pair(0xFFE066, 0xFFB11F)
        case .micMute: return FeatureColors.pair(0xFF7A8A, 0xFF2D55)
        case .muteSound: return FeatureColors.pair(0xFF8FC8, 0xF0368A)
        case .bluetoothAudio: return FeatureColors.pair(0x5AA9FF, 0x2F6BFF)
        case .hiddenFiles: return FeatureColors.pair(0x8FA3BF, 0x55657F)
        case .autoHideDock: return FeatureColors.pair(0x3FE0C5, 0x10A9A0)
        case .autoHideMenuBar: return FeatureColors.pair(0x44D9F0, 0x159FD6)
        case .lockScreen: return FeatureColors.pair(0x8E9BFF, 0x5261E8)
        case .lockKeyboard: return FeatureColors.pair(0xB191FF, 0x7A52F2)
        case .cleanScreen: return FeatureColors.pair(0x5CF0D8, 0x1FB5E0)
        case .ejectDisks: return FeatureColors.pair(0xFF9E7A, 0xFF5C4D)
        case .screenSaver: return FeatureColors.pair(0x7BEA9C, 0x27C27A)
        case .displayResolution: return FeatureColors.pair(0x6FD3FF, 0x2895F2)
        case .audioOutput: return FeatureColors.pair(0xFFA95E, 0xFF4F8B)
        }
    }

    /// 设置列表里图标的主色
    var tint: Color { colors[1] }
}

extension SceneID {
    var colors: [Color] {
        switch self {
        case .present: return FeatureColors.pair(0xFF9A4D, 0xFF3D77)
        case .focus: return FeatureColors.pair(0x6F8BFF, 0xA24BFF)
        case .night: return FeatureColors.pair(0x5B5FEF, 0x2A2475)
        }
    }
}

extension Array where Element == Color {
    var diagonalGradient: LinearGradient {
        LinearGradient(colors: self, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - 玻璃 / 毛玻璃背景

#if compiler(>=6.2)
extension View {
    /// 整个面板 / 提示框的背景
    @ViewBuilder
    func panelBackground(cornerRadius: CGFloat = Theme.panelRadius) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self.legacyPanelBackground(cornerRadius: cornerRadius)
        }
    }

    /// 小圆形玻璃按钮（面板右上角的设置 / 退出）
    @ViewBuilder
    func smallGlassButton(hovering: Bool) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: Circle())
        } else {
            self.background(Circle().fill(Color.primary.opacity(hovering ? 0.14 : 0.07)))
        }
    }

    /// 主要按钮样式
    @ViewBuilder
    func prominentButton() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }
}
#else
extension View {
    func panelBackground(cornerRadius: CGFloat = Theme.panelRadius) -> some View {
        legacyPanelBackground(cornerRadius: cornerRadius)
    }

    func smallGlassButton(hovering: Bool) -> some View {
        background(Circle().fill(Color.primary.opacity(hovering ? 0.14 : 0.07)))
    }

    func prominentButton() -> some View {
        buttonStyle(.borderedProminent)
    }
}
#endif

extension View {
    /// 旧系统上的面板背景：窗口后方模糊 + 细边框
    func legacyPanelBackground(cornerRadius: CGFloat) -> some View {
        background(
            VisualEffectBackground(material: .popover)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
        )
    }

    /// 面板里一组开关的底板
    func platter() -> some View {
        background(
            RoundedRectangle(cornerRadius: Theme.platterRadius, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.platterRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }
}

// MARK: - 按钮手感

/// 按下时轻轻缩小，松开弹回
struct SquishButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.92

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - 其他小组件

/// 透过窗口看到后面内容的模糊背景（NSVisualEffectView）
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

/// 系统设置风格的彩色小图标
struct SettingsIcon: View {
    let symbol: String
    let colors: [Color]
    var size: CGFloat = 22

    init(symbol: String, color: Color, size: CGFloat = 22) {
        self.symbol = symbol
        self.colors = [color.opacity(0.85), color]
        self.size = size
    }

    init(symbol: String, colors: [Color], size: CGFloat = 22) {
        self.symbol = symbol
        self.colors = colors
        self.size = size
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .fill(colors.diagonalGradient)
            )
    }
}

enum AppActivation {
    /// 把 SwitchBar 带到前台（打开设置窗口、锁定界面时需要）
    static func activate() {
        NSApp.activate(ignoringOtherApps: true)
    }
}
