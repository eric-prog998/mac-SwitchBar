import Foundation
import ServiceManagement

/// 登录时自动启动（系统的「登录项」，可以在 系统设置 › 通用 › 登录项 里看到和关闭）
enum LoginItem {
    /// 已经登记为登录项（包括「已登记，但还要你在系统设置里允许」）
    static var isEnabled: Bool {
        let status = SMAppService.mainApp.status
        return status == .enabled || status == .requiresApproval
    }

    /// 是否在「应用程序」文件夹里（从下载文件夹直接运行时，系统可能把应用放在临时位置）
    static var isInApplicationsFolder: Bool {
        let path = Bundle.main.bundlePath
        return path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/")
    }

    static var needsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    /// 返回给你看的错误信息，nil 表示成功
    static func set(_ enabled: Bool) -> String? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            NSLog("SwitchBar: 设置登录项失败：\(error)")
            return (enabled ? "开启失败：" : "关闭失败：") + error.localizedDescription
        }
    }
}
