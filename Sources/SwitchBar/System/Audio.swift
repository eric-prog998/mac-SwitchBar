import CoreAudio
import Foundation

/// 静音麦克风 / 系统声音：直接设置当前默认输入或输出设备的「静音」属性（公开的 CoreAudio 接口）。
/// 有些设备不支持静音属性，就退而求其次把音量调到 0，取消静音时再恢复原音量。
/// 只改设备属性、不采集任何声音，所以不需要「麦克风」权限。
struct AudioMute {
    private let scope: AudioObjectPropertyScope
    private let defaultDeviceSelector: AudioObjectPropertySelector
    private let savedVolumes: ReferenceWritableKeyPath<Preferences, [Float]>
    private let mainElement = kAudioObjectPropertyElementMain

    /// 麦克风（默认输入设备）
    static let input = AudioMute(scope: kAudioObjectPropertyScopeInput,
                                 defaultDeviceSelector: kAudioHardwarePropertyDefaultInputDevice,
                                 savedVolumes: \.savedMicVolumes)

    /// 系统声音（默认输出设备）
    static let output = AudioMute(scope: kAudioObjectPropertyScopeOutput,
                                  defaultDeviceSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                  savedVolumes: \.savedOutputVolumes)

    func defaultDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: defaultDeviceSelector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: mainElement
        )
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        guard status == noErr, deviceID != 0 else { return nil }
        return deviceID
    }

    var isAvailable: Bool { defaultDevice() != nil }

    var isMuted: Bool {
        guard let device = defaultDevice() else { return false }
        if hasSettableMute(device) {
            return readMute(device) ?? false
        }
        let volumes = volumeElements(device).compactMap { readVolume(device, element: $0) }
        return !volumes.isEmpty && volumes.allSatisfy { $0 <= 0.001 }
    }

    /// 返回是否成功
    func setMuted(_ muted: Bool) -> Bool {
        guard let device = defaultDevice() else { return false }
        let prefs = Preferences.shared

        if hasSettableMute(device) {
            let ok = writeMute(device, muted)
            // 如果之前是用「音量调到 0」的方式静音的，这里顺便恢复音量
            if ok, !muted, !prefs[keyPath: savedVolumes].isEmpty {
                restoreVolumes(device)
            }
            return ok
        }

        let elements = volumeElements(device)
        guard !elements.isEmpty else { return false }
        if muted {
            let current = elements.map { readVolume(device, element: $0) ?? 0.8 }
            if current.contains(where: { $0 > 0.001 }) {
                prefs[keyPath: savedVolumes] = current
            }
            return elements.allSatisfy { writeVolume(device, element: $0, 0) }
        } else {
            return restoreVolumes(device)
        }
    }

    @discardableResult
    private func restoreVolumes(_ device: AudioDeviceID) -> Bool {
        let prefs = Preferences.shared
        let elements = volumeElements(device)
        let saved = prefs[keyPath: savedVolumes]
        var ok = true
        for (index, element) in elements.enumerated() {
            let value = index < saved.count && saved[index] > 0.001 ? saved[index] : 0.6
            ok = writeVolume(device, element: element, value) && ok
        }
        prefs[keyPath: savedVolumes] = []
        return ok
    }

    // MARK: - 静音属性

    private func muteAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: scope, mElement: mainElement)
    }

    private func hasSettableMute(_ device: AudioDeviceID) -> Bool {
        var address = muteAddress()
        return isSettable(device, &address)
    }

    private func readMute(_ device: AudioDeviceID) -> Bool? {
        var address = muteAddress()
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value != 0
    }

    private func writeMute(_ device: AudioDeviceID, _ muted: Bool) -> Bool {
        var address = muteAddress()
        var value = UInt32(muted ? 1 : 0)
        let size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectSetPropertyData(device, &address, 0, nil, size, &value) == noErr
    }

    // MARK: - 音量

    private func volumeAddress(_ element: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: scope, mElement: element)
    }

    /// 可以调音量的声道：优先用主声道，否则逐个声道调
    private func volumeElements(_ device: AudioDeviceID) -> [AudioObjectPropertyElement] {
        var main = volumeAddress(mainElement)
        if isSettable(device, &main) { return [mainElement] }
        var result: [AudioObjectPropertyElement] = []
        for channel in UInt32(1)...UInt32(8) {
            var address = volumeAddress(channel)
            if isSettable(device, &address) { result.append(channel) }
        }
        return result
    }

    private func readVolume(_ device: AudioDeviceID, element: AudioObjectPropertyElement) -> Float? {
        var address = volumeAddress(element)
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private func writeVolume(_ device: AudioDeviceID, element: AudioObjectPropertyElement, _ volume: Float) -> Bool {
        var address = volumeAddress(element)
        var value = Float32(volume)
        let size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectSetPropertyData(device, &address, 0, nil, size, &value) == noErr
    }

    private func isSettable(_ device: AudioDeviceID, _ address: inout AudioObjectPropertyAddress) -> Bool {
        guard AudioObjectHasProperty(device, &address) else { return false }
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr else { return false }
        return settable.boolValue
    }
}
