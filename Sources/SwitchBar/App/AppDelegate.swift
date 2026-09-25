import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 不在程序坞显示图标（Info.plist 里的 LSUIElement 也会做同样的事）
        NSApp.setActivationPolicy(.accessory)
        installMainMenu()

        #if DEBUG
        // 调试版的截图模式会自己退出
        if Snapshot.runIfRequested() { return }
        #endif

        // 已经有一个 SwitchBar 在运行（比如又双击了一次），就不要再放一个图标到菜单栏
        if let bundleID = Bundle.main.bundleIdentifier {
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .filter { $0 != NSRunningApplication.current }
            if !others.isEmpty {
                NSApp.terminate(nil)
                return
            }
        }

        // 启动时不读取各个开关的状态：第一次打开面板时才读，用不到的系统框架就不会被加载
        let store = SwitchStore.shared
        let prefs = Preferences.shared
        let statusBar = StatusBarController(store: store)
        self.statusBar = statusBar

        let hotKeys = HotKeyManager.shared
        hotKeys.onTrigger = { target in
            switch target {
            case .panel:
                statusBar.togglePanel()
            case .feature(let feature):
                store.trigger(feature, fromHotKey: true)
            case .scene(let scene):
                store.toggleScene(scene, fromHotKey: true)
            case .timer:
                store.toggleTimer(fromHotKey: true)
            }
        }
        hotKeys.apply(prefs.allHotKeys)
        prefs.hotKeysChanged
            .sink { hotKeys.apply(prefs.allHotKeys) }
            .store(in: &cancellables)
    }

    func applicationWillTerminate(_ notification: Notification) {
        SwitchStore.shared.shutdown()
    }

    @objc private func openSettings(_ sender: Any?) {
        SwitchStore.shared.openSettings()
    }

    /// 菜单栏应用看不到主菜单，但设置窗口里的输入框要靠它才能用 ⌘C / ⌘V / ⌘A，⌘W 才能关窗口
    private func installMainMenu() {
        let main = NSMenu()

        let appMenu = NSMenu(title: "SwitchBar")
        let settings = appMenu.addItem(withTitle: "设置…", action: #selector(openSettings(_:)), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 SwitchBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(withTitle: "关闭", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")

        for submenu in [appMenu, editMenu, windowMenu] {
            let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
            item.submenu = submenu
            main.addItem(item)
        }
        NSApp.mainMenu = main
    }
}
