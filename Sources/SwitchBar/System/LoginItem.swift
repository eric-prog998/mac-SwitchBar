import Foundation
import ServiceManagement

/// 登录时自动启动（系统的「登录项」，可以在 系统设置 › 通用 › 登录项 里看到和关闭）
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
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
