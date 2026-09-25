import Carbon.HIToolbox
import Foundation

/// 注册全局快捷键。用的是系统的 RegisterEventHotKey：
/// 只会收到「自己注册的那几个组合键」被按下的通知，看不到你打的其他任何字，也不需要任何权限。
final class HotKeyManager: ObservableObject {
    static let shared = HotKeyManager()

    /// 注册失败（通常是被其他应用占用）的功能
    @Published private(set) var failed: Set<FeatureID> = []

    var onTrigger: ((FeatureID) -> Void)?

    private static let signature = OSType(0x5357_4252) // "SWBR"
    private var registered: [EventHotKeyRef] = []
    private var featureByID: [UInt32: FeatureID] = [:]
    private var keys: [FeatureID: HotKey] = [:]
    private var suspended = false
    private var handlerInstalled = false

    private init() {}

    func apply(_ keys: [FeatureID: HotKey]) {
        self.keys = keys
        if !suspended { registerAll() }
    }

    /// 录制新快捷键时暂停全部快捷键，避免按下的组合键直接触发功能
    func suspend() {
        suspended = true
        unregisterAll()
    }

    func resume() {
        suspended = false
        registerAll()
    }

    fileprivate func handle(id: UInt32) {
        guard let feature = featureByID[id] else { return }
        // 离开 Carbon 事件回调后再执行，避免在回调里弹窗或跑脚本
        DispatchQueue.main.async { [weak self] in
            self?.onTrigger?(feature)
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
        var failures = Set<FeatureID>()
        for (index, feature) in FeatureID.allCases.enumerated() {
            guard let key = keys[feature] else { continue }
            let id = UInt32(index + 1)
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
            let status = RegisterEventHotKey(key.keyCode, key.modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &ref)
            if status == noErr, let ref {
                registered.append(ref)
                featureByID[id] = feature
            } else {
                failures.insert(feature)
            }
        }
        if failures != failed { failed = failures }
    }

    private func unregisterAll() {
        for ref in registered {
            UnregisterEventHotKey(ref)
        }
        registered.removeAll()
        featureByID.removeAll()
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
