import AppKit
import SwiftUI

// 外观：macOS 26 及以上使用系统的「液态玻璃」（Liquid Glass），更早的系统退回到毛玻璃材质。
// 用 #if compiler 判断：用 Xcode 26 以上编译时才包含玻璃效果的代码，旧版 Xcode 也能正常编译。

enum Theme {
    /// 菜单栏面板、提示框的圆角
    static let panelRadius: CGFloat = 24
    /// 面板里一组开关的底板圆角
    static let platterRadius: CGFloat = 18
}

#if compiler(>=6.2)
extension View {
    /// 圆形按钮底：开启时用强调色，关闭时是玻璃
    @ViewBuilder
    func bubbleBackground(on: Bool, hovering: Bool) -> some View {
        if #available(macOS 26.0, *) {
            if on {
                // 和控制中心一样：开启时是实心的强调色圆，一眼就能看出来
                self.background(Circle().fill(Color.accentColor.gradient))
                    .glassEffect(.regular.interactive(), in: Circle())
            } else {
                self.glassEffect(.regular.interactive(), in: Circle())
            }
        } else {
            self.background(Circle().fill(Theme.legacyBubble(on: on, hovering: hovering)))
        }
    }

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
    func bubbleBackground(on: Bool, hovering: Bool) -> some View {
        background(Circle().fill(Theme.legacyBubble(on: on, hovering: hovering)))
    }

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

extension Theme {
    static func legacyBubble(on: Bool, hovering: Bool) -> AnyShapeStyle {
        if on { return AnyShapeStyle(Color.accentColor.gradient) }
        return AnyShapeStyle(Color.primary.opacity(hovering ? 0.14 : 0.08))
    }
}

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
                .fill(Color.primary.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.platterRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }
}

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
    let color: Color
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.52, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                    .fill(color.gradient)
            )
    }
}

extension FeatureID {
    /// 设置列表里图标的颜色
    var tint: Color {
        switch self {
        case .hideDesktop: return .blue
        case .darkMode: return .indigo
        case .keepAwake: return .brown
        case .doNotDisturb: return .purple
        case .nightShift: return .orange
        case .trueTone: return .yellow
        case .micMute: return .red
        case .muteSound: return .pink
        case .bluetoothAudio: return .blue
        case .hiddenFiles: return .gray
        case .autoHideDock: return .teal
        case .autoHideMenuBar: return .teal
        case .lockScreen: return .gray
        case .lockKeyboard: return .gray
        case .cleanScreen: return .cyan
        case .ejectDisks: return .gray
        case .screenSaver: return .mint
        case .displayResolution: return .blue
        }
    }
}

enum AppActivation {
    /// 把 SwitchBar 带到前台（打开设置窗口、锁定界面时需要）
    static func activate() {
        NSApp.activate(ignoringOtherApps: true)
    }
}
