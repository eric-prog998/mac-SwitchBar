#if DEBUG
import AppKit
import SwiftUI

/// 仅调试版（swift build 默认）包含：把界面渲染成 PNG，方便在 CI 里检查界面、确认启动不崩溃。
/// 发布版（make install / Releases 使用的 release）里完全没有这段代码。
///
/// 用法：SWITCHBAR_SNAPSHOT_DIR=/tmp/shots .build/debug/SwitchBar
/// 另加 SWITCHBAR_SNAPSHOT_LIVE=1 时，会把真实的面板、设置窗口、提示框依次显示在屏幕上，
/// 并把窗口编号写进 windows-<阶段>.txt，由 CI 用 screencapture 截取真实效果（包括液态玻璃）。
enum Snapshot {
    private static var directory = URL(fileURLWithPath: "/tmp")
    private static var panel: MenuPanelController<PanelView>?

    private struct Phase {
        let name: String
        let appearance: NSAppearance.Name
        let tab: SettingsTab
    }

    private static let phases: [Phase] = [
        Phase(name: "light", appearance: .aqua, tab: .features),
        Phase(name: "dark", appearance: .darkAqua, tab: .features),
        Phase(name: "light-scenes", appearance: .aqua, tab: .scenes),
        Phase(name: "dark-scenes", appearance: .darkAqua, tab: .scenes),
        Phase(name: "light-general", appearance: .aqua, tab: .general),
        Phase(name: "light-focus", appearance: .aqua, tab: .focus),
        Phase(name: "light-security", appearance: .aqua, tab: .security),
        Phase(name: "dark-security", appearance: .darkAqua, tab: .security),
        Phase(name: "light-about", appearance: .aqua, tab: .about),
    ]

    static func runIfRequested() -> Bool {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["SWITCHBAR_SNAPSHOT_DIR"] else { return false }
        directory = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let store = SwitchStore.shared
        store.keepAwake.start(minutes: 60) // 让截图里有「开启」的开关、场景和计时
        store.debugMarkSceneActive(.focus)
        store.debugStartTimer(minutes: 25)
        store.refresh()
        print("states: \(store.states.map { "\($0.key.rawValue)=\($0.value)" }.sorted())")
        print("unavailable: \(store.unavailable.map(\.rawValue).sorted())")

        checkPanelRelease(store)
        renderStatic(store)

        if environment["SWITCHBAR_SNAPSHOT_LIVE"] != nil {
            write(phases.map(\.name).joined(separator: "\n") + "\n", to: "phases.txt")
            runPhase(0)
        } else {
            finish()
        }
        return true
    }

    // MARK: - 面板反复打开 / 关闭后内存要能回收

    private static func checkPanelRelease(_ store: SwitchStore) {
        let panel = MenuPanelController { PanelView(store: store, prefs: store.prefs) }
        func cycle() {
            panel.show(below: nil)
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            panel.close()
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        }
        cycle() // 第一次打开会加载 SwiftUI 等框架，不算
        let before = footprintMB()
        for _ in 0..<10 { cycle() }
        let after = footprintMB()
        print(String(format: "panel open/close x10: footprint %.1f MB -> %.1f MB, window released: %@",
                     before, after, panel.windowNumber == nil ? "yes" : "no"))
    }

    private static func footprintMB() -> Double {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0)
            }
        }
        return result == 0 ? Double(info.ri_phys_footprint) / 1_048_576 : -1
    }

    // MARK: - 离屏渲染

    private static func renderStatic(_ store: SwitchStore) {
        for (appearance, suffix) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
            render(PanelView(store: store, prefs: store.prefs), appearance: appearance, name: "panel-\(suffix)")
        }
        for tab in SettingsTab.allCases {
            SettingsRouter.shared.tab = tab
            render(SettingsView(store: store, prefs: store.prefs, router: SettingsRouter.shared), appearance: .aqua,
                   name: "settings-\(tab.rawValue)")
        }
        render(CleaningView(showsControls: true) {}.frame(width: 800, height: 500), appearance: .darkAqua,
               name: "lock-cleaning")
    }

    private static func render<V: View>(_ view: V, appearance: NSAppearance.Name, name: String) {
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
            try? rep.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("\(name).png"))
        }
        window.orderOut(nil)
    }

    // MARK: - 屏幕上的真实窗口

    private static func runPhase(_ index: Int) {
        guard index < phases.count else {
            finish()
            return
        }
        let phase = phases[index]
        NSApp.appearance = NSAppearance(named: phase.appearance)

        let store = SwitchStore.shared
        let panel = self.panel ?? MenuPanelController { PanelView(store: store, prefs: store.prefs) }
        self.panel = panel
        panel.close()
        panel.show(below: nil)

        SettingsWindowController.shared.show(tab: phase.tab)
        if index % 2 == 0 {
            HUD.shared.show("深色模式：开", symbol: "moon.fill", duration: 60)
        } else {
            HUD.shared.show("已复制 #0A84FF", symbol: "circle.fill", color: .systemBlue, duration: 60)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            var lines = ""
            if let number = panel.windowNumber { lines += "panel \(number)\n" }
            if let number = SettingsWindowController.shared.windowNumber { lines += "settings \(number)\n" }
            if let number = HUD.shared.windowNumber { lines += "hud \(number)\n" }
            write(lines, to: "windows-\(phase.name).txt")
            waitForCapture(phase.name, attemptsLeft: 120) {
                runPhase(index + 1)
            }
        }
    }

    private static func waitForCapture(_ phase: String, attemptsLeft: Int, then next: @escaping () -> Void) {
        let marker = directory.appendingPathComponent("captured-\(phase)").path
        if FileManager.default.fileExists(atPath: marker) || attemptsLeft <= 0 {
            next()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            waitForCapture(phase, attemptsLeft: attemptsLeft - 1, then: next)
        }
    }

    private static func write(_ text: String, to name: String) {
        try? text.write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    private static func finish() {
        print("snapshots written to \(directory.path)")
        SwitchStore.shared.keepAwake.stop(notify: false)
        NSApp.terminate(nil)
    }
}
#endif
