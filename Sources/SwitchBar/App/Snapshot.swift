#if DEBUG
import AppKit
import SwiftUI

/// 仅调试版（swift build 默认）包含：把界面渲染成 PNG，方便在 CI 里检查界面、确认启动不崩溃。
/// 发布版（make install 使用的 release）里完全没有这段代码。
/// 用法：SWITCHBAR_SNAPSHOT_DIR=/tmp/shots .build/debug/SwitchBar
enum Snapshot {
    static func runIfRequested() -> Bool {
        guard let path = ProcessInfo.processInfo.environment["SWITCHBAR_SNAPSHOT_DIR"] else { return false }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let store = SwitchStore.shared
        store.refresh()
        print("states: \(store.states.map { "\($0.key.rawValue)=\($0.value)" }.sorted())")
        print("unavailable: \(store.unavailable.map(\.rawValue).sorted())")

        for (appearance, suffix) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
            render(PanelView(store: store, prefs: store.prefs), appearance: appearance,
                   to: directory.appendingPathComponent("panel-\(suffix).png"))
        }
        let tabs: [(SettingsTab, String)] = [(.features, "features"), (.general, "general"), (.focus, "focus"), (.about, "about")]
        for (tab, name) in tabs {
            SettingsRouter.shared.tab = tab
            render(SettingsView(store: store, prefs: store.prefs, router: SettingsRouter.shared), appearance: .aqua,
                   to: directory.appendingPathComponent("settings-\(name).png"))
        }
        render(KeyboardLockView {}, appearance: .darkAqua, to: directory.appendingPathComponent("lock-keyboard.png"))
        render(CleaningView(showsControls: true) {}.frame(width: 800, height: 500), appearance: .darkAqua,
               to: directory.appendingPathComponent("lock-cleaning.png"))
        print("snapshots written to \(directory.path)")
        return true
    }

    private static func render<V: View>(_ view: V, appearance: NSAppearance.Name, to url: URL) {
        let hosting = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
        let size = hosting.fittingSize
        let window = NSWindow(contentRect: NSRect(x: 40, y: 40, width: size.width, height: size.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = hosting
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        hosting.display()
        if let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
        }
        window.orderOut(nil)
    }
}
#endif
