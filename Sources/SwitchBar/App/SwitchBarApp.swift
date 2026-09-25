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
        if Snapshot.runIfRequested() {
            NSApp.terminate(nil)
            return
        }
        #endif

        let store = SwitchStore.shared
        store.refresh()
        statusBar = StatusBarController(store: store)

        let hotKeys = HotKeyManager.shared
        hotKeys.onTrigger = { feature in
            store.trigger(feature, fromHotKey: true)
        }
        hotKeys.apply(Preferences.shared.hotKeys)
        Preferences.shared.$hotKeys
            .dropFirst()
            .sink { hotKeys.apply($0) }
            .store(in: &cancellables)
    }

    func applicationWillTerminate(_ notification: Notification) {
        SwitchStore.shared.shutdown()
    }
}
