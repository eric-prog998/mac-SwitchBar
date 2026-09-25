import AppKit
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable, Hashable {
    case features
    case scenes
    case general
    case focus
    case security
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .features: return "功能与快捷键"
        case .scenes: return "场景与计时"
        case .general: return "通用"
        case .focus: return "勿扰模式"
        case .security: return "安全与权限"
        case .about: return "关于"
        }
    }

    var symbol: String {
        switch self {
        case .features: return "square.grid.2x2.fill"
        case .scenes: return "sparkles"
        case .general: return "gearshape.fill"
        case .focus: return "moon.fill"
        case .security: return "checkmark.shield.fill"
        case .about: return "info.circle.fill"
        }
    }

    var colors: [Color] {
        switch self {
        case .features: return FeatureColors.pair(0x5AA9FF, 0x2F6BFF)
        case .scenes: return FeatureColors.pair(0xFF9A4D, 0xFF3D77)
        case .general: return FeatureColors.neutral
        case .focus: return FeatureColors.pair(0x8C7BFF, 0x5B3BEA)
        case .security: return FeatureColors.pair(0x5BE39A, 0x1FAF62)
        case .about: return FeatureColors.pair(0x9AA5B8, 0x6B7486)
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
