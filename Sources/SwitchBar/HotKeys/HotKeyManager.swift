import AppKit
import Carbon.HIToolbox

/// 注册全局快捷键。用的是系统的 RegisterEventHotKey：
/// 只会收到「自己注册的那几个组合键」被按下的通知，看不到你打的其他任何字，也不需要任何权限。
final class HotKeyManager: ObservableObject {
    static let shared = HotKeyManager()

    /// 注册失败（通常是被系统或其他应用占用）的快捷键
    @Published private(set) var failed: Set<HotKeyTarget> = []

    /// 正在录制快捷键的目标（同一时间只允许录制一个）
    @Published private(set) var recording: HotKeyTarget?

    var onTrigger: ((HotKeyTarget) -> Void)?

    private static let signature = OSType(0x5357_4252) // "SWBR"
    private var registered: [EventHotKeyRef] = []
    private var targetByID: [UInt32: HotKeyTarget] = [:]
    private var featureKeys: [FeatureID: HotKey] = [:]
    private var panelKey: HotKey?
    private var suspended = false
    private var handlerInstalled = false
    private var recordingMonitor: Any?

    private init() {}

    func apply(features: [FeatureID: HotKey], panel: HotKey?) {
        featureKeys = features
        panelKey = panel
        if !suspended { registerAll() }
    }

    // MARK: - 录制

    /// 开始录制：暂停全部快捷键，避免按下的组合键直接触发功能
    func beginRecording(_ target: HotKeyTarget) {
        endRecording()
        recording = target
        suspended = true
        unregisterAll()
        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleRecording(event)
            return nil
        }
    }

    func endRecording() {
        guard recording != nil else { return }
        if let recordingMonitor {
            NSEvent.removeMonitor(recordingMonitor)
        }
        recordingMonitor = nil
        recording = nil
        suspended = false
        registerAll()
    }

    private func handleRecording(_ event: NSEvent) {
        guard let target = recording else { return }
        let keyCode = UInt32(event.keyCode)
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let prefs = Preferences.shared

        if keyCode == UInt32(kVK_Escape) && flags.isEmpty {
            endRecording()
            return
        }
        if (keyCode == UInt32(kVK_Delete) || keyCode == UInt32(kVK_ForwardDelete)) && flags.isEmpty {
            prefs.setHotKey(nil, for: target)
            endRecording()
            return
        }
        // 必须带 ⌘ / ⌥ / ⌃ 中的至少一个（F1–F20 除外），否则会和正常打字冲突
        guard !flags.subtracting(.shift).isEmpty || KeyNames.isFunctionKey(keyCode) else {
            NSSound.beep()
            return
        }
        prefs.setHotKey(HotKey(keyCode: keyCode, modifiers: HotKey.carbonModifiers(from: flags)), for: target)
        endRecording()
    }

    // MARK: - 注册

    fileprivate func handle(id: UInt32) {
        guard let target = targetByID[id] else { return }
        // 离开 Carbon 事件回调后再执行，避免在回调里弹窗或跑脚本
        DispatchQueue.main.async { [weak self] in
            self?.onTrigger?(target)
        }
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetEventDispatcherTarget(), hotKeyEventHandler, 1, &eventType, nil, nil)
        handlerInstalled = status == noErr
    }

    private func registerAll() {
        installHandlerIfNeeded()
        unregisterAll()

        var entries: [(HotKeyTarget, HotKey)] = []
        if let panelKey { entries.append((.panel, panelKey)) }
        for feature in FeatureID.allCases {
            if let key = featureKeys[feature] { entries.append((.feature(feature), key)) }
        }

        var failures = Set<HotKeyTarget>()
        for (index, entry) in entries.enumerated() {
            let id = UInt32(index + 1)
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
            let status = RegisterEventHotKey(entry.1.keyCode, entry.1.modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &ref)
            if status == noErr, let ref {
                registered.append(ref)
                targetByID[id] = entry.0
            } else {
                failures.insert(entry.0)
            }
        }
        if failures != failed { failed = failures }
    }

    private func unregisterAll() {
        for ref in registered {
            UnregisterEventHotKey(ref)
        }
        registered.removeAll()
        targetByID.removeAll()
    }
}

private func hotKeyEventHandler(_ callRef: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                   nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
    guard status == noErr else { return status }
    HotKeyManager.shared.handle(id: hotKeyID.id)
    return noErr
}
