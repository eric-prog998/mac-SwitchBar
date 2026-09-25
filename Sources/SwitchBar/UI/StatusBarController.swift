import AppKit
import SwiftUI

/// 菜单栏图标：左键打开开关面板，右键弹出「设置 / 退出」
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let panel: MenuPanelController
    private let store: SwitchStore

    init(store: SwitchStore) {
        self.store = store
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // 记住位置：按住 ⌘ 拖动过图标后，下次启动仍在原处（有刘海的屏幕上可以把它挪到不被挡住的地方）
        statusItem.autosaveName = "SwitchBarStatusItem"
        panel = MenuPanelController(rootView: PanelView(store: store, prefs: store.prefs))
        super.init()

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "switch.2", accessibilityDescription: "SwitchBar")
            image?.isTemplate = true
            button.image = image
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            panel.statusButtonWindow = button.window
        }

        store.closePanel = { [weak self] in
            self?.panel.close()
        }
    }

    /// 打开或关闭面板（点图标、按快捷键都走这里）
    func togglePanel() {
        if panel.isShown {
            panel.close()
            return
        }
        store.refresh()
        panel.statusButtonWindow = statusItem.button?.window
        panel.show(below: statusItem.button)
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showContextMenu()
        } else {
            togglePanel()
        }
    }

    private func showContextMenu() {
        panel.close()
        guard let button = statusItem.button else { return }
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem("设置…") { [weak self] in
            self?.store.openSettings()
        })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("退出 SwitchBar") {
            NSApp.terminate(nil)
        })
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 5), in: button)
    }
}

/// 用闭包响应点击的菜单项
final class ClosureMenuItem: NSMenuItem {
    private var handler: (() -> Void)?

    /// handler 为 nil 时是不可点击的说明文字
    convenience init(_ title: String, checked: Bool = false, handler: (() -> Void)?) {
        self.init(title: title, action: handler == nil ? nil : #selector(ClosureMenuItem.fire), keyEquivalent: "")
        self.handler = handler
        self.target = self
        self.state = checked ? .on : .off
        self.isEnabled = handler != nil
    }

    @objc private func fire() {
        handler?()
    }

    /// 菜单里的小标题
    static func header(_ title: String) -> NSMenuItem {
        if #available(macOS 14.0, *) {
            return NSMenuItem.sectionHeader(title: title)
        }
        return ClosureMenuItem(title, handler: nil)
    }
}
