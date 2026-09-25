import Foundation

/// 推出外接磁盘、磁盘映像和网络宗卷（公开的 FileManager 接口）
enum Disks {
    struct Volume {
        let url: URL
        let name: String
        let isNetwork: Bool
    }

    static func ejectableVolumes() -> [Volume] {
        let keys: [URLResourceKey] = [
            .volumeIsEjectableKey, .volumeIsRemovableKey, .volumeIsInternalKey,
            .volumeIsLocalKey, .volumeIsRootFileSystemKey, .volumeLocalizedNameKey,
        ]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys,
                                                         options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url in
            guard url.path.hasPrefix("/Volumes/"),
                  let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.volumeIsRootFileSystem != true else { return nil }
            let isNetwork = values.volumeIsLocal == false
            let isExternal = values.volumeIsEjectable == true
                || values.volumeIsRemovable == true
                || values.volumeIsInternal == false
            guard isNetwork || isExternal else { return nil }
            return Volume(url: url, name: values.volumeLocalizedName ?? url.lastPathComponent, isNetwork: isNetwork)
        }
    }

    /// 逐个推出宗卷，完成后在主线程回调推出失败的宗卷名称
    static func eject(_ volumes: [Volume], completion: @escaping ([String]) -> Void) {
        ejectNext(volumes[...], failed: [], completion: completion)
    }

    private static func ejectNext(_ remaining: ArraySlice<Volume>, failed: [String],
                                  completion: @escaping ([String]) -> Void) {
        guard let volume = remaining.first else {
            DispatchQueue.main.async { completion(failed) }
            return
        }
        // 前面推出整块硬盘时，同一块硬盘上的其他宗卷已经一起被推出了
        guard FileManager.default.fileExists(atPath: volume.url.path) else {
            ejectNext(remaining.dropFirst(), failed: failed, completion: completion)
            return
        }
        let options: FileManager.UnmountOptions = volume.isNetwork ? [] : [.allPartitionsAndEjectDisk]
        FileManager.default.unmountVolume(at: volume.url, options: options) { error in
            var failed = failed
            if let error, FileManager.default.fileExists(atPath: volume.url.path) {
                NSLog("SwitchBar: 推出 \(volume.name) 失败：\(error)")
                failed.append(volume.name)
            }
            ejectNext(remaining.dropFirst(), failed: failed, completion: completion)
        }
    }
}
