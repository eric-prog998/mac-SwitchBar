import AppKit
import SwiftUI

/// 点击菜单栏图标后弹出的面板
struct PanelView: View {
    @ObservedObject var store: SwitchStore
    @ObservedObject var prefs: Preferences

    static let columnCount = 4
    static let tileWidth: CGFloat = 76
    static let tileSpacing: CGFloat = 6
    static let platterPadding: CGFloat = 10
    static let outerPadding: CGFloat = 14

    static var width: CGFloat {
        CGFloat(columnCount) * tileWidth + CGFloat(columnCount - 1) * tileSpacing
            + platterPadding * 2 + outerPadding * 2
    }

    private let columns = Array(repeating: GridItem(.fixed(PanelView.tileWidth), spacing: PanelView.tileSpacing),
                                count: PanelView.columnCount)

    var body: some View {
        let visible = prefs.visibleFeatures
        let toggles = visible.filter { $0.kind == .toggle }
        let tools = visible.filter { $0.kind != .toggle }

        VStack(alignment: .leading, spacing: 12) {
            header
            quickRow

            if visible.isEmpty {
                Text("所有开关都被隐藏了，可以在设置里打开。")
                    .font(Theme.rounded(12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .platter()
            }
            if !toggles.isEmpty {
                section("开关", toggles)
            }
            if !tools.isEmpty {
                section("工具", tools)
            }
        }
        .padding(PanelView.outerPadding)
        .frame(width: PanelView.width)
        .background(glow)
        .panelBackground()
    }

    // MARK: - 顶部

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting)
                    .font(Theme.rounded(18, .bold))
                // 每秒刷新一次，倒计时、剩余时间才会跟着走
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(summary)
                        .font(Theme.rounded(11, .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            if let battery = store.battery {
                BatteryChip(status: battery)
            }
            HeaderButton(symbol: "gearshape.fill", help: "设置") {
                store.openSettings()
            }
            HeaderButton(symbol: "power", help: "退出 SwitchBar") {
                NSApp.terminate(nil)
            }
        }
        .padding(.horizontal, 4)
    }

    /// 场景 + 专注计时
    private var quickRow: some View {
        HStack(spacing: 6) {
            ForEach(SceneID.allCases) { scene in
                SceneChip(scene: scene, store: store, prefs: prefs)
            }
            TimerChip(store: store, prefs: prefs)
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<11: return "早上好 ☀️"
        case 11..<13: return "中午好 🍱"
        case 13..<18: return "下午好 ☕️"
        case 18..<23: return "晚上好 🌙"
        default: return "夜深了 ✨"
        }
    }

    private var summary: String {
        if store.timerRunning {
            return "专注中 · 还剩 \(Int((store.focusTimer.remaining / 60).rounded(.up))) 分钟"
        }
        if let scene = SceneID.allCases.first(where: { store.activeScenes.contains($0) }) {
            return "\(scene.emoji) \(scene.title)模式进行中"
        }
        if store.keepAwake.isActive, let minutes = store.keepAwake.remainingMinutes {
            return "保持亮屏中 · 还剩 \(minutes) 分钟"
        }
        let count = prefs.visibleFeatures.filter { $0.kind == .toggle && store.isOn($0) }.count
        return count == 0 ? "一切都关着，想开点什么？" : "已开启 \(count) 个开关"
    }

    /// 面板顶部淡淡的彩色光晕
    private var glow: some View {
        LinearGradient(colors: [Color(hex: 0xFF8AB8, opacity: 0.16), Color(hex: 0x7C8CFF, opacity: 0.12), .clear],
                       startPoint: .topLeading, endPoint: .init(x: 0.6, y: 0.45))
            .clipShape(RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous))
            .allowsHitTesting(false)
    }

    private func section(_ title: String, _ features: [FeatureID]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Theme.rounded(12, .bold))
                .foregroundStyle(.secondary)
                .padding(.leading, 6)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(features) { feature in
                    ColorTile(feature: feature, store: store)
                }
            }
            .padding(PanelView.platterPadding)
            .platter()
        }
    }
}

// MARK: - 彩色开关

struct ColorTile: View {
    let feature: FeatureID
    @ObservedObject var store: SwitchStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var hovering = false

    private static let size: CGFloat = 50

    var body: some View {
        let available = store.isAvailable(feature)
        let on = store.isOn(feature)
        let busy = store.isBusy(feature)
        let colors = feature.colors
        let shape = RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)

        VStack(spacing: 5) {
            Button {
                store.trigger(feature)
            } label: {
                ZStack {
                    shape.fill(on ? AnyShapeStyle(colors.diagonalGradient)
                                  : AnyShapeStyle(colors[1].opacity(colorScheme == .dark ? 0.24 : 0.13)))
                    if on {
                        // 顶部的一层高光，看起来更「亮」
                        shape.fill(LinearGradient(colors: [.white.opacity(0.32), .clear],
                                                  startPoint: .top, endPoint: .center))
                    }
                    if busy {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: feature.symbol(on: on))
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(on ? AnyShapeStyle(Color.white) : AnyShapeStyle(colors.diagonalGradient))
                    }
                }
                .frame(width: Self.size, height: Self.size)
                .overlay(shape.strokeBorder(colors[1].opacity(hovering && available ? 0.55 : 0), lineWidth: 1.5))
                .shadow(color: on ? colors[1].opacity(0.45) : .clear, radius: 8, y: 3)
                .contentShape(shape)
            }
            .buttonStyle(SquishButtonStyle())
            .overlay(alignment: .topTrailing) {
                if feature.hasOptions && available {
                    OptionsBadge {
                        store.showOptionsMenu(for: feature)
                    }
                    .offset(x: 6, y: -5)
                }
            }
            .disabled(!available || busy)
            .onHover { hovering = $0 }

            Text(store.title(for: feature))
                .font(Theme.rounded(11, on ? .semibold : .medium))
                .foregroundColor(available ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(width: PanelView.tileWidth)
        .opacity(available ? 1 : 0.4)
        .saturation(available ? 1 : 0)
        .animation(.easeOut(duration: 0.18), value: on)
        .help(store.tooltip(for: feature))
    }
}

// MARK: - 场景和计时

private struct SceneChip: View {
    let scene: SceneID
    @ObservedObject var store: SwitchStore
    @ObservedObject var prefs: Preferences

    var body: some View {
        let active = store.activeScenes.contains(scene)
        Button {
            store.toggleScene(scene)
        } label: {
            HStack(spacing: 3) {
                Text(scene.emoji)
                    .font(.system(size: 12))
                Text(scene.title)
                    .font(Theme.rounded(12, .semibold))
            }
            .foregroundColor(active ? .white : .primary)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(chipBackground(active: active, colors: scene.colors))
            .shadow(color: active ? scene.colors[1].opacity(0.4) : .clear, radius: 6, y: 2)
            .contentShape(Capsule())
        }
        .buttonStyle(SquishButtonStyle(scale: 0.95))
        .help("\(scene.title)模式：" + prefs.members(of: scene).map(\.title).joined(separator: "、"))
    }
}

private struct TimerChip: View {
    @ObservedObject var store: SwitchStore
    @ObservedObject var prefs: Preferences

    var body: some View {
        Button {
            store.toggleTimer()
        } label: {
            Group {
                if store.timerRunning {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        HStack(spacing: 3) {
                            Image(systemName: "timer")
                                .font(.system(size: 11, weight: .bold))
                            Text(FocusTimer.format(store.focusTimer.remaining))
                                .font(Theme.rounded(12, .bold).monospacedDigit())
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(
                            ZStack(alignment: .leading) {
                                Capsule().fill(FeatureColors.timer.diagonalGradient)
                                GeometryReader { proxy in
                                    Capsule()
                                        .fill(Color.white.opacity(0.22))
                                        .frame(width: proxy.size.width * store.focusTimer.progress)
                                }
                            }
                            .clipShape(Capsule())
                        )
                    }
                } else {
                    HStack(spacing: 3) {
                        Text("🍅")
                            .font(.system(size: 12))
                        Text("\(prefs.timerMinutes)分")
                            .font(Theme.rounded(12, .semibold))
                    }
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .background(chipBackground(active: false, colors: FeatureColors.timer))
                }
            }
            .shadow(color: store.timerRunning ? FeatureColors.timer[1].opacity(0.4) : .clear, radius: 6, y: 2)
            .contentShape(Capsule())
        }
        .buttonStyle(SquishButtonStyle(scale: 0.95))
        .help(store.timerRunning ? "专注中，点一下停止（右键可以加时间）" : "专注计时 \(prefs.timerMinutes) 分钟（右键选择时长）")
        .contextMenu {
            if store.timerRunning {
                Button("再加 5 分钟") { store.extendTimer(minutes: 5) }
                Button("停止计时") { store.toggleTimer() }
            } else {
                ForEach([15, 25, 45, 60], id: \.self) { minutes in
                    Button("专注 \(minutes) 分钟") { store.startTimer(minutes: minutes) }
                }
            }
        }
    }
}

private func chipBackground(active: Bool, colors: [Color]) -> some View {
    Capsule()
        .fill(active ? AnyShapeStyle(colors.diagonalGradient) : AnyShapeStyle(Color.primary.opacity(0.06)))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(active ? 0 : 0.07), lineWidth: 0.5))
}

// MARK: - 小组件

private struct BatteryChip: View {
    let status: Battery.Status

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
            Text("\(status.percent)%")
                .font(Theme.rounded(11, .semibold).monospacedDigit())
        }
        .foregroundColor(color)
        .padding(.horizontal, 7)
        .frame(height: 22)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
        .help(status.isCharging ? "正在充电" : (status.isPluggedIn ? "已接通电源" : "使用电池"))
    }

    private var symbol: String {
        if status.isCharging { return "battery.100.bolt" }
        switch status.percent {
        case 88...: return "battery.100"
        case 63..<88: return "battery.75"
        case 38..<63: return "battery.50"
        case 13..<38: return "battery.25"
        default: return "battery.0"
        }
    }

    private var color: Color {
        if status.isCharging { return Color(hex: 0x2FBF71) }
        if status.percent < 20 { return Color(hex: 0xFF4D4F) }
        return .secondary
    }
}

/// 开关右上角的「更多选项」小按钮
private struct OptionsBadge: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.down")
                .font(.system(size: 7.5, weight: .heavy))
                .foregroundColor(hovering ? .primary : .secondary)
                .frame(width: 18, height: 18)
                .background(Circle().fill(.regularMaterial))
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                .contentShape(Circle())
        }
        .buttonStyle(SquishButtonStyle(scale: 0.85))
        .onHover { hovering = $0 }
        .help("更多选项")
    }
}

/// 面板右上角的小圆按钮
private struct HeaderButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(hovering ? .primary : .secondary)
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(SquishButtonStyle(scale: 0.88))
        .smallGlassButton(hovering: hovering)
        .onHover { hovering = $0 }
        .help(help)
    }
}
