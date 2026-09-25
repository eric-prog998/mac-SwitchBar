import AppKit

/// 通过系统自带的「快捷指令」开关勿扰模式。
/// macOS 没有公开的接口可以切换专注模式，这是不用私有接口、也不用额外权限的做法。
enum Shortcuts {
    private static let tool = "/usr/bin/shortcuts"

    /// 在后台运行快捷指令，完成后在主线程回调是否成功
    static func run(_ name: String, completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = Shell.run(tool, ["run", name]).status == 0
            DispatchQueue.main.async { completion(ok) }
        }
    }

    /// 列出本机所有快捷指令的名称
    static func list() -> [String] {
        Shell.run(tool, ["list"]).output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    static func openApp() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app"))
    }
}

/// 读取系统记录的「手动开启的专注模式」。
/// 读不到（文件受保护或格式变化）时返回 nil，调用方会退回到自己记录的状态。
enum FocusStatus {
    static func readActive() -> Bool? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/DoNotDisturb/DB/Assertions.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["data"] as? [[String: Any]] else { return nil }
        for item in items {
            if let records = item["storeAssertionRecords"] as? [Any], !records.isEmpty {
                return true
            }
        }
        return false
    }
}
