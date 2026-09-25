import AppKit
import Combine

/// 所有开关的状态和操作都集中在这里，面板和全局快捷键共用同一套逻辑
final class SwitchStore: ObservableObject {
    static let shared = SwitchStore()

    @Published private(set) var states: [FeatureID: Bool] = [:]
    @Published private(set) var unavailable: Set<FeatureID> = []
    @Published private(set) var busy: Set<FeatureID> = []
    /// 正在生效的场景
    @Published private(set) var activeScenes: Set<SceneID> = []
    /// 专注计时是否在进行
    @Published private(set) var timerRunning = false
    /// 电池电量（没有电池时为 nil）
    @Published private(set) var battery: Battery.Status?

    let prefs = Preferences.shared
    let keepAwake = KeepAwake()
    let inputLocker = InputLocker()
    let focusTimer = FocusTimer()
    private let nightShift = NightShift()
    private let trueTone = TrueTone()
    private let bluetooth = BluetoothAudio()

    /// 关闭菜单栏弹出面板（由 StatusBarController 设置）
    var closePanel: (() -> Void)?

    /// 专注计时每秒回调（由 StatusBarController 设置，用来更新菜单栏上的倒计时）
    var onTimerTick: (() -> Void)?

    /// 能否直接读到系统的勿扰状态（读不到时用自己记录的状态）
    private var canReadFocusStatus = false

    /// 每个场景开启时实际打开了哪些开关（关闭场景时只关这些，原本就开着的不动）
    private var sceneChanges: [SceneID: [FeatureID]] = [:]
    /// 专注计时是否顺带开启了「专注」场景
    private var timerActivatedFocus = false

    private init() {
        keepAwake.onChange = { [weak self] in self?.refresh() }
        inputLocker.onChange = { [weak self] in self?.refresh() }
        focusTimer.onTick = { [weak self] in self?.onTimerTick?() }
        focusTimer.onEnd = { [weak self] completed in self?.timerEnded(completed: completed) }
    }

    // MARK: - 状态

    /// 不可用的开关一律显示为关
    func isOn(_ feature: FeatureID) -> Bool { isAvailable(feature) && (states[feature] ?? false) }

    func isAvailable(_ feature: FeatureID) -> Bool { !unavailable.contains(feature) }

    func isBusy(_ feature: FeatureID) -> Bool { busy.contains(feature) }

    /// 重新读取系统里各个开关的真实状态
    func refresh() {
        var s: [FeatureID: Bool] = [:]
        s[.hideDesktop] = Finder.isDesktopHidden
        s[.darkMode] = Appearance.isDark
        s[.keepAwake] = keepAwake.isActive
        let focus = FocusStatus.readActive()
        canReadFocusStatus = focus != nil
        s[.doNotDisturb] = focus ?? prefs.dndActive
        s[.nightShift] = nightShift.isEnabled
        s[.trueTone] = trueTone.isEnabled
        s[.micMute] = AudioMute.input.isMuted
        s[.muteSound] = AudioMute.output.isMuted
        // 没选过耳机就不碰蓝牙，避免一启动就弹出蓝牙权限请求
        s[.bluetoothAudio] = prefs.bluetoothAddress.isEmpty ? false : bluetooth.isConnected(address: prefs.bluetoothAddress)
        s[.hiddenFiles] = Finder.showsHiddenFiles
        s[.autoHideDock] = Dock.isAutoHidden
        s[.autoHideMenuBar] = MenuBar.isAutoHidden
        s[.lockKeyboard] = inputLocker.mode == .keyboard
        s[.cleanScreen] = inputLocker.mode == .cleaning

        var u: Set<FeatureID> = []
        if !nightShift.isSupported { u.insert(.nightShift) }
        if !trueTone.isSupported { u.insert(.trueTone) }
        if !AudioMute.input.isAvailable { u.insert(.micMute) }
        if !AudioMute.output.isAvailable { u.insert(.muteSound) }

        if s != states { states = s }
        if u != unavailable { unavailable = u }
        let status = Battery.current()
        if status != battery { battery = status }
    }

    private func refreshSoon(after delay: TimeInterval = 0.8) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.refresh()
        }
    }

    func title(for feature: FeatureID) -> String {
        if feature == .bluetoothAudio, !prefs.bluetoothName.isEmpty {
            return prefs.bluetoothName
        }
        return feature.title
    }

    /// 开关下面的一行状态文字，例如「开启」「还剩 42 分钟」「已连接」
    func stateText(for feature: FeatureID) -> String {
        if !isAvailable(feature) {
            switch feature {
            case .micMute: return "没有麦克风"
            case .muteSound: return "没有输出设备"
            default: return "此 Mac 不支持"
            }
        }
        if isBusy(feature) { return "正在切换…" }
        let on = isOn(feature)
        switch feature {
        case .keepAwake:
            guard on else { return "关闭" }
            return keepAwake.remainingMinutes.map { "还剩 \($0) 分钟" } ?? "一直保持"
        case .micMute, .muteSound:
            return on ? "已静音" : "未静音"
        case .bluetoothAudio:
            if prefs.bluetoothAddress.isEmpty { return "选择耳机" }
            return on ? "已连接" : "未连接"
        default:
            return on ? "开启" : "关闭"
        }
    }

    func tooltip(for feature: FeatureID) -> String {
        var parts = [feature.title]
        if !isAvailable(feature) {
            switch feature {
            case .micMute: parts.append("没有检测到麦克风")
            case .muteSound: parts.append("没有检测到扬声器或耳机")
            default: parts.append("这台 Mac 不支持")
            }
        }
        if feature == .keepAwake, keepAwake.isActive {
            parts.append(keepAwake.remainingMinutes.map { "还剩 \($0) 分钟" } ?? "一直保持中")
        }
        if feature == .audioOutput {
            if let output = AudioDevices.defaultDeviceName(output: true) { parts.append("输出：\(output)") }
            if let input = AudioDevices.defaultDeviceName(output: false) { parts.append("输入：\(input)") }
        }
        if feature == .doNotDisturb, !canReadFocusStatus {
            parts.append("通过「快捷指令」切换")
        }
        if let key = prefs.hotKeys[feature] {
            parts.append("快捷键 \(key.displayString)")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - 执行

    func trigger(_ feature: FeatureID, fromHotKey: Bool = false) {
        guard isAvailable(feature), !isBusy(feature) else { return }

        switch feature {
        case .hideDesktop:
            let target = !Finder.isDesktopHidden
            Finder.setDesktopHidden(target)
            didToggle(feature, to: target, fromHotKey)

        case .darkMode:
            let target = !Appearance.isDark
            if let error = Appearance.setDark(target) {
                report(error)
            } else {
                didToggle(feature, to: target, fromHotKey)
            }

        case .keepAwake:
            if keepAwake.isActive {
                keepAwake.stop()
                didToggle(feature, to: false, fromHotKey)
            } else {
                startKeepAwake(minutes: prefs.keepAwakeMinutes, fromHotKey: fromHotKey)
            }

        case .doNotDisturb:
            setDoNotDisturb(!currentDoNotDisturb, fromHotKey: fromHotKey)

        case .nightShift:
            let target = !nightShift.isEnabled
            if nightShift.setEnabled(target) {
                didToggle(feature, to: target, fromHotKey)
            } else {
                report("无法切换夜览")
            }

        case .trueTone:
            let target = !trueTone.isEnabled
            if trueTone.setEnabled(target) {
                didToggle(feature, to: target, fromHotKey)
            } else {
                report("无法切换原彩显示")
            }

        case .micMute:
            let target = !AudioMute.input.isMuted
            if AudioMute.input.setMuted(target) {
                didToggle(feature, to: target, fromHotKey)
            } else {
                report("当前输入设备不支持静音或调节音量")
            }

        case .muteSound:
            let target = !AudioMute.output.isMuted
            if AudioMute.output.setMuted(target) {
                didToggle(feature, to: target, fromHotKey)
            } else {
                report("当前输出设备不支持静音或调节音量")
            }

        case .bluetoothAudio:
            toggleBluetooth(fromHotKey: fromHotKey)

        case .hiddenFiles:
            let target = !Finder.showsHiddenFiles
            Finder.setShowsHiddenFiles(target)
            didToggle(feature, to: target, fromHotKey)

        case .autoHideDock:
            let target = !Dock.isAutoHidden
            if let error = Dock.setAutoHide(target) {
                report(error)
            } else {
                didToggle(feature, to: target, fromHotKey)
            }

        case .autoHideMenuBar:
            let target = !MenuBar.isAutoHidden
            if let error = MenuBar.setAutoHide(target) {
                report(error)
            } else {
                didToggle(feature, to: target, fromHotKey)
            }

        case .lockScreen:
            closePanel?()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { ScreenLock.lock() }

        case .lockKeyboard:
            startInputLock(.keyboard)

        case .cleanScreen:
            startInputLock(.cleaning)

        case .ejectDisks:
            ejectAll()

        case .screenSaver:
            closePanel?()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { ScreenSaver.start() }

        case .displayResolution, .audioOutput:
            showOptionsMenu(for: feature)
        }
    }

    /// 把某个开关切到指定状态（已经是这个状态就什么都不做）
    private func setFeature(_ feature: FeatureID, on: Bool) {
        guard feature.kind == .toggle, isAvailable(feature), isOn(feature) != on else { return }
        // 没选过耳机时，场景里的「蓝牙耳机」直接跳过，不弹菜单
        if feature == .bluetoothAudio && prefs.bluetoothAddress.isEmpty { return }
        trigger(feature)
    }

    // MARK: - 场景

    func toggleScene(_ scene: SceneID, fromHotKey: Bool = false) {
        let turningOn = !activeScenes.contains(scene)
        if turningOn {
            activateScene(scene)
        } else {
            deactivateScene(scene)
        }
        if fromHotKey && prefs.showHUD {
            HUD.shared.show("\(scene.title)模式：\(turningOn ? "开" : "关")", symbol: scene.symbol)
        }
    }

    private func activateScene(_ scene: SceneID) {
        let toTurnOn = prefs.members(of: scene).filter { isAvailable($0) && !isOn($0) }
        activeScenes.insert(scene)
        sceneChanges[scene] = toTurnOn
        for feature in toTurnOn {
            setFeature(feature, on: true)
        }
    }

    private func deactivateScene(_ scene: SceneID) {
        activeScenes.remove(scene)
        let changed = sceneChanges.removeValue(forKey: scene) ?? []
        // 其他还开着的场景也需要的开关，先不关
        let stillNeeded = Set(activeScenes.flatMap { prefs.members(of: $0) })
        for feature in changed where !stillNeeded.contains(feature) {
            setFeature(feature, on: false)
        }
    }

    // MARK: - 专注计时

    func toggleTimer(fromHotKey: Bool = false) {
        if timerRunning {
            focusTimer.stop()
            if fromHotKey && prefs.showHUD {
                HUD.shared.show("专注计时已停止", symbol: "timer")
            }
        } else {
            startTimer()
            if fromHotKey && prefs.showHUD {
                HUD.shared.show("开始专注 \(prefs.timerMinutes) 分钟", symbol: "timer")
            }
        }
    }

    func startTimer(minutes: Int? = nil) {
        focusTimer.start(minutes: minutes ?? prefs.timerMinutes)
        timerRunning = true
        if prefs.timerStartsFocus && !activeScenes.contains(.focus) {
            activateScene(.focus)
            timerActivatedFocus = true
        }
    }

    func extendTimer(minutes: Int) {
        focusTimer.extend(minutes: minutes)
    }

    private func timerEnded(completed: Bool) {
        timerRunning = false
        if timerActivatedFocus {
            timerActivatedFocus = false
            if activeScenes.contains(.focus) { deactivateScene(.focus) }
        }
        if completed {
            if prefs.timerSound { NSSound(named: NSSound.Name("Glass"))?.play() }
            HUD.shared.show("时间到，休息一下", symbol: "cup.and.saucer.fill", duration: 4)
        }
        onTimerTick?()
    }

    func openSettings(tab: SettingsTab? = nil) {
        closePanel?()
        SettingsWindowController.shared.show(tab: tab)
    }

    /// 退出时收尾：释放「保持亮屏」、解除键盘锁定
    func shutdown() {
        focusTimer.onEnd = nil
        focusTimer.stop()
        keepAwake.stop(notify: false)
        inputLocker.stop()
    }

    private func didToggle(_ feature: FeatureID, to on: Bool, _ fromHotKey: Bool) {
        states[feature] = on
        if fromHotKey && prefs.showHUD {
            HUD.shared.show("\(title(for: feature))：\(on ? "开" : "关")", symbol: feature.symbol(on: on))
        }
        refreshSoon()
    }

    private func report(_ message: String) {
        HUD.shared.show(message, symbol: "exclamationmark.triangle.fill", duration: 4)
    }

    // MARK: - 保持亮屏

    private func startKeepAwake(minutes: Int, fromHotKey: Bool) {
        if keepAwake.start(minutes: minutes) {
            didToggle(.keepAwake, to: true, fromHotKey)
        } else {
            report("无法开启保持亮屏")
        }
    }

    // MARK: - 勿扰模式

    private var currentDoNotDisturb: Bool {
        FocusStatus.readActive() ?? prefs.dndActive
    }

    private func setDoNotDisturb(_ on: Bool, fromHotKey: Bool) {
        let name = on ? prefs.dndOnShortcut : prefs.dndOffShortcut
        busy.insert(.doNotDisturb)
        Shortcuts.run(name) { [weak self] ok in
            guard let self else { return }
            self.busy.remove(.doNotDisturb)
            if ok {
                self.prefs.dndActive = on
                self.didToggle(.doNotDisturb, to: on, fromHotKey)
            } else {
                self.report("没有找到快捷指令「\(name)」。请到 设置 › 勿扰模式 按说明创建。")
            }
        }
    }

    // MARK: - 蓝牙耳机

    private func toggleBluetooth(fromHotKey: Bool) {
        let address = prefs.bluetoothAddress
        guard !address.isEmpty else {
            if fromHotKey {
                report("请先在面板里点蓝牙耳机右上角的箭头，选择一副耳机")
            } else {
                showOptionsMenu(for: .bluetoothAudio)
            }
            return
        }
        if bluetooth.isConnected(address: address) {
            bluetooth.disconnect(address: address)
            didToggle(.bluetoothAudio, to: false, fromHotKey)
        } else {
            connectBluetooth(address: address, name: title(for: .bluetoothAudio), fromHotKey: fromHotKey)
        }
    }

    private func connectBluetooth(address: String, name: String, fromHotKey: Bool) {
        busy.insert(.bluetoothAudio)
        bluetooth.connect(address: address) { [weak self] ok in
            guard let self else { return }
            self.busy.remove(.bluetoothAudio)
            if ok {
                self.didToggle(.bluetoothAudio, to: true, fromHotKey)
            } else {
                self.report("连接「\(name)」失败，请确认耳机已打开盒盖、并且在附近")
                self.refreshSoon(after: 0)
            }
        }
    }

    // MARK: - 锁定键盘 / 清洁屏幕

    private func startInputLock(_ mode: InputLocker.Mode) {
        closePanel?()
        inputLocker.startWhenModifiersReleased(mode) { [weak self] error in
            if let error { self?.report(error) }
        }
    }

    // MARK: - 推出磁盘

    private func ejectAll() {
        eject(Disks.ejectableVolumes())
    }

    private func eject(_ volumes: [Disks.Volume]) {
        guard !volumes.isEmpty else {
            HUD.shared.show("没有可推出的磁盘", symbol: "eject")
            return
        }
        busy.insert(.ejectDisks)
        Disks.eject(volumes) { [weak self] failed in
            guard let self else { return }
            self.busy.remove(.ejectDisks)
            if failed.isEmpty {
                let text = volumes.count == 1 ? "已推出「\(volumes[0].name)」" : "已推出 \(volumes.count) 个磁盘"
                HUD.shared.show(text, symbol: "eject.fill")
            } else {
                self.report("无法推出：\(failed.joined(separator: "、"))（可能有程序正在使用）")
            }
        }
    }

    // MARK: - 更多选项菜单

    func showOptionsMenu(for feature: FeatureID) {
        guard let menu = optionsMenu(for: feature) else { return }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private func optionsMenu(for feature: FeatureID) -> NSMenu? {
        let menu = NSMenu()
        menu.autoenablesItems = false

        switch feature {
        case .keepAwake:
            let choices: [(String, Int)] = [
                ("一直保持", 0), ("15 分钟", 15), ("30 分钟", 30), ("1 小时", 60),
                ("2 小时", 120), ("4 小时", 240), ("8 小时", 480),
            ]
            menu.addItem(ClosureMenuItem.header("保持亮屏多久"))
            for (title, minutes) in choices {
                menu.addItem(ClosureMenuItem(title) { [weak self] in
                    self?.startKeepAwake(minutes: minutes, fromHotKey: false)
                })
            }
            if keepAwake.isActive {
                menu.addItem(.separator())
                menu.addItem(ClosureMenuItem("关闭保持亮屏") { [weak self] in
                    self?.keepAwake.stop()
                })
            }

        case .doNotDisturb:
            menu.addItem(ClosureMenuItem("开启勿扰模式") { [weak self] in
                self?.setDoNotDisturb(true, fromHotKey: false)
            })
            menu.addItem(ClosureMenuItem("关闭勿扰模式") { [weak self] in
                self?.setDoNotDisturb(false, fromHotKey: false)
            })
            menu.addItem(.separator())
            menu.addItem(ClosureMenuItem("设置快捷指令…") { [weak self] in
                self?.openSettings(tab: .focus)
            })

        case .bluetoothAudio:
            let devices = bluetooth.pairedAudioDevices()
            menu.addItem(ClosureMenuItem.header("选择耳机"))
            if devices.isEmpty {
                menu.addItem(ClosureMenuItem("没有已配对的蓝牙音频设备", handler: nil))
            }
            for device in devices {
                let title = device.isConnected ? "\(device.name)（已连接）" : device.name
                let item = ClosureMenuItem(title, checked: device.address == prefs.bluetoothAddress) { [weak self] in
                    guard let self else { return }
                    self.prefs.bluetoothAddress = device.address
                    self.prefs.bluetoothName = device.name
                    if !device.isConnected {
                        self.connectBluetooth(address: device.address, name: device.name, fromHotKey: false)
                    } else {
                        self.refresh()
                    }
                }
                menu.addItem(item)
            }
            if !prefs.bluetoothAddress.isEmpty {
                menu.addItem(.separator())
                menu.addItem(ClosureMenuItem("取消选择") { [weak self] in
                    self?.prefs.bluetoothAddress = ""
                    self?.prefs.bluetoothName = ""
                    self?.refresh()
                })
            }
            menu.addItem(.separator())
            menu.addItem(ClosureMenuItem("打开蓝牙设置…") { SystemSettings.open(.bluetooth) })

        case .ejectDisks:
            let volumes = Disks.ejectableVolumes()
            if volumes.isEmpty {
                menu.addItem(ClosureMenuItem("没有可推出的磁盘", handler: nil))
            } else {
                for volume in volumes {
                    menu.addItem(ClosureMenuItem("推出「\(volume.name)」") { [weak self] in
                        self?.eject([volume])
                    })
                }
                if volumes.count > 1 {
                    menu.addItem(.separator())
                    menu.addItem(ClosureMenuItem("全部推出") { [weak self] in
                        self?.eject(volumes)
                    })
                }
            }

        case .displayResolution:
            let displays = Displays.all()
            if displays.isEmpty {
                menu.addItem(ClosureMenuItem("没有检测到显示器", handler: nil))
            }
            for (index, display) in displays.enumerated() {
                if index > 0 { menu.addItem(.separator()) }
                menu.addItem(ClosureMenuItem.header(display.name))
                addModes(display.primaryModes, of: display, to: menu)
                if !display.otherModes.isEmpty {
                    let submenu = NSMenu()
                    submenu.autoenablesItems = false
                    addModes(display.otherModes, of: display, to: submenu)
                    let more = NSMenuItem(title: "更多分辨率（非 HiDPI）", action: nil, keyEquivalent: "")
                    more.submenu = submenu
                    menu.addItem(more)
                }
            }

        case .audioOutput:
            addAudioDevices(output: true, to: menu)
            menu.addItem(.separator())
            addAudioDevices(output: false, to: menu)
            menu.addItem(.separator())
            menu.addItem(ClosureMenuItem("声音设置…") { SystemSettings.open(.sound) })

        default:
            return nil
        }
        return menu
    }

    private func addAudioDevices(output: Bool, to menu: NSMenu) {
        menu.addItem(ClosureMenuItem.header(output ? "输出" : "输入"))
        let devices = AudioDevices.all(output: output)
        let current = AudioDevices.defaultDevice(output: output)
        if devices.isEmpty {
            menu.addItem(ClosureMenuItem(output ? "没有输出设备" : "没有输入设备", handler: nil))
        }
        for device in devices {
            menu.addItem(ClosureMenuItem(device.name, checked: device.id == current) { [weak self] in
                if AudioDevices.setDefault(device.id, output: output) {
                    HUD.shared.show(device.name, symbol: output ? "hifispeaker.2.fill" : "mic.fill")
                    self?.refreshSoon(after: 0.3)
                } else {
                    self?.report("切换到「\(device.name)」失败")
                }
            })
        }
    }

    private func addModes(_ modes: [Displays.ModeOption], of display: Displays.Display, to menu: NSMenu) {
        for option in modes {
            let item = ClosureMenuItem(option.title, checked: option.isCurrent) { [weak self] in
                if !Displays.apply(option.mode, to: display.id) {
                    self?.report("切换分辨率失败")
                }
            }
            menu.addItem(item)
        }
    }
}

#if DEBUG
extension SwitchStore {
    /// 仅调试版截图用：直接标记场景为开启，不去真的切换系统设置
    func debugMarkSceneActive(_ scene: SceneID) {
        activeScenes.insert(scene)
    }

    /// 仅调试版截图用：开始计时但不联动场景
    func debugStartTimer(minutes: Int) {
        focusTimer.start(minutes: minutes)
        timerRunning = true
    }
}
#endif
