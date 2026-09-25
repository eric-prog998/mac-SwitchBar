import AppKit
import SwiftUI

/// 菜单栏图标：左键打开开关面板，右键弹出「设置 / 退出」
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let store: SwitchStore

    init(store: SwitchStore) {
        self.store = store
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "switch.2", accessibilityDescription: "SwitchBar")
            image?.isTemplate = true
            button.image = image
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let hosting = NSHostingController(rootView: PanelView(store: store, prefs: store.prefs))
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        popover.behavior = .transient

        store.closePanel = { [weak self] in
            self?.closePopover()
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        if popover.isShown {
            closePopover()
            return
        }
        guard let button = statusItem.button else { return }
        store.refresh()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func closePopover() {
        if popover.isShown {
            popover.performClose(nil)
        }
    }

    private func showContextMenu() {
        closePopover()
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
}
