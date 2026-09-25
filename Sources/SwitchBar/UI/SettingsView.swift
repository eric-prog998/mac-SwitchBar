import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: SwitchStore
    @ObservedObject var prefs: Preferences
    @ObservedObject var router: SettingsRouter

    var body: some View {
        TabView(selection: $router.tab) {
            FeaturesSettingsView(prefs: prefs)
                .tabItem { Label("功能与快捷键", systemImage: "square.grid.2x2") }
                .tag(SettingsTab.features)
            GeneralSettingsView(prefs: prefs)
                .tabItem { Label("通用", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            FocusSettingsView(prefs: prefs)
                .tabItem { Label("勿扰模式", systemImage: "bell.slash") }
                .tag(SettingsTab.focus)
            AboutView()
                .tabItem { Label("关于与隐私", systemImage: "lock.shield") }
                .tag(SettingsTab.about)
        }
        .padding(12)
        .frame(width: 620, height: 540)
    }
}

// MARK: - 功能与快捷键

private struct FeaturesSettingsView: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject private var hotKeys = HotKeyManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("勾选要在面板中显示的开关，拖动可以调整顺序。点右侧按钮录制全局快捷键（Esc 取消，Delete 清除）。")
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            List {
                ForEach(prefs.featureOrder) { feature in
                    HStack(spacing: 10) {
                        Toggle("", isOn: Binding(
                            get: { prefs.isVisible(feature) },
                            set: { prefs.setVisible($0, feature) }
                        ))
                        .labelsHidden()
                        Image(systemName: feature.symbol(on: false))
                            .frame(width: 22)
                        Text(feature.title)
                        Spacer()
                        if feature.supportsHotKey {
                            if hotKeys.failed.contains(feature) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                    .help("这个快捷键已被系统或其他应用占用，请换一个")
                            }
                            HotKeyRecorder(feature: feature, prefs: prefs)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .onMove { source, destination in
                    prefs.featureOrder.move(fromOffsets: source, toOffset: destination)
                }
            }
        }
        .padding(8)
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
            Section("启动") {
                Toggle("登录时自动启动 SwitchBar", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        LoginItem.set(newValue)
                        reload()
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
            }

            Section("保持亮屏") {
                Picker("点击开关时默认保持", selection: $prefs.keepAwakeMinutes) {
                    Text("一直保持").tag(0)
                    Text("15 分钟").tag(15)
                    Text("30 分钟").tag(30)
                    Text("1 小时").tag(60)
                    Text("2 小时").tag(120)
                    Text("4 小时").tag(240)
                    Text("8 小时").tag(480)
                }
                Text("也可以点面板里「保持亮屏」右上角的小箭头，临时选择时长。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("提示") {
                Toggle("用快捷键操作时，在屏幕上显示提示", isOn: $prefs.showHUD)
            }

            Section("系统权限（只在用到对应功能时才需要）") {
                PermissionRow(title: "辅助功能",
                              detail: "「锁定键盘」「清洁屏幕」需要，用来暂时拦截按键",
                              granted: accessibilityGranted) {
                    InputLocker.requestPermission()
                    SystemSettings.open(.accessibility)
                }
                PermissionRow(title: "自动化 › 系统事件",
                              detail: "「深色模式」「隐藏程序坞」需要，第一次使用时系统会弹窗询问",
                              granted: nil) {
                    SystemSettings.open(.automation)
                }
                PermissionRow(title: "蓝牙",
                              detail: "「蓝牙耳机」需要，第一次选择耳机时系统会弹窗询问",
                              granted: nil) {
                    SystemSettings.open(.bluetoothPrivacy)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: reload)
    }

    private func reload() {
        let enabled = LoginItem.isEnabled
        if launchAtLogin != enabled { launchAtLogin = enabled }
        loginNeedsApproval = LoginItem.needsApproval
        accessibilityGranted = InputLocker.hasPermission
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool?
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
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
                Text("macOS 没有公开的接口可以直接切换勿扰模式，所以 SwitchBar 借助系统自带的「快捷指令」来完成——不需要任何额外权限，也不用私有接口。只需要设置一次：")
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 8) {
                    Text("1. 打开「快捷指令」App，点「+」新建快捷指令，在右侧搜索并添加操作「**设定专注模式**」，设为「**打开** 勿扰模式」，然后把快捷指令命名为下面的第一个名字。")
                    Text("2. 再新建一个，同样添加「设定专注模式」，设为「**关闭** 勿扰模式」，命名为下面的第二个名字。")
                    Text("3. 回到这里点「检查」，看到 ✅ 就完成了。")
                }
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            }

            Section("快捷指令名称") {
                TextField("开启勿扰时运行", text: $prefs.dndOnShortcut)
                TextField("关闭勿扰时运行", text: $prefs.dndOffShortcut)
            }

            Section {
                HStack(spacing: 10) {
                    Button("打开「快捷指令」App") { Shortcuts.openApp() }
                    Button("检查", action: check)
                    if let checkResult {
                        Text(checkResult)
                            .font(.callout)
                    }
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

// MARK: - 关于与隐私

private struct AboutView: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版"
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SwitchBar")
                            .font(.title2.bold())
                        Text("版本 \(version) · 自己编译、自己使用的菜单栏开关工具")
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section("隐私与安全") {
                Label("完全离线：代码里没有任何网络请求，不收集、不上传任何数据", systemImage: "wifi.slash")
                Label("没有第三方依赖：只用苹果系统框架，全部源码可以自己审查、自己编译", systemImage: "shippingbox")
                Label("设置只保存在本机：~/Library/Preferences/local.switchbar.plist", systemImage: "internaldrive")
                Label("权限按需申请：只有用到相关功能时系统才会询问", systemImage: "hand.raised")
            }

            Section("用到的非公开系统接口") {
                Text("夜览、原彩显示：CoreBrightness 框架（系统设置自己也用它）\n锁定屏幕：login 框架的 SACLockScreenImmediate（不可用时退回 pmset）\n它们都只在本机调用系统自带功能；如果将来 macOS 移除了这些接口，对应开关会自动变灰，不会崩溃。")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}
