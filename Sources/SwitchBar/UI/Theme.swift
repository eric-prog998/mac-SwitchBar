import AppKit
import SwiftUI

// 外观：尽量贴近 macOS 26 / 27 自带的「控制中心」。
// 面板背景是系统的「液态玻璃」（Liquid Glass，macOS 13–15 上退回到毛玻璃）；
// 图标用单色 SF Symbols，只有「开启」的开关才用系统强调色，其余都是中性的灰色玻璃。
// 用 #if compiler 判断：用 Xcode 26 以上编译时才包含玻璃效果的代码，旧版 Xcode 也能正常编译。

enum Theme {
    /// 菜单栏面板、提示框的圆角
    static let panelRadius: CGFloat = 22
    /// 面板里每一组（模块）的圆角
    static let moduleRadius: CGFloat = 16
}

// MARK: - 玻璃 / 毛玻璃

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

    /// 圆形按钮底：开启时是实心的系统强调色，关闭时是玻璃
    @ViewBuilder
    func circleBackground(on: Bool, hovering: Bool) -> some View {
        if #available(macOS 26.0, *) {
            if on {
                self.background(Circle().fill(Color.accentColor))
                    .glassEffect(.regular.interactive(), in: Circle())
            } else {
                self.glassEffect(.regular.interactive(), in: Circle())
            }
        } else {
            self.background(Circle().fill(Theme.legacyCircle(on: on, hovering: hovering)))
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

    func circleBackground(on: Bool, hovering: Bool) -> some View {
        background(Circle().fill(Theme.legacyCircle(on: on, hovering: hovering)))
    }

    func prominentButton() -> some View {
        buttonStyle(.borderedProminent)
    }
}
#endif

extension Theme {
    static func legacyCircle(on: Bool, hovering: Bool) -> Color {
        on ? .accentColor : Color.primary.opacity(hovering ? 0.14 : 0.09)
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

    /// 面板里的一组（和控制中心的模块一样，比背景稍微亮一点）
    func module() -> some View {
        background(
            RoundedRectangle(cornerRadius: Theme.moduleRadius, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
    }
}

// MARK: - 按钮手感

/// 按下时轻微缩小
struct PressButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.95

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
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

/// 「系统设置」风格的彩色小图标
struct SettingsIcon: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                    .fill(color.gradient)
            )
    }
}

extension FeatureID {
    /// 设置列表里图标的颜色（和「系统设置」一样用系统色）
    var tint: Color {
        switch self {
        case .hideDesktop, .bluetoothAudio, .fileExtensions: return .blue
        case .darkMode, .lockScreen, .sleepNow: return .indigo
        case .keepAwake: return .brown
        case .doNotDisturb: return .purple
        case .nightShift: return .orange
        case .micMute, .audioOutput: return .red
        case .hiddenFiles: return .gray
        case .autoHideDock, .autoHideMenuBar: return .teal
        case .displaySleep: return .gray
        case .cleanScreen: return .cyan
        case .screenSaver: return .mint
        case .colorPicker: return .pink
        case .plainText: return .green
        }
    }
}

extension SceneID {
    var symbol: String {
        switch self {
        case .focus: return "headphones"
        case .night: return "moon.stars.fill"
        }
    }

    var tint: Color {
        switch self {
        case .focus: return .indigo
        case .night: return .blue
        }
    }
}

enum AppActivation {
    /// 把 SwitchBar 带到前台（打开设置窗口、清洁屏幕时需要）
    static func activate() {
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 把焦点还给之前在用的应用
    static func reactivate(_ app: NSRunningApplication) {
        if #available(macOS 14.0, *) {
            app.activate()
        } else {
            app.activate(options: [])
        }
    }
}
