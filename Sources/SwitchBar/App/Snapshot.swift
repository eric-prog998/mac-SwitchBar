#if DEBUG
import AppKit
import SwiftUI

/// 仅调试版（swift build 默认）包含：把界面渲染成 PNG，方便在 CI 里检查界面、确认启动不崩溃。
/// 发布版（make install / Releases 使用的 release）里完全没有这段代码。
///
/// 用法：SWITCHBAR_SNAPSHOT_DIR=/tmp/shots .build/debug/SwitchBar
/// 另加 SWITCHBAR_SNAPSHOT_LIVE=1 时，会把真实的面板、设置窗口、提示框依次显示在屏幕上，
/// 并把窗口编号写进 windows-<阶段>.txt，由 CI 用 screencapture 截取真实效果（包括液态玻璃）。
///
/// 截图之前还会检查「常驻很轻」的几个前提：面板、设置窗口、提示框关掉后界面真的被释放了，
/// 反复打开面板后空闲时的唤醒次数不会变多（界面里的每秒刷新没有留在后台），清洁屏幕的窗口大小正确。
/// 任何一项不通过，程序以失败状态退出，CI 会变红。
enum Snapshot {
    private static var directory = URL(fileURLWithPath: "/tmp")
    private static var panel: MenuPanelController<PanelView>?
    private static var failures: [String] = []

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
        // 先在「什么都没开」的状态下检查释放和空闲唤醒（开着计时器时每秒都会唤醒，没法比较）
        checkReleases(store)

        store.keepAwake.start(minutes: 60) // 让截图里有「开启」的开关、场景和计时
        store.debugMarkSceneActive(.focus)
        store.debugStartTimer(minutes: 25)
        store.refresh()
        print("states: \(store.states.map { "\($0.key.rawValue)=\($0.value)" }.sorted())")
        print("unavailable: \(store.unavailable.map(\.rawValue).sorted())")

        renderStatic(store)

        if environment["SWITCHBAR_SNAPSHOT_LIVE"] != nil {
            write(phases.map(\.name).joined(separator: "\n") + "\n", to: "phases.txt")
            runPhase(0)
        } else {
            finish()
        }
        return true
    }

    // MARK: - 关掉的界面要真的释放，空闲时不能有残留的刷新

    private struct Usage {
        let footprintMB: Double
        let cpuSeconds: Double
        let wakeups: UInt64
    }

    private static func usage() -> Usage {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0)
            }
        }
        guard result == 0 else { return Usage(footprintMB: -1, cpuSeconds: -1, wakeups: 0) }
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let ticks = Double(info.ri_user_time + info.ri_system_time)
        return Usage(footprintMB: Double(info.ri_phys_footprint) / 1_048_576,
                     cpuSeconds: ticks * Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000,
                     wakeups: info.ri_pkg_idle_wkups + info.ri_interrupt_wkups)
    }

    private static func spin(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    /// 空闲 seconds 秒期间的唤醒次数和 CPU 时间
    private static func idle(_ seconds: TimeInterval) -> (wakeups: UInt64, cpu: Double) {
        let start = usage()
        spin(seconds)
        let end = usage()
        return (end.wakeups - start.wakeups, end.cpuSeconds - start.cpuSeconds)
    }

    private static func check(_ ok: Bool, _ message: String) {
        print("[check] \(ok ? "OK" : "FAIL") \(message)")
        if !ok { failures.append(message) }
    }

    private static func checkReleases(_ store: SwitchStore) {
        // 面板：关掉后界面控制器要被释放
        let panel = MenuPanelController { PanelView(store: store, prefs: store.prefs) }
        panel.show(below: nil)
        spin(0.3)
        weak var hosting = panel.debugHosting
        check(hosting != nil, "面板打开后有界面")
        panel.close()
        spin(0.3)
        check(hosting == nil && panel.windowNumber == nil, "面板关闭后界面和窗口已释放")

        // 反复打开 / 关闭 20 次：内存不能一直涨，空闲唤醒不能变多
        let baseline = idle(3)
        let before = usage()
        for _ in 0..<20 {
            panel.show(below: nil)
            spin(0.2)
            panel.close()
            spin(0.2)
        }
        spin(0.5)
        let after = usage()
        let afterIdle = idle(3)
        print(String(format: "[check] panel x20: footprint %.1f -> %.1f MB; idle 3s wakeups %llu -> %llu, cpu %.3f -> %.3f s",
                     before.footprintMB, after.footprintMB, baseline.wakeups, afterIdle.wakeups,
                     baseline.cpu, afterIdle.cpu))
        check(after.footprintMB - before.footprintMB < 8, "面板开关 20 次后内存没有明显增长")
        check(afterIdle.wakeups <= baseline.wakeups + 15, "面板开关 20 次后空闲唤醒没有变多")
        check(afterIdle.cpu < 0.05, "面板开关 20 次后空闲 3 秒 CPU < 0.05 秒")

        // 设置窗口：关掉后释放
        SettingsWindowController.shared.show(tab: .general)
        spin(0.5)
        let settingsNumber = SettingsWindowController.shared.windowNumber
        weak var settingsWindow = NSApp.windows.first { $0.windowNumber == settingsNumber }
        check(settingsWindow != nil, "设置窗口能打开")
        settingsWindow?.performClose(nil)
        spin(0.5)
        check(SettingsWindowController.shared.windowNumber == nil && settingsWindow == nil, "设置窗口关闭后已释放")

        // 提示框：消失后释放
        HUD.shared.show("测试", symbol: "checkmark", duration: 0.2)
        spin(1.2)
        check(HUD.shared.windowNumber == nil, "提示框消失后已释放")

        // 清洁屏幕的黑屏窗口：大小要和屏幕一致（界面放进窗口后不能把窗口缩小）
        let frame = NSRect(x: 100, y: 100, width: 800, height: 500)
        let overlay = InputLocker.makeOverlayWindow(frame: frame, showsControls: true) {}
        overlay.orderFrontRegardless()
        spin(0.3)
        check(overlay.frame.size == frame.size, "清洁屏幕窗口大小正确（\(overlay.frame.size)）")
        overlay.orderOut(nil)
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
        if !failures.isEmpty {
            print("检查没有通过：\(failures.joined(separator: "；"))")
            fflush(stdout)
            exit(1)
        }
        NSApp.terminate(nil)
    }
}
#endif
