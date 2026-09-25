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
        case .scenes: return "square.stack.3d.up.fill"
        case .general: return "gearshape.fill"
        case .focus: return "moon.fill"
        case .security: return "checkmark.shield.fill"
        case .about: return "info.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .features: return .blue
        case .scenes: return .orange
        case .general: return .gray
        case .focus: return .indigo
        case .security: return .green
        case .about: return .gray
        }
    }
}

final class SettingsRouter: ObservableObject {
    static let shared = SettingsRouter()
    @Published var tab: SettingsTab = .features
}

/// 设置窗口只在打开时创建，关掉后立刻释放（窗口里的界面不会在后台继续刷新）
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    /// 打开设置前正在用的应用；关掉设置后把焦点还给它（菜单栏应用关掉最后一个窗口后，系统不会自动切回去）
    private var previousApp: NSRunningApplication?

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
            window.delegate = self
            window.center()
            self.window = window
        }
        if !NSApp.isActive {
            let frontmost = NSWorkspace.shared.frontmostApplication
            previousApp = frontmost == NSRunningApplication.current ? nil : frontmost
        }
        if window?.isMiniaturized == true {
            window?.deminiaturize(nil)
        }
        AppActivation.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow, closing === window else { return }
        // 等窗口关完再释放；如果这期间又被打开了，就留着
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window === closing, !closing.isVisible else { return }
            closing.delegate = nil
            self.window = nil
            // 你还停在 SwitchBar 上（没有自己点去别的应用）时，把焦点还给之前的应用
            if NSApp.isActive, let previous = self.previousApp {
                AppActivation.reactivate(previous)
            }
            self.previousApp = nil
        }
    }
}
