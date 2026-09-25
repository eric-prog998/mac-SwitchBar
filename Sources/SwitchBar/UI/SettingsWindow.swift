import AppKit
import SwiftUI

enum SettingsTab: Hashable {
    case features
    case general
    case focus
    case about
}

final class SettingsRouter: ObservableObject {
    static let shared = SettingsRouter()
    @Published var tab: SettingsTab = .features
}

final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show(tab: SettingsTab? = nil) {
        if let tab {
            SettingsRouter.shared.tab = tab
        }
        if window == nil {
            let view = SettingsView(store: SwitchStore.shared, prefs: Preferences.shared, router: SettingsRouter.shared)
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "SwitchBar 设置"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
