import AppKit
import SwiftUI

/// 菜单栏下方弹出的面板（和系统「控制中心」一样没有小箭头，背景是液态玻璃）。
///
/// 用「不激活应用」的浮动面板实现：打开面板不会抢走当前应用的焦点，
/// 点面板外任何地方、按 Esc、切换桌面空间都会自动关闭。
/// 面板的窗口和界面只在打开时创建，关闭后立刻释放，平时不占内存、也不会在后台刷新。
final class MenuPanelController<Content: View> {
    private let makeContent: () -> Content
    private var panel: MenuPanelWindow?
    private var hosting: NSHostingController<Content>?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var spaceObserver: NSObjectProtocol?

    /// 状态栏按钮所在的窗口；点它时交给按钮自己处理开关，不要当成「点了外面」
    weak var statusButtonWindow: NSWindow?

    var isShown: Bool { panel?.isVisible ?? false }

    /// 窗口编号（调试版截图用）
    var windowNumber: Int? { panel?.windowNumber }

    init(content: @escaping () -> Content) {
        makeContent = content
    }

    /// 在状态栏按钮下方显示；按钮不可见（比如被刘海挡住）时显示在屏幕右上角
    func show(below button: NSStatusBarButton?) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let hosting: NSHostingController<Content>
        if let existing = self.hosting {
            hosting = existing
        } else {
            hosting = NSHostingController(rootView: makeContent())
            self.hosting = hosting
            panel.contentViewController = hosting
        }
        let size = contentSize(of: hosting)
        let anchor = buttonFrameOnScreen(button)
        let screen = anchor.flatMap { frame in NSScreen.screens.first { $0.frame.intersects(frame) } }
            ?? NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }

        let margin: CGFloat = 8
        var x = (anchor?.midX ?? visible.maxX) - size.width / 2
        x = min(max(x, visible.minX + margin), visible.maxX - size.width - margin)
        let top = min(anchor?.minY ?? visible.maxY, visible.maxY) - 6
        let y = max(top - size.height, visible.minY + margin)

        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            panel.animator().alphaValue = 1
        }
        installMonitors()
    }

    func close() {
        removeMonitors()
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
        // 面板里的按钮可能还在处理这次点击（比如点了「锁定屏幕」），等它处理完再释放界面
        DispatchQueue.main.async { [weak self] in
            guard let self, let current = self.panel, current === panel, !current.isVisible else { return }
            current.contentViewController = nil
            self.hosting = nil
            self.panel = nil
        }
    }

    /// 界面需要的大小。刚创建的 SwiftUI 界面还没排过版，直接问 AppKit（fittingSize）会得到 0×0，
    /// 所以直接让 SwiftUI 按内容算；万一还是算不出来，就先排一次版再量，最后兜底用固定大小，保证面板一定看得见。
    private func contentSize(of hosting: NSHostingController<Content>) -> NSSize {
        var size = hosting.sizeThatFits(in: NSSize(width: 10_000, height: 10_000))
        if !Self.isUsable(size) {
            hosting.view.layoutSubtreeIfNeeded()
            size = hosting.view.fittingSize
        }
        return Self.isUsable(size) ? size : NSSize(width: 356, height: 560)
    }

    private static func isUsable(_ size: NSSize) -> Bool {
        size.width >= 100 && size.height >= 100 && size.width < 5_000 && size.height < 5_000
    }

    private func makePanel() -> MenuPanelWindow {
        let panel = MenuPanelWindow(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                    backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        return panel
    }

    // MARK: - 关闭时机

    private func installMonitors() {
        removeMonitors()
        // 点其他应用的任何地方
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            self?.close()
        }
        // 点 SwitchBar 自己的其他窗口，或者按 Esc
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53 { // Esc
                    self.close()
                    return nil
                }
                return event
            }
            let window = event.window
            // 弹出的选项菜单是单独的窗口，点它不算点了外面
            let isMenu = window.map { NSStringFromClass(type(of: $0)).contains("Menu") } ?? false
            if window !== self.panel && window !== self.statusButtonWindow && !isMenu {
                self.close()
            }
            return event
        }
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.close()
        }
    }

    private func removeMonitors() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver) }
        globalMonitor = nil
        localMonitor = nil
        spaceObserver = nil
    }

    private func buttonFrameOnScreen(_ button: NSStatusBarButton?) -> NSRect? {
        guard let button, let window = button.window, window.isVisible else { return nil }
        let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
        // 按钮被刘海挡住或者不在任何屏幕上时，frame 可能是空的
        guard frame.width > 0, NSScreen.screens.contains(where: { $0.frame.intersects(frame) }) else { return nil }
        return frame
    }
}

/// 可以成为键盘焦点（接收 Esc），但不会激活 SwitchBar、不会抢走其他应用焦点的面板
final class MenuPanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
