import AppKit
import SwiftUI

/// 点击菜单栏图标后弹出的面板，布局参照 macOS「控制中心」：
/// 顶部一行状态，下面依次是「场景与计时」「开关」「工具」三个模块。
struct PanelView: View {
    @ObservedObject var store: SwitchStore
    @ObservedObject var prefs: Preferences

    static let width: CGFloat = 356

    var body: some View {
        let visible = prefs.visibleFeatures
        let toggles = visible.filter { $0.kind == .toggle }
        let tools = visible.filter { $0.kind != .toggle }

        VStack(spacing: 10) {
            header
            scenesModule
            if !toggles.isEmpty {
                togglesModule(toggles)
            }
            if !tools.isEmpty {
                toolsModule(tools)
            }
            if visible.isEmpty {
                Text("所有开关都被隐藏了，可以在设置里打开。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .module()
            }
        }
        .padding(12)
        .frame(width: PanelView.width)
        .panelBackground()
    }

    // MARK: - 顶部

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("SwitchBar")
                    .font(.system(size: 13, weight: .semibold))
                // 每秒刷新一次，倒计时、剩余时间才会跟着走
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(summary)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let battery = store.battery {
                BatteryLabel(status: battery)
            }
            Button {
                AppMenu.show(store: store)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .contentShape(Circle())
            }
            .buttonStyle(PressButtonStyle())
            .help("设置、退出")
        }
        .padding(.horizontal, 6)
        .padding(.top, 2)
    }

    private var summary: String {
        if store.timerRunning {
            return "专注中，还剩 \(FocusTimer.format(store.focusTimer.remaining))"
        }
        if let scene = SceneID.allCases.first(where: { store.activeScenes.contains($0) }) {
            return "\(scene.title)模式"
        }
        if store.keepAwake.isActive, let minutes = store.keepAwake.remainingMinutes {
            return "保持亮屏，还剩 \(minutes) 分钟"
        }
        let count = prefs.visibleFeatures.filter { $0.kind == .toggle && store.isOn($0) }.count
        return count == 0 ? "没有开启的开关" : "已开启 \(count) 个开关"
    }

    // MARK: - 模块

    /// 场景 + 专注计时：四个圆形按钮
    private var scenesModule: some View {
        HStack(spacing: 0) {
            ForEach(SceneID.allCases) { scene in
                CircleButton(symbol: scene.symbol,
                             title: scene.title,
                             on: store.activeScenes.contains(scene),
                             help: "\(scene.title)模式：" + prefs.members(of: scene).map(\.title).joined(separator: "、")) {
                    store.toggleScene(scene)
                }
                .frame(maxWidth: .infinity)
            }
            TimerButton(store: store, prefs: prefs)
                .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 10)
        .module()
    }

    /// 开关：两列，每个是「圆形图标 + 名称 + 状态」
    private func togglesModule(_ features: [FeatureID]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)], spacing: 2) {
            ForEach(features) { feature in
                ToggleRow(feature: feature, store: store)
            }
        }
        .padding(6)
        .module()
    }

    /// 工具：一次性的操作，四列圆形按钮
    private func toolsModule(_ features: [FeatureID]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 4), spacing: 10) {
            ForEach(features) { feature in
                ToolButton(feature: feature, store: store)
            }
        }
        .padding(.vertical, 10)
        .module()
    }
}

// MARK: - 开关行

private struct ToggleRow: View {
    let feature: FeatureID
    @ObservedObject var store: SwitchStore
    @State private var hovering = false

    var body: some View {
        let available = store.isAvailable(feature)
        let on = store.isOn(feature)
        let busy = store.isBusy(feature)

        HStack(spacing: 0) {
            Button {
                store.trigger(feature)
            } label: {
                HStack(spacing: 9) {
                    ZStack {
                        if busy {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Image(systemName: feature.symbol(on: on))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(on ? .white : .primary)
                        }
                    }
                    .frame(width: 30, height: 30)
                    .circleBackground(on: on, hovering: hovering && available)

                    VStack(alignment: .leading, spacing: 0) {
                        Text(store.title(for: feature))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        stateLabel
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressButtonStyle(scale: 0.98))
            .disabled(!available || busy)

            if feature.hasOptions && available {
                Button {
                    store.showOptionsMenu(for: feature)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 18, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressButtonStyle())
                .help("更多选项")
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.primary.opacity(hovering && available ? 0.06 : 0))
        )
        .opacity(available ? 1 : 0.45)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: on)
        .help(store.tooltip(for: feature))
    }

    /// 状态文字；「保持亮屏」的剩余时间在面板开着时也要跟着走
    @ViewBuilder
    private var stateLabel: some View {
        if feature == .keepAwake && store.isOn(.keepAwake) {
            TimelineView(.periodic(from: .now, by: 10)) { _ in
                stateText
            }
        } else {
            stateText
        }
    }

    private var stateText: some View {
        Text(store.stateText(for: feature))
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

// MARK: - 圆形按钮

/// 图标在上、文字在下的圆形按钮（场景、工具共用）
private struct CircleButton: View {
    let symbol: String
    let title: String
    var on: Bool = false
    var help: String = ""
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(on ? .white : .primary)
                    .frame(width: 38, height: 38)
                    .circleBackground(on: on, hovering: hovering)
                Text(title)
                    .font(.system(size: 11))
                    .foregroundColor(on ? .primary : .secondary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressButtonStyle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: on)
        .help(help)
    }
}

private struct ToolButton: View {
    let feature: FeatureID
    @ObservedObject var store: SwitchStore

    var body: some View {
        let available = store.isAvailable(feature)
        CircleButton(symbol: feature.symbol(on: false), title: store.title(for: feature),
                     help: store.tooltip(for: feature)) {
            store.trigger(feature)
        }
        .overlay(alignment: .topTrailing) {
            if feature.hasOptions && available {
                Button {
                    store.showOptionsMenu(for: feature)
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(.regularMaterial))
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
                        .contentShape(Circle())
                }
                .buttonStyle(PressButtonStyle(scale: 0.85))
                .offset(x: -8, y: -3)
                .help("更多选项")
            }
        }
        .disabled(!available || store.isBusy(feature))
        .opacity(available ? 1 : 0.45)
    }
}

private struct TimerButton: View {
    @ObservedObject var store: SwitchStore
    @ObservedObject var prefs: Preferences

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            CircleButton(symbol: "timer",
                         title: store.timerRunning ? FocusTimer.format(store.focusTimer.remaining) : "专注计时",
                         on: store.timerRunning,
                         help: store.timerRunning ? "点一下停止；右键可以加时间"
                                                  : "专注 \(prefs.timerMinutes) 分钟；右键选择时长") {
                store.toggleTimer()
            }
        }
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

// MARK: - 小组件

private struct BatteryLabel: View {
    let status: Battery.Status

    var body: some View {
        HStack(spacing: 3) {
            Text("\(status.percent)%")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
            Image(systemName: symbol)
                .font(.system(size: 13))
                .symbolRenderingMode(.hierarchical)
        }
        .foregroundStyle(.secondary)
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
}

/// 面板右上角「…」弹出的菜单
private enum AppMenu {
    static func show(store: SwitchStore) {
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem("设置…") { store.openSettings() })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("退出 SwitchBar") { NSApp.terminate(nil) })
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}
