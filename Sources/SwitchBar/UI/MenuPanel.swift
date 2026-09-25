import AppKit
import SwiftUI

/// 菜单栏下方弹出的面板（和系统「控制中心」一样没有小箭头，背景是液态玻璃）。
///
/// 用「不激活应用」的浮动面板实现：打开面板不会抢走当前应用的焦点，
/// 点面板外任何地方、按 Esc、切换桌面空间都会自动关闭。
/// 面板的窗口和界面只在打开时创建，关闭后立刻释放，平时不占内存、也不会在后台刷新。
final class MenuPanelController {
    private let makeContent: () -> NSView
    private var panel: MenuPanelWindow?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var spaceObserver: NSObjectProtocol?

    /// 状态栏按钮所在的窗口；点它时交给按钮自己处理开关，不要当成「点了外面」
    weak var statusButtonWindow: NSWindow?

    var isShown: Bool { panel?.isVisible ?? false }

    /// 窗口编号（调试版截图用）
    var windowNumber: Int? { panel?.windowNumber }

    init<Content: View>(content: @escaping () -> Content) {
        makeContent = { NSHostingView(rootView: content()) }
    }

    /// 在状态栏按钮下方显示；按钮不可见（比如被刘海挡住）时显示在屏幕右上角
    func show(below button: NSStatusBarButton?) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        // 顺序很重要：先在窗口外量好界面需要的大小，再放进窗口，最后设置窗口大小。
        // 放进空窗口后再量会得到 0×0；先设大小再放界面，窗口又会被缩回 0×0（面板就看不见了）。
        let content = panel.contentView ?? makeContent()
        var size = content.fittingSize
        #if DEBUG
        print("[panel] fitting before attach=\(size) intrinsic=\(content.intrinsicContentSize) frame=\(content.frame)")
        #endif
        if panel.contentView !== content {
            panel.contentView = content
        }
        #if DEBUG
        print("[panel] fitting after attach=\(content.fittingSize) window=\(panel.frame)")
        #endif
        if size.width < 1 || size.height < 1 {
            content.layoutSubtreeIfNeeded()
            size = content.fittingSize
        }
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
        #if DEBUG
        print("[panel] size=\(size) window after setFrame=\(panel.frame)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            print("[panel] window 0.5s later=\(panel.frame) content=\(content.frame) minSize=\(panel.contentMinSize) maxSize=\(panel.contentMaxSize)")
        }
        #endif
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
            current.contentView = nil
            self.panel = nil
        }
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
