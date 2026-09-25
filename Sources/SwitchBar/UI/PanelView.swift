import AppKit
import SwiftUI

/// 点击菜单栏图标后弹出的开关面板（控制中心风格）
struct PanelView: View {
    @ObservedObject var store: SwitchStore
    @ObservedObject var prefs: Preferences

    static let columnCount = 4
    static let tileWidth: CGFloat = 72
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

            if visible.isEmpty {
                Text("所有开关都被隐藏了，可以在设置里打开。")
                    .font(.callout)
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
        .panelBackground()
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("SwitchBar")
                    .font(.system(size: 15, weight: .semibold))
                Text(summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            HeaderButton(symbol: "gearshape.fill", help: "设置") {
                store.openSettings()
            }
            HeaderButton(symbol: "power", help: "退出 SwitchBar") {
                NSApp.terminate(nil)
            }
        }
        .padding(.horizontal, 4)
    }

    private var summary: String {
        if store.keepAwake.isActive, let minutes = store.keepAwake.remainingMinutes {
            return "保持亮屏中 · 还剩 \(minutes) 分钟"
        }
        let count = prefs.visibleFeatures.filter { $0.kind == .toggle && store.isOn($0) }.count
        return count == 0 ? "所有开关都已关闭" : "已开启 \(count) 个开关"
    }

    private func section(_ title: String, _ features: [FeatureID]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 6)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(features) { feature in
                    TileView(feature: feature, store: store)
                }
            }
            .padding(PanelView.platterPadding)
            .platter()
        }
    }
}

/// 面板里的一个圆形开关
struct TileView: View {
    let feature: FeatureID
    @ObservedObject var store: SwitchStore
    @State private var hovering = false

    var body: some View {
        let available = store.isAvailable(feature)
        let on = store.isOn(feature)
        let busy = store.isBusy(feature)

        VStack(spacing: 6) {
            Button {
                store.trigger(feature)
            } label: {
                ZStack {
                    if busy {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: feature.symbol(on: on))
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(on ? .white : .primary)
                    }
                }
                .frame(width: 46, height: 46)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .bubbleBackground(on: on, hovering: hovering && available)
            .overlay(alignment: .topTrailing) {
                if feature.hasOptions && available {
                    OptionsBadge {
                        store.showOptionsMenu(for: feature)
                    }
                    .offset(x: 5, y: -3)
                }
            }
            .disabled(!available || busy)
            .onHover { hovering = $0 }

            Text(store.title(for: feature))
                .font(.system(size: 11, weight: on ? .medium : .regular))
                .foregroundColor(available ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(width: PanelView.tileWidth)
        .opacity(available ? 1 : 0.45)
        .animation(.easeOut(duration: 0.15), value: on)
        .help(store.tooltip(for: feature))
    }
}

/// 开关右上角的「更多选项」小按钮
private struct OptionsBadge: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.down")
                .font(.system(size: 7.5, weight: .bold))
                .foregroundColor(hovering ? .primary : .secondary)
                .frame(width: 17, height: 17)
                .background(Circle().fill(.regularMaterial))
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.12), radius: 1.5, y: 0.5)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
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
        .buttonStyle(.plain)
        .smallGlassButton(hovering: hovering)
        .onHover { hovering = $0 }
        .help(help)
    }
}
