import Foundation
import IOBluetooth

/// 连接 / 断开已配对的蓝牙耳机（公开的 IOBluetooth 接口，和 blueutil 等开源工具用的相同）
final class BluetoothAudio: NSObject {
    struct Device {
        let address: String
        let name: String
        let isConnected: Bool
    }

    private struct Pending {
        let token: UUID
        let completion: (Bool) -> Void
    }

    private var pending: [String: Pending] = [:]

    /// 已配对的音频设备（耳机、音箱）；如果一个都识别不出来，就列出全部已配对设备
    func pairedAudioDevices() -> [Device] {
        let devices = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        let audioMajor = BluetoothDeviceClassMajor(kBluetoothDeviceClassMajorAudio)
        let audio = devices.filter { $0.deviceClassMajor == audioMajor }
        return (audio.isEmpty ? devices : audio).compactMap { device in
            guard let address = device.addressString else { return nil }
            return Device(address: address, name: device.name ?? address, isConnected: device.isConnected())
        }
    }

    func isConnected(address: String) -> Bool {
        guard let device = IOBluetoothDevice(addressString: address) else { return false }
        return device.isConnected()
    }

    /// 异步连接，完成后在主线程回调
    func connect(address: String, completion: @escaping (Bool) -> Void) {
        guard let device = IOBluetoothDevice(addressString: address) else {
            completion(false)
            return
        }
        if device.isConnected() {
            completion(true)
            return
        }
        let token = UUID()
        pending[address] = Pending(token: token, completion: completion)
        guard device.openConnection(self) == kIOReturnSuccess else {
            finish(address, ok: false)
            return
        }
        // 兜底：设备不在附近时可能迟迟没有回调（只处理这一次连接，不影响之后的连接）
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            guard let self, self.pending[address]?.token == token else { return }
            self.finish(address, ok: device.isConnected())
        }
    }

    func disconnect(address: String) {
        guard let device = IOBluetoothDevice(addressString: address) else { return }
        device.closeConnection()
    }

    /// IOBluetooth 连接完成的回调
    @objc func connectionComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        guard let address = device?.addressString else { return }
        finish(address, ok: status == kIOReturnSuccess)
    }

    private func finish(_ address: String, ok: Bool) {
        guard let entry = pending.removeValue(forKey: address) else { return }
        entry.completion(ok)
    }
}
