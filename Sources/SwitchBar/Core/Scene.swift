import Foundation

/// 场景：一次切换一组开关。rawValue 会存进偏好设置，不要随意改名。
enum SceneID: String, CaseIterable, Codable, Identifiable {
    case present
    case focus
    case night

    var id: String { rawValue }

    var title: String {
        switch self {
        case .present: return "演示"
        case .focus: return "专注"
        case .night: return "夜间"
        }
    }

    var emoji: String {
        switch self {
        case .present: return "🎬"
        case .focus: return "🎧"
        case .night: return "🌙"
        }
    }

    var detail: String {
        switch self {
        case .present: return "开会、投屏、录屏前一键收拾好桌面"
        case .focus: return "屏蔽打扰，安心做事"
        case .night: return "晚上用电脑更护眼"
        }
    }

    /// 默认包含的开关（可以在设置里修改）
    var defaultMembers: [FeatureID] {
        switch self {
        case .present: return [.hideDesktop, .doNotDisturb, .keepAwake, .autoHideDock]
        case .focus: return [.doNotDisturb, .autoHideMenuBar, .autoHideDock]
        case .night: return [.darkMode, .nightShift]
        }
    }
}
