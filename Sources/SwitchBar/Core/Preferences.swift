import Combine
import Foundation

/// 用户设置，全部保存在本机 UserDefaults（~/Library/Preferences/local.switchbar.plist）
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private enum Key {
        static let order = "featureOrder"
        static let hidden = "hiddenFeatures"
        static let hotKeys = "hotKeys"
        static let panelHotKey = "panelHotKey"
        static let extraHotKeys = "extraHotKeys"
        static let sceneMembers = "sceneMembers"
        static let timerMinutes = "timerMinutes"
        static let timerStartsFocus = "timerStartsFocus"
        static let timerSound = "timerSound"
        static let keepAwakeMinutes = "keepAwakeMinutes"
        static let showHUD = "showHUD"
        static let dndOn = "dndOnShortcut"
        static let dndOff = "dndOffShortcut"
        static let dndActive = "dndActive"
        static let bluetoothAddress = "bluetoothAddress"
        static let bluetoothName = "bluetoothName"
        static let micVolumes = "savedMicVolumes"
        /// 2.0 删掉「静音」开关后不再使用
        static let obsoleteOutputVolumes = "savedOutputVolumes"
    }

    private let defaults = UserDefaults.standard

    /// 任何快捷键改变后发出（值已经更新）
    let hotKeysChanged = PassthroughSubject<Void, Never>()

    /// 所有功能的排列顺序（包括隐藏的）
    @Published var featureOrder: [FeatureID] {
        didSet { defaults.set(featureOrder.map(\.rawValue), forKey: Key.order) }
    }

    /// 不在面板里显示的功能
    @Published var hiddenFeatures: Set<FeatureID> {
        didSet { defaults.set(hiddenFeatures.map(\.rawValue).sorted(), forKey: Key.hidden) }
    }

    /// 各个开关的快捷键
    @Published private(set) var hotKeys: [FeatureID: HotKey] {
        didSet {
            saveHotKeys()
            hotKeysChanged.send()
        }
    }

    /// 打开 / 关闭面板的快捷键（默认 ⌃⌥⌘S，可以清除）
    @Published private(set) var panelHotKey: HotKey? {
        didSet {
            // 包一层再保存，这样「清除了」和「从没设置过」可以区分开
            if let data = try? JSONEncoder().encode(StoredHotKey(key: panelHotKey)) {
                defaults.set(data, forKey: Key.panelHotKey)
            }
            hotKeysChanged.send()
        }
    }

    /// 场景、专注计时的快捷键
    @Published private(set) var extraHotKeys: [String: HotKey] {
        didSet {
            if let data = try? JSONEncoder().encode(extraHotKeys) {
                defaults.set(data, forKey: Key.extraHotKeys)
            }
            hotKeysChanged.send()
        }
    }

    /// 每个场景包含哪些开关
    @Published var sceneMembers: [SceneID: [FeatureID]] {
        didSet {
            let raw = Dictionary(uniqueKeysWithValues: sceneMembers.map { ($0.key.rawValue, $0.value.map(\.rawValue)) })
            defaults.set(raw, forKey: Key.sceneMembers)
        }
    }

    /// 专注计时默认多少分钟
    @Published var timerMinutes: Int {
        didSet { defaults.set(timerMinutes, forKey: Key.timerMinutes) }
    }

    /// 开始计时时自动开启「专注」场景，结束时恢复
    @Published var timerStartsFocus: Bool {
        didSet { defaults.set(timerStartsFocus, forKey: Key.timerStartsFocus) }
    }

    /// 计时结束时播放提示音
    @Published var timerSound: Bool {
        didSet { defaults.set(timerSound, forKey: Key.timerSound) }
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
        if let data = d.data(forKey: Key.extraHotKeys),
           let stored = try? JSONDecoder().decode([String: HotKey].self, from: data) {
            extraHotKeys = stored
        } else {
            extraHotKeys = [:]
        }
        sceneMembers = Preferences.loadSceneMembers(from: d)
        timerMinutes = d.object(forKey: Key.timerMinutes) as? Int ?? 25
        timerStartsFocus = d.object(forKey: Key.timerStartsFocus) as? Bool ?? true
        timerSound = d.object(forKey: Key.timerSound) as? Bool ?? true
        keepAwakeMinutes = d.object(forKey: Key.keepAwakeMinutes) as? Int ?? 0
        showHUD = d.object(forKey: Key.showHUD) as? Bool ?? true
        dndOnShortcut = d.string(forKey: Key.dndOn) ?? "开启勿扰"
        dndOffShortcut = d.string(forKey: Key.dndOff) ?? "关闭勿扰"
        bluetoothAddress = d.string(forKey: Key.bluetoothAddress) ?? ""
        bluetoothName = d.string(forKey: Key.bluetoothName) ?? ""
        // 已删除的功能留下的设置（旧版本里被删掉的开关、场景的顺序和快捷键在读取时会自动忽略）
        d.removeObject(forKey: Key.obsoleteOutputVolumes)
    }

    // MARK: - 面板

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

    // MARK: - 场景

    func members(of scene: SceneID) -> [FeatureID] {
        sceneMembers[scene] ?? scene.defaultMembers
    }

    func setMember(_ feature: FeatureID, of scene: SceneID, included: Bool) {
        var list = members(of: scene).filter { $0 != feature }
        if included {
            // 按功能列表的顺序保存，切换时也按这个顺序执行
            list.append(feature)
            list.sort { (FeatureID.allCases.firstIndex(of: $0) ?? 0) < (FeatureID.allCases.firstIndex(of: $1) ?? 0) }
        }
        sceneMembers[scene] = list
    }

    // MARK: - 快捷键

    /// 所有已设置的快捷键
    var allHotKeys: [HotKeyTarget: HotKey] {
        var result: [HotKeyTarget: HotKey] = [:]
        if let panelHotKey { result[.panel] = panelHotKey }
        for (feature, key) in hotKeys { result[.feature(feature)] = key }
        for target in HotKeyTarget.extraTargets {
            if let key = extraHotKeys[target.storageKey] { result[target] = key }
        }
        return result
    }

    func hotKey(for target: HotKeyTarget) -> HotKey? {
        switch target {
        case .panel: return panelHotKey
        case .feature(let feature): return hotKeys[feature]
        case .scene, .timer: return extraHotKeys[target.storageKey]
        }
    }

    /// 设置快捷键；同一组合键如果已被别处使用，会从那里移除
    func setHotKey(_ key: HotKey?, for target: HotKeyTarget) {
        var all = allHotKeys
        if let key {
            for (other, existing) in all where existing == key && other != target {
                all[other] = nil
            }
        }
        all[target] = key
        store(all)
    }

    /// 一键设置推荐快捷键：只给「还没有快捷键」的设置，不会覆盖你自己录制的。返回新设置的数量
    @discardableResult
    func applyRecommendedHotKeys() -> Int {
        var all = allHotKeys
        var used = Set(all.values.map { "\($0.keyCode)-\($0.modifiers)" })
        var count = 0
        for target in HotKeyTarget.allTargets where all[target] == nil {
            guard let key = target.recommendedHotKey else { continue }
            let signature = "\(key.keyCode)-\(key.modifiers)"
            guard !used.contains(signature) else { continue }
            all[target] = key
            used.insert(signature)
            count += 1
        }
        store(all)
        return count
    }

    private func store(_ all: [HotKeyTarget: HotKey]) {
        var features: [FeatureID: HotKey] = [:]
        var extra: [String: HotKey] = [:]
        var panel: HotKey?
        for (target, key) in all {
            switch target {
            case .panel: panel = key
            case .feature(let feature): features[feature] = key
            case .scene, .timer: extra[target.storageKey] = key
            }
        }
        if features != hotKeys { hotKeys = features }
        if panel != panelHotKey { panelHotKey = panel }
        if extra != extraHotKeys { extraHotKeys = extra }
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

    private static func loadSceneMembers(from defaults: UserDefaults) -> [SceneID: [FeatureID]] {
        guard let raw = defaults.dictionary(forKey: Key.sceneMembers) as? [String: [String]] else { return [:] }
        var result: [SceneID: [FeatureID]] = [:]
        for (name, members) in raw {
            if let scene = SceneID(rawValue: name) {
                result[scene] = members.compactMap(FeatureID.init(rawValue:))
            }
        }
        return result
    }
}
