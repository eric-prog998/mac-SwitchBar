import AppKit
import SwiftUI

/// 设置窗口：左侧边栏 + 右侧内容，和「系统设置」的布局一致
struct SettingsView: View {
    @ObservedObject var store: SwitchStore
    @ObservedObject var prefs: Preferences
    @ObservedObject var router: SettingsRouter

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
                .ignoresSafeArea()
            detail
        }
        .frame(width: 780, height: 560)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 给左上角的红黄绿按钮留出位置
            Color.clear.frame(height: 46)
            List(SettingsTab.allCases, selection: selection) { tab in
                Label {
                    Text(tab.title)
                        .font(.system(size: 13))
                } icon: {
                    SettingsIcon(symbol: tab.symbol, color: tab.color, size: 22)
                }
                .padding(.vertical, 3)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .frame(width: 210)
        .background(VisualEffectBackground(material: .sidebar).ignoresSafeArea())
        .ignoresSafeArea(edges: .top)
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(router.tab.title)
                .font(.system(size: 20, weight: .bold))
                .padding(.horizontal, 28)
                .padding(.top, 14)
                .padding(.bottom, 2)
            Group {
                switch router.tab {
                case .features: FeaturesSettingsView(prefs: prefs)
                case .general: GeneralSettingsView(prefs: prefs)
                case .focus: FocusSettingsView(prefs: prefs)
                case .about: AboutView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea(edges: .top)
    }

    private var selection: Binding<SettingsTab?> {
        Binding(get: { router.tab }, set: { if let tab = $0 { router.tab = tab } })
    }
}

// MARK: - 功能与快捷键

private struct FeaturesSettingsView: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject private var hotKeys = HotKeyManager.shared

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    SettingsIcon(symbol: "menubar.arrow.down.rectangle", color: .blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("打开 / 关闭面板")
                        Text("菜单栏图标被刘海挡住时也能用它打开面板")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    HotKeyWarning(target: .panel, hotKeys: hotKeys)
                    HotKeyRecorder(target: .panel, prefs: prefs)
                }
                .padding(.vertical, 4)
            } header: {
                Text("面板")
            }

            Section {
                ForEach(prefs.featureOrder) { feature in
                    FeatureRow(feature: feature, prefs: prefs, hotKeys: hotKeys)
                }
                .onMove { source, destination in
                    prefs.featureOrder.move(fromOffsets: source, toOffset: destination)
                }
            } header: {
                Text("开关（勾选要显示的，拖动调整顺序；Esc 取消录制，Delete 清除快捷键）")
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: false))
    }
}

private struct FeatureRow: View {
    let feature: FeatureID
    @ObservedObject var prefs: Preferences
    @ObservedObject var hotKeys: HotKeyManager

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { prefs.isVisible(feature) },
                set: { prefs.setVisible($0, feature) }
            ))
            .labelsHidden()
            .help("在面板中显示")
            SettingsIcon(symbol: feature.symbol(on: true), color: feature.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(feature.title)
                Text(feature.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if feature.supportsHotKey {
                HotKeyWarning(target: .feature(feature), hotKeys: hotKeys)
                HotKeyRecorder(target: .feature(feature), prefs: prefs)
            }
        }
        .padding(.vertical, 3)
        .opacity(prefs.isVisible(feature) ? 1 : 0.55)
    }
}

private struct HotKeyWarning: View {
    let target: HotKeyTarget
    @ObservedObject var hotKeys: HotKeyManager

    var body: some View {
        if hotKeys.failed.contains(target) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .help("这个快捷键已被系统或其他应用占用，请换一个")
        }
    }
}

// MARK: - 通用

private struct GeneralSettingsView: View {
    @ObservedObject var prefs: Preferences

    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginNeedsApproval = LoginItem.needsApproval
    @State private var accessibilityGranted = InputLocker.hasPermission

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    SettingsIcon(symbol: "power", color: .green)
                    Toggle("登录时自动启动 SwitchBar", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { newValue in
                            LoginItem.set(newValue)
                            reload()
                        }
                }
                if !LoginItem.isInApplicationsFolder {
                    Text("建议先把 SwitchBar 放进「应用程序」文件夹再开启，否则移动位置后自动启动会失效。")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                if loginNeedsApproval {
                    HStack {
                        Text("需要在「登录项」里允许 SwitchBar")
                            .font(.caption)
                            .foregroundColor(.orange)
                        Spacer()
                        Button("打开登录项设置") { SystemSettings.open(.loginItems) }
                    }
                }
            } header: {
                Text("启动")
            }

            Section {
                HStack(spacing: 12) {
                    SettingsIcon(symbol: "cup.and.saucer.fill", color: .brown)
                    Picker("点击开关时默认保持", selection: $prefs.keepAwakeMinutes) {
                        Text("一直保持").tag(0)
                        Text("15 分钟").tag(15)
                        Text("30 分钟").tag(30)
                        Text("1 小时").tag(60)
                        Text("2 小时").tag(120)
                        Text("4 小时").tag(240)
                        Text("8 小时").tag(480)
                    }
                }
                HStack(spacing: 12) {
                    SettingsIcon(symbol: "text.bubble.fill", color: .orange)
                    Toggle("用快捷键操作时，在屏幕上显示提示", isOn: $prefs.showHUD)
                }
            } header: {
                Text("行为")
            } footer: {
                Text("也可以点面板里「保持亮屏」右上角的小箭头，临时选择时长。")
            }

            Section {
                PermissionRow(symbol: "accessibility", color: .blue, title: "辅助功能",
                              detail: "「锁定键盘」「清洁屏幕」需要，用来暂时拦截按键",
                              granted: accessibilityGranted) {
                    InputLocker.requestPermission()
                    SystemSettings.open(.accessibility)
                }
                PermissionRow(symbol: "gearshape.2.fill", color: .gray, title: "自动化 › 系统事件",
                              detail: "「深色模式」「隐藏程序坞」需要，第一次使用时系统会询问",
                              granted: nil) {
                    SystemSettings.open(.automation)
                }
                PermissionRow(symbol: "headphones", color: .blue, title: "蓝牙",
                              detail: "「蓝牙耳机」需要，第一次选择耳机时系统会询问",
                              granted: nil) {
                    SystemSettings.open(.bluetoothPrivacy)
                }
            } header: {
                Text("系统权限（只在用到对应功能时才需要）")
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            reload()
        }
    }

    private func reload() {
        let enabled = LoginItem.isEnabled
        if launchAtLogin != enabled { launchAtLogin = enabled }
        loginNeedsApproval = LoginItem.needsApproval
        accessibilityGranted = InputLocker.hasPermission
    }
}

private struct PermissionRow: View {
    let symbol: String
    let color: Color
    let title: String
    let detail: String
    let granted: Bool?
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(symbol: symbol, color: color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let granted {
                Label(granted ? "已允许" : "未允许", systemImage: granted ? "checkmark.circle.fill" : "xmark.circle")
                    .font(.caption)
                    .foregroundColor(granted ? .green : .orange)
            }
            Button("打开设置", action: action)
        }
    }
}

// MARK: - 勿扰模式

private struct FocusSettingsView: View {
    @ObservedObject var prefs: Preferences
    @State private var checkResult: String?

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("macOS 没有公开的接口可以直接切换勿扰模式，SwitchBar 借助系统自带的「快捷指令」来完成——不需要任何额外权限，也不用私有接口。只需要设置一次：")
                        .fixedSize(horizontal: false, vertical: true)
                    StepRow(number: 1, text: "打开「快捷指令」App，点「+」新建快捷指令，搜索并添加操作「**设定专注模式**」，设为「**打开** 勿扰模式」，把快捷指令命名为下面的第一个名字。")
                    StepRow(number: 2, text: "再新建一个，同样添加「设定专注模式」，设为「**关闭** 勿扰模式」，命名为下面的第二个名字。")
                    StepRow(number: 3, text: "回到这里点「检查」，看到 ✅ 就完成了。")
                }
                .padding(.vertical, 4)
            }

            Section {
                TextField("开启勿扰时运行", text: $prefs.dndOnShortcut)
                TextField("关闭勿扰时运行", text: $prefs.dndOffShortcut)
            } header: {
                Text("快捷指令名称")
            }

            Section {
                HStack(spacing: 10) {
                    Button("打开「快捷指令」App") { Shortcuts.openApp() }
                    Button("检查", action: check)
                    if let checkResult {
                        Text(checkResult)
                            .font(.callout)
                    }
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
    }

    private func check() {
        let names = Set(Shortcuts.list())
        let missing = [prefs.dndOnShortcut, prefs.dndOffShortcut].filter { !names.contains($0) }
        checkResult = missing.isEmpty ? "✅ 两个快捷指令都找到了" : "❌ 没找到：\(missing.joined(separator: "、"))"
    }
}

private struct StepRow: View {
    let number: Int
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.accentColor))
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - 关于与隐私

private struct AboutView: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版"
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SwitchBar")
                            .font(.system(size: 22, weight: .bold))
                        Text("版本 \(version)")
                            .foregroundStyle(.secondary)
                        Text("自己编译、自己使用的菜单栏开关工具")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }

            Section {
                AboutRow(symbol: "wifi.slash", color: .green, text: "完全离线：代码里没有任何网络请求，不收集、不上传任何数据")
                AboutRow(symbol: "shippingbox.fill", color: .brown, text: "没有第三方依赖：只用苹果系统框架，全部源码可以自己审查、自己编译")
                AboutRow(symbol: "internaldrive.fill", color: .gray, text: "设置只保存在本机：~/Library/Preferences/local.switchbar.plist")
                AboutRow(symbol: "hand.raised.fill", color: .blue, text: "权限按需申请：只有用到相关功能时系统才会询问")
            } header: {
                Text("隐私与安全")
            }

            Section {
                Text("夜览、原彩显示：CoreBrightness 框架（系统设置自己也用它）\n锁定屏幕：login 框架的 SACLockScreenImmediate（不可用时退回 pmset）\n它们都只在本机调用系统自带功能；如果将来 macOS 移除了这些接口，对应开关会自动变灰，不会崩溃。")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("用到的非公开系统接口")
            }
        }
        .formStyle(.grouped)
    }
}

private struct AboutRow: View {
    let symbol: String
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(symbol: symbol, color: color)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
