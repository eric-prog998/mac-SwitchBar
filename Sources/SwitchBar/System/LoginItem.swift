import Foundation
import ServiceManagement

/// 登录时自动启动（系统的「登录项」，可以在 系统设置 › 通用 › 登录项 里看到和关闭）
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// 是否在「应用程序」文件夹里（从下载文件夹直接运行时，系统可能把应用放在临时位置）
    static var isInApplicationsFolder: Bool {
        let path = Bundle.main.bundlePath
        return path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/")
    }

    static var needsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    static func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("SwitchBar: 设置登录项失败：\(error)")
        }
    }
}
