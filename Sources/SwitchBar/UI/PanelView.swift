import AppKit
import SwiftUI

/// 点击菜单栏图标后弹出的开关面板
struct PanelView: View {
    @ObservedObject var store: SwitchStore
    @ObservedObject var prefs: Preferences

    private static let tileWidth: CGFloat = 76
    private static let columnCount = 4
    private let columns = Array(repeating: GridItem(.fixed(PanelView.tileWidth), spacing: 6), count: PanelView.columnCount)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text("SwitchBar")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button {
                    store.openSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("设置")
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .buttonStyle(.borderless)
                .help("退出 SwitchBar")
            }

            if prefs.visibleFeatures.isEmpty {
                Text("所有开关都被隐藏了，可以在设置里打开。")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                    ForEach(prefs.visibleFeatures) { feature in
                        TileView(feature: feature, store: store)
                    }
                }
            }

            if store.keepAwake.isActive {
                Label(keepAwakeText, systemImage: "cup.and.saucer.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .frame(width: PanelView.tileWidth * CGFloat(PanelView.columnCount) + 6 * CGFloat(PanelView.columnCount - 1) + 28)
    }

    private var keepAwakeText: String {
        if let minutes = store.keepAwake.remainingMinutes {
            return "保持亮屏中，还剩 \(minutes) 分钟"
        }
        return "保持亮屏中"
    }
}

/// 面板里的一个圆形开关
struct TileView: View {
    let feature: FeatureID
    @ObservedObject var store: SwitchStore

    var body: some View {
        let on = store.isOn(feature)
        let available = store.isAvailable(feature)
        let busy = store.isBusy(feature)

        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Button {
                    store.trigger(feature)
                } label: {
                    ZStack {
                        Circle()
                            .fill(on ? Color.accentColor : Color.primary.opacity(0.08))
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
                .disabled(!available || busy)

                if feature.hasOptions && available {
                    Button {
                        store.showOptionsMenu(for: feature)
                    } label: {
                        Image(systemName: "chevron.down.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .background(Circle().fill(Color(nsColor: .windowBackgroundColor)))
                    }
                    .buttonStyle(.plain)
                    .offset(x: 5, y: -3)
                    .help("更多选项")
                }
            }

            Text(store.title(for: feature))
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(width: 76)
        .opacity(available ? 1 : 0.4)
        .help(store.tooltip(for: feature))
    }
}
