import AppKit
import Combine
import SwiftUI

@main
struct SwitchBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // 菜单栏应用没有主窗口；这里的 Settings 只是让 ⌘, 也能打开设置
        Settings {
            SettingsView(store: SwitchStore.shared, prefs: Preferences.shared, router: SettingsRouter.shared)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 不在程序坞显示图标（Info.plist 里的 LSUIElement 也会做同样的事）
        NSApp.setActivationPolicy(.accessory)

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

        let store = SwitchStore.shared
        let prefs = Preferences.shared
        store.refresh()
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
}
