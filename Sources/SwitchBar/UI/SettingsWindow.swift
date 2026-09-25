import AppKit
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable, Hashable {
    case features
    case general
    case focus
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .features: return "功能与快捷键"
        case .general: return "通用"
        case .focus: return "勿扰模式"
        case .about: return "关于与隐私"
        }
    }

    var symbol: String {
        switch self {
        case .features: return "square.grid.2x2.fill"
        case .general: return "gearshape.fill"
        case .focus: return "moon.fill"
        case .about: return "lock.shield.fill"
        }
    }

    var color: Color {
        switch self {
        case .features: return .blue
        case .general: return .gray
        case .focus: return .indigo
        case .about: return .green
        }
    }
}

final class SettingsRouter: ObservableObject {
    static let shared = SettingsRouter()
    @Published var tab: SettingsTab = .features
}

final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    /// 窗口编号（调试版截图用）
    var windowNumber: Int? { window?.windowNumber }

    func show(tab: SettingsTab? = nil) {
        if let tab {
            SettingsRouter.shared.tab = tab
        }
        if window == nil {
            let view = SettingsView(store: SwitchStore.shared, prefs: Preferences.shared, router: SettingsRouter.shared)
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "SwitchBar 设置"
            window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        AppActivation.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
