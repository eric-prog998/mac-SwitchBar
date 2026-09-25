import AppKit
import CoreGraphics

/// 切换显示器分辨率（公开的 CoreGraphics 接口），支持多台外接显示器
enum Displays {
    struct ModeOption {
        let mode: CGDisplayMode
        let title: String
        let isCurrent: Bool
    }

    struct Display {
        let id: CGDirectDisplayID
        let name: String
        /// HiDPI（清晰）模式；如果显示器不支持 HiDPI，就是全部模式
        let primaryModes: [ModeOption]
        /// 支持 HiDPI 的显示器上，其余的低分辨率模式放进「更多」子菜单
        let otherModes: [ModeOption]
    }

    static func all() -> [Display] {
        activeDisplayIDs().map { id in
            let current = CGDisplayCopyDisplayMode(id)
            let options = modeOptions(for: id, current: current)
            let hiDPI = options.filter { isHiDPI($0.mode) }
            if hiDPI.isEmpty {
                return Display(id: id, name: name(for: id), primaryModes: labelled(options), otherModes: [])
            }
            return Display(id: id, name: name(for: id), primaryModes: labelled(hiDPI),
                           otherModes: options.filter { !isHiDPI($0.mode) })
        }
    }

    /// 永久切换到指定模式（和在系统设置里切换效果相同）
    static func apply(_ mode: CGDisplayMode, to display: CGDirectDisplayID) -> Bool {
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return false }
        guard CGConfigureDisplayWithDisplayMode(config, display, mode, nil) == .success else {
            CGCancelDisplayConfiguration(config)
            return false
        }
        return CGCompleteDisplayConfiguration(config, .permanently) == .success
    }

    // MARK: - 私有

    private static func activeDisplayIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        // 镜像显示时只保留主屏
        return ids.prefix(Int(count)).filter { CGDisplayMirrorsDisplay($0) == 0 }
    }

    private static func name(for id: CGDirectDisplayID) -> String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        let screen = NSScreen.screens.first { ($0.deviceDescription[key] as? NSNumber)?.uint32Value == id }
        if let screen { return screen.localizedName }
        return CGDisplayIsBuiltin(id) != 0 ? "内建显示器" : "显示器 \(id)"
    }

    private static func isHiDPI(_ mode: CGDisplayMode) -> Bool {
        mode.pixelWidth > mode.width
    }

    private static func modeOptions(for id: CGDirectDisplayID, current: CGDisplayMode?) -> [ModeOption] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
        guard let modes = CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode] else { return [] }

        // 同一个「看起来的分辨率」可能有多种刷新率，只保留一个：
        // 优先当前正在用的模式，其次和当前刷新率相同的，再其次刷新率最高的
        var best: [String: CGDisplayMode] = [:]
        for mode in modes where mode.isUsableForDesktopGUI() {
            let key = "\(mode.width)x\(mode.height)-\(isHiDPI(mode))"
            if let existing = best[key], score(existing, current) >= score(mode, current) { continue }
            best[key] = mode
        }

        let sorted = best.values.sorted { a, b in
            if a.width != b.width { return a.width > b.width }
            return a.height > b.height
        }
        return sorted.map { mode in
            ModeOption(mode: mode, title: title(for: mode), isCurrent: current?.ioDisplayModeID == mode.ioDisplayModeID)
        }
    }

    /// 像「系统设置」一样，在最大和最小的选项后面注明「更多空间」「更大字体」
    private static func labelled(_ options: [ModeOption]) -> [ModeOption] {
        guard options.count >= 3 else { return options }
        return options.enumerated().map { index, option in
            guard !option.title.contains("默认") else { return option }
            if index == 0 {
                return ModeOption(mode: option.mode, title: option.title + "（更多空间）", isCurrent: option.isCurrent)
            }
            if index == options.count - 1 {
                return ModeOption(mode: option.mode, title: option.title + "（更大字体）", isCurrent: option.isCurrent)
            }
            return option
        }
    }

    private static func score(_ mode: CGDisplayMode, _ current: CGDisplayMode?) -> Double {
        var score = mode.refreshRate
        if let current {
            if mode.ioDisplayModeID == current.ioDisplayModeID { score += 100_000 }
            if abs(mode.refreshRate - current.refreshRate) < 0.5 { score += 10_000 }
        }
        return score
    }

    private static func title(for mode: CGDisplayMode) -> String {
        var title = "\(mode.width) × \(mode.height)"
        if mode.ioFlags & 0x0000_0004 != 0 { // kDisplayModeDefaultFlag
            title += "（默认）"
        }
        return title
    }
}
