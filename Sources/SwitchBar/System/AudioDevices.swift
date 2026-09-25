import CoreAudio
import Foundation

/// 列出声音输出 / 输入设备，并切换默认设备（公开的 CoreAudio 接口，不需要任何权限）
enum AudioDevices {
    struct Device: Equatable {
        let id: AudioDeviceID
        let name: String
    }

    private static let system = AudioObjectID(kAudioObjectSystemObject)

    static func all(output: Bool) -> [Device] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard hasStreams(id, output: output), let name = name(of: id) else { return nil }
            return Device(id: id, name: name)
        }
    }

    static func defaultDevice(output: Bool) -> AudioDeviceID? {
        var address = defaultAddress(output: output)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &id) == noErr, id != 0 else { return nil }
        return id
    }

    static func defaultDeviceName(output: Bool) -> String? {
        defaultDevice(output: output).flatMap(name(of:))
    }

    @discardableResult
    static func setDefault(_ id: AudioDeviceID, output: Bool) -> Bool {
        var device = id
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = defaultAddress(output: output)
        let ok = AudioObjectSetPropertyData(system, &address, 0, nil, size, &device) == noErr
        if ok && output {
            // 系统提示音也跟着切换
            var alertAddress = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
                                                          mScope: kAudioObjectPropertyScopeGlobal,
                                                          mElement: kAudioObjectPropertyElementMain)
            _ = AudioObjectSetPropertyData(system, &alertAddress, 0, nil, size, &device)
        }
        return ok
    }

    private static func defaultAddress(output: Bool) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: output ? kAudioHardwarePropertyDefaultOutputDevice : kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func hasStreams(_ id: AudioDeviceID, output: Bool) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                 mScope: output ? kAudioObjectPropertyScopeOutput : kAudioObjectPropertyScopeInput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }

    static func name(of id: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr, let name else { return nil }
        return name.takeRetainedValue() as String
    }
}
