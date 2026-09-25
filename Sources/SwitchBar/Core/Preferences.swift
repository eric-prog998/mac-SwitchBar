import Foundation

/// 用户设置，全部保存在本机 UserDefaults（~/Library/Preferences/local.switchbar.plist）
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private enum Key {
        static let order = "featureOrder"
        static let hidden = "hiddenFeatures"
        static let hotKeys = "hotKeys"
        static let panelHotKey = "panelHotKey"
        static let keepAwakeMinutes = "keepAwakeMinutes"
        static let showHUD = "showHUD"
        static let dndOn = "dndOnShortcut"
        static let dndOff = "dndOffShortcut"
        static let dndActive = "dndActive"
        static let bluetoothAddress = "bluetoothAddress"
        static let bluetoothName = "bluetoothName"
        static let micVolumes = "savedMicVolumes"
    }

    private let defaults = UserDefaults.standard

    /// 所有功能的排列顺序（包括隐藏的）
    @Published var featureOrder: [FeatureID] {
        didSet { defaults.set(featureOrder.map(\.rawValue), forKey: Key.order) }
    }

    /// 不在面板里显示的功能
    @Published var hiddenFeatures: Set<FeatureID> {
        didSet { defaults.set(hiddenFeatures.map(\.rawValue).sorted(), forKey: Key.hidden) }
    }

    @Published var hotKeys: [FeatureID: HotKey] {
        didSet { saveHotKeys() }
    }

    /// 打开 / 关闭面板的快捷键（默认 ⌃⌥⌘S，可以清除）
    @Published var panelHotKey: HotKey? {
        didSet {
            // 包一层再保存，这样「清除了」和「从没设置过」可以区分开
            if let data = try? JSONEncoder().encode(StoredHotKey(key: panelHotKey)) {
                defaults.set(data, forKey: Key.panelHotKey)
            }
        }
    }

    /// 点「保持亮屏」时默认保持多久，0 表示一直保持
    @Published var keepAwakeMinutes: Int {
        didSet { defaults.set(keepAwakeMinutes, forKey: Key.keepAwakeMinutes) }
    }

    /// 用快捷键操作时是否在屏幕上显示提示
    @Published var showHUD: Bool {
        didSet { defaults.set(showHUD, forKey: Key.showHUD) }
    }

    /// 用于开启 / 关闭勿扰模式的「快捷指令」名称
    @Published var dndOnShortcut: String {
        didSet { defaults.set(dndOnShortcut, forKey: Key.dndOn) }
    }

    @Published var dndOffShortcut: String {
        didSet { defaults.set(dndOffShortcut, forKey: Key.dndOff) }
    }

    /// 选中的蓝牙耳机
    @Published var bluetoothAddress: String {
        didSet { defaults.set(bluetoothAddress, forKey: Key.bluetoothAddress) }
    }

    @Published var bluetoothName: String {
        didSet { defaults.set(bluetoothName, forKey: Key.bluetoothName) }
    }

    /// 无法读取系统勿扰状态时，用这个记录上一次的操作结果
    var dndActive: Bool {
        get { defaults.bool(forKey: Key.dndActive) }
        set { defaults.set(newValue, forKey: Key.dndActive) }
    }

    /// 麦克风不支持「静音」属性时，静音前记下的音量，用于恢复
    var savedMicVolumes: [Float] {
        get { (defaults.array(forKey: Key.micVolumes) as? [NSNumber])?.map(\.floatValue) ?? [] }
        set { defaults.set(newValue, forKey: Key.micVolumes) }
    }

    var visibleFeatures: [FeatureID] {
        featureOrder.filter { !hiddenFeatures.contains($0) }
    }

    private init() {
        let d = UserDefaults.standard
        let storedOrder = (d.stringArray(forKey: Key.order) ?? []).compactMap(FeatureID.init(rawValue:))
        // 新版本增加的功能追加到末尾
        featureOrder = storedOrder + FeatureID.allCases.filter { !storedOrder.contains($0) }
        hiddenFeatures = Set((d.stringArray(forKey: Key.hidden) ?? []).compactMap(FeatureID.init(rawValue:)))
        hotKeys = Preferences.loadHotKeys(from: d)
        if let data = d.data(forKey: Key.panelHotKey), let stored = try? JSONDecoder().decode(StoredHotKey.self, from: data) {
            panelHotKey = stored.key
        } else {
            panelHotKey = HotKey.defaultPanel
        }
        keepAwakeMinutes = d.object(forKey: Key.keepAwakeMinutes) as? Int ?? 0
        showHUD = d.object(forKey: Key.showHUD) as? Bool ?? true
        dndOnShortcut = d.string(forKey: Key.dndOn) ?? "开启勿扰"
        dndOffShortcut = d.string(forKey: Key.dndOff) ?? "关闭勿扰"
        bluetoothAddress = d.string(forKey: Key.bluetoothAddress) ?? ""
        bluetoothName = d.string(forKey: Key.bluetoothName) ?? ""
    }

    func isVisible(_ feature: FeatureID) -> Bool {
        !hiddenFeatures.contains(feature)
    }

    func setVisible(_ visible: Bool, _ feature: FeatureID) {
        if visible {
            hiddenFeatures.remove(feature)
        } else {
            hiddenFeatures.insert(feature)
        }
    }

    func hotKey(for target: HotKeyTarget) -> HotKey? {
        switch target {
        case .panel: return panelHotKey
        case .feature(let feature): return hotKeys[feature]
        }
    }

    /// 设置快捷键；同一组合键如果已被别处使用，会从那里移除
    func setHotKey(_ key: HotKey?, for target: HotKeyTarget) {
        var keys = hotKeys
        if let key {
            for (other, existing) in keys where existing == key && target != .feature(other) {
                keys[other] = nil
            }
            if target != .panel && panelHotKey == key {
                panelHotKey = nil
            }
        }
        switch target {
        case .panel:
            panelHotKey = key
        case .feature(let feature):
            keys[feature] = key
        }
        if keys != hotKeys { hotKeys = keys }
    }

    private struct StoredHotKey: Codable {
        var key: HotKey?
    }

    private func saveHotKeys() {
        let raw = Dictionary(uniqueKeysWithValues: hotKeys.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(raw) {
            defaults.set(data, forKey: Key.hotKeys)
        }
    }

    private static func loadHotKeys(from defaults: UserDefaults) -> [FeatureID: HotKey] {
        guard let data = defaults.data(forKey: Key.hotKeys),
              let raw = try? JSONDecoder().decode([String: HotKey].self, from: data) else { return [:] }
        var result: [FeatureID: HotKey] = [:]
        for (name, key) in raw {
            if let feature = FeatureID(rawValue: name) { result[feature] = key }
        }
        return result
    }
}
