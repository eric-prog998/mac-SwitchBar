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
                case .scenes: ScenesSettingsView(prefs: prefs)
                case .general: GeneralSettingsView(prefs: prefs)
                case .focus: FocusSettingsView(prefs: prefs)
                case .security: SecurityView()
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
    @State private var recommendResult: String?

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

                HStack(spacing: 12) {
                    SettingsIcon(symbol: "command", color: .purple)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("推荐快捷键")
                        Text(recommendResult ?? "⌃⌥ + 好记的字母，例如 ⌃⌥D 深色模式、⌃⌥V 纯文本、⌃⌥1 专注场景、⌃⌥T 专注计时；不会覆盖已设置的")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("一键设置") {
                        let count = prefs.applyRecommendedHotKeys()
                        recommendResult = count == 0 ? "没有需要设置的：常用开关都已经有快捷键了" : "已设置 \(count) 个快捷键，可以在下面逐个修改"
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("面板与快捷键")
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
                Text(feature.systemShortcut.map { "\(feature.detail) · \($0)" } ?? feature.detail)
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

// MARK: - 场景与计时

private struct ScenesSettingsView: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject private var hotKeys = HotKeyManager.shared

    private static let memberColumns = [GridItem(.adaptive(minimum: 120), spacing: 8, alignment: .leading)]
    private let toggleFeatures = FeatureID.allCases.filter { $0.kind == .toggle }

    var body: some View {
        Form {
            ForEach(SceneID.allCases) { scene in
                Section {
                    HStack(spacing: 12) {
                        SettingsIcon(symbol: scene.symbol, color: scene.tint, size: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(scene.title)模式")
                                .font(.system(size: 13, weight: .semibold))
                            Text(scene.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        HotKeyWarning(target: .scene(scene), hotKeys: hotKeys)
                        HotKeyRecorder(target: .scene(scene), prefs: prefs)
                    }
                    LazyVGrid(columns: Self.memberColumns, alignment: .leading, spacing: 8) {
                        ForEach(toggleFeatures) { feature in
                            Toggle(feature.title, isOn: Binding(
                                get: { prefs.members(of: scene).contains(feature) },
                                set: { prefs.setMember(feature, of: scene, included: $0) }
                            ))
                            .toggleStyle(.checkbox)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                HStack(spacing: 12) {
                    SettingsIcon(symbol: "timer", color: .red)
                    Text("开始 / 停止专注计时")
                    Spacer()
                    HotKeyWarning(target: .timer, hotKeys: hotKeys)
                    HotKeyRecorder(target: .timer, prefs: prefs)
                }
                HStack(spacing: 12) {
                    SettingsIcon(symbol: "hourglass", color: .red)
                    Picker("默认时长", selection: $prefs.timerMinutes) {
                        ForEach([15, 20, 25, 30, 45, 60, 90], id: \.self) { minutes in
                            Text("\(minutes) 分钟").tag(minutes)
                        }
                    }
                }
                HStack(spacing: 12) {
                    SettingsIcon(symbol: "headphones", color: .indigo)
                    Toggle("计时时自动开启「专注」场景，结束后恢复", isOn: $prefs.timerStartsFocus)
                }
                HStack(spacing: 12) {
                    SettingsIcon(symbol: "bell.fill", color: .orange)
                    Toggle("时间到时播放提示音", isOn: $prefs.timerSound)
                }
            } header: {
                Text("专注计时")
            } footer: {
                Text("点面板里的「专注计时」开始，菜单栏会显示倒计时；在按钮上点右键可以选时长或加时间。")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 通用

private struct GeneralSettingsView: View {
    @ObservedObject var prefs: Preferences

    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginNeedsApproval = LoginItem.needsApproval

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
                Text("也可以点面板里「保持亮屏」右边的「›」，临时选择时长。")
            }

            Section {
                HStack(spacing: 12) {
                    SettingsIcon(symbol: "checkmark.shield.fill", color: .green)
                    Text("SwitchBar 用到了哪些系统权限、怎么确认它不联网，见「安全与权限」。")
                    Spacer()
                    Button("查看") { SettingsRouter.shared.tab = .security }
                }
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

    /// 「快捷指令」列出全部指令要一两秒，放到后台做，不卡住设置窗口
    private func check() {
        checkResult = "正在检查…"
        let wanted = [prefs.dndOnShortcut, prefs.dndOffShortcut]
        DispatchQueue.global(qos: .userInitiated).async {
            let names = Set(Shortcuts.list())
            let missing = wanted.filter { !names.contains($0) }
            DispatchQueue.main.async {
                checkResult = missing.isEmpty ? "✅ 两个快捷指令都找到了" : "❌ 没找到：\(missing.joined(separator: "、"))"
            }
        }
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

// MARK: - 安全与权限

private struct SecurityView: View {
    @State private var accessibility = SecurityCheck.State.notDetermined
    @State private var automation = SecurityCheck.State.notDetermined
    @State private var bluetooth = SecurityCheck.State.notDetermined
    @State private var screenRecording = SecurityCheck.State.denied
    @State private var inputMonitoring = SecurityCheck.State.denied
    @State private var signature: CodeSignature.Info?
    @State private var copied: String?

    private static let lsofCommand = "lsof -i -a -p $(pgrep -x SwitchBar)"
    private static let resetCommand = "tccutil reset All local.switchbar"

    var body: some View {
        Form {
            Section {
                PermissionStatusRow(symbol: "accessibility", color: .blue, title: "辅助功能",
                                    usage: "清洁屏幕：擦屏幕时暂时拦截按键和触控板手势", state: accessibility, needed: true) {
                    SystemSettings.open(.accessibility)
                }
                PermissionStatusRow(symbol: "gearshape.2.fill", color: .gray, title: "自动化 › 系统事件",
                                    usage: "深色模式、隐藏程序坞、隐藏菜单栏", state: automation, needed: true) {
                    SystemSettings.open(.automation)
                }
                PermissionStatusRow(symbol: "headphones", color: .blue, title: "蓝牙",
                                    usage: "连接 / 断开你选择的耳机", state: bluetooth, needed: true) {
                    SystemSettings.open(.bluetoothPrivacy)
                }
            } header: {
                Text("SwitchBar 可能用到的权限")
            } footer: {
                Text("只有第一次使用对应功能时系统才会询问。用不到的功能可以在「功能与快捷键」里隐藏，再到系统设置里把权限关掉。")
            }

            Section {
                PermissionStatusRow(symbol: "record.circle", color: .red, title: "屏幕录制",
                                    usage: "SwitchBar 不需要，代码里也没有任何录屏功能", state: screenRecording, needed: false) {
                    SystemSettings.open(.screenRecording)
                }
                PermissionStatusRow(symbol: "keyboard", color: .gray, title: "输入监控",
                                    usage: "SwitchBar 不需要，快捷键用的是不需要权限的系统接口", state: inputMonitoring, needed: false) {
                    SystemSettings.open(.inputMonitoring)
                }
                HStack(spacing: 12) {
                    SettingsIcon(symbol: "nosign", color: .gray)
                    Text("完全磁盘访问、麦克风、摄像头、定位、通讯录、照片：SwitchBar 从不申请")
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("SwitchBar 不需要的权限")
            } footer: {
                Text("如果这里出现「已允许」，说明系统设置里给了 SwitchBar 不需要的权限，建议点「去关闭」把它关掉。")
            }

            Section {
                SecurityFactRow(symbol: "lock.shield.fill", color: signature?.hardenedRuntime == true ? .green : .orange,
                                title: signature?.hardenedRuntime == true ? "强化运行时：已开启" : "强化运行时：未开启（调试版）",
                                detail: "其他程序不能向 SwitchBar 注入代码、不能用调试器附加，所以没法借用 SwitchBar 已经拿到的权限。")
                SecurityFactRow(symbol: "wifi.slash", color: .green, title: "不联网",
                                detail: "程序里没有任何联网代码；每次构建时 CI 会同时检查源码和编译出来的程序，发现联网函数就直接失败。")
                SecurityFactRow(symbol: "antenna.radiowaves.left.and.right.slash", color: .green, title: "不接受外部指令",
                                detail: "没有网址协议、没有 AppleScript 接口、没有后台服务、不监听任何端口，别的程序或网络上的人都没法遥控它。")
                SecurityFactRow(symbol: "keyboard.fill", color: .green, title: "不记录按键",
                                detail: "清洁屏幕时按键直接丢弃、不保存；全局快捷键只会收到你设置的那几个组合键。")
                SecurityFactRow(symbol: "doc.on.clipboard.fill", color: .green, title: "不监视剪贴板、不看屏幕",
                                detail: "「纯文本」只在你点按钮或按快捷键的那一刻读写一次剪贴板，不保存任何内容；「取色器」用的是系统自带的取色放大镜，SwitchBar 自己看不到屏幕，所以不需要「屏幕录制」权限。")
                SecurityFactRow(symbol: "signature", color: .gray, title: "签名",
                                detail: signatureText)
            } header: {
                Text("防护措施")
            }

            Section {
                CommandRow(title: "确认没有网络连接",
                           detail: "在「终端」运行下面的命令，没有任何输出就说明 SwitchBar 没有任何网络连接：",
                           command: Self.lsofCommand, copied: $copied)
                CommandRow(title: "一键撤销全部权限",
                           detail: "在「终端」运行下面的命令，会清除 SwitchBar 获得的所有系统权限，下次用到时系统会重新询问：",
                           command: Self.resetCommand, copied: $copied)
            } header: {
                Text("自己动手验证")
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            reload()
        }
    }

    private var signatureText: String {
        guard let signature else { return "无法读取（可能是用 swift run 直接运行的开发版）" }
        if let signer = signature.signer { return "由证书「\(signer)」签名" }
        return signature.adHoc ? "临时签名（没有使用证书）" : "已签名"
    }

    private func reload() {
        accessibility = SecurityCheck.accessibility
        automation = SecurityCheck.automation
        bluetooth = SecurityCheck.bluetooth
        screenRecording = SecurityCheck.screenRecording
        inputMonitoring = SecurityCheck.inputMonitoring
        signature = CodeSignature.current()
    }
}

private struct PermissionStatusRow: View {
    let symbol: String
    let color: Color
    let title: String
    let usage: String
    let state: SecurityCheck.State
    /// 是否是 SwitchBar 某些功能需要的权限
    let needed: Bool
    let open: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(symbol: symbol, color: color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(usage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Label(statusText, systemImage: statusSymbol)
                .font(.caption)
                .foregroundColor(statusColor)
            if !needed && state == .granted {
                Button("去关闭", action: open)
            } else if needed {
                Button("打开设置", action: open)
            }
        }
    }

    private var statusText: String {
        switch (needed, state) {
        case (true, .granted): return "已允许"
        case (true, .denied): return "未允许"
        case (true, .notDetermined): return "还没用过"
        case (_, .unknown(let message)): return message
        case (false, .granted): return "已允许，建议关闭"
        case (false, _): return "未允许（正确）"
        }
    }

    private var statusSymbol: String {
        switch (needed, state) {
        case (false, .granted): return "exclamationmark.triangle.fill"
        case (false, _): return "checkmark.circle.fill"
        case (true, .granted): return "checkmark.circle.fill"
        default: return "circle.dashed"
        }
    }

    private var statusColor: Color {
        switch (needed, state) {
        case (false, .granted): return .orange
        case (false, _), (true, .granted): return .green
        default: return .secondary
        }
    }
}

private struct SecurityFactRow: View {
    let symbol: String
    let color: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SettingsIcon(symbol: symbol, color: color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct CommandRow: View {
    let title: String
    let detail: String
    let command: String
    @Binding var copied: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text(command)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
                Spacer()
                Button(copied == command ? "已复制" : "复制") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                    copied = command
                }
            }
        }
        .padding(.vertical, 2)
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
                Text("夜览：CoreBrightness 框架（系统设置自己也用它）\n锁定屏幕：login 框架的 SACLockScreenImmediate（不可用时退回「关闭显示器」）\n它们都只在本机调用系统自带功能；如果将来 macOS 移除了这些接口，对应开关会自动变灰，不会崩溃。")
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
