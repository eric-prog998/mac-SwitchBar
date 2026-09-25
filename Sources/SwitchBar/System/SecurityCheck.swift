import AppKit
import ApplicationServices
import Carbon.HIToolbox
import CoreBluetooth
import IOKit.hid
import Security

/// 「权限体检」：读取 SwitchBar 当前在系统里拥有哪些权限。
/// 这里用的都是「只查询、不申请」的系统接口，调用它们不会弹出授权窗口，也不会把 SwitchBar 加进任何权限列表。
enum SecurityCheck {
    enum State: Equatable {
        case granted
        case denied
        case notDetermined
        case unknown(String)
    }

    /// 辅助功能（锁定键盘、清洁屏幕需要）
    static var accessibility: State {
        AXIsProcessTrusted() ? .granted : .denied
    }

    /// 自动化 › 系统事件（深色模式、程序坞、菜单栏需要）
    static var automation: State {
        let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.systemevents")
        guard let desc = target.aeDesc else { return .unknown("无法查询") }
        let status = AEDeterminePermissionToAutomateTarget(desc, AEEventClass(typeWildCard), AEEventID(typeWildCard), false)
        switch status {
        case noErr: return .granted
        case OSStatus(errAEEventNotPermitted): return .denied
        case OSStatus(errAEEventWouldRequireUserConsent): return .notDetermined
        case OSStatus(procNotFound): return .unknown("「系统事件」没有运行，用到时会自动启动")
        default: return .unknown("错误 \(status)")
        }
    }

    /// 蓝牙（蓝牙耳机需要）
    static var bluetooth: State {
        switch CBManager.authorization {
        case .allowedAlways: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .unknown("未知状态")
        }
    }

    /// 屏幕录制——SwitchBar 不需要
    static var screenRecording: State {
        CGPreflightScreenCaptureAccess() ? .granted : .denied
    }

    /// 输入监控——SwitchBar 不需要
    static var inputMonitoring: State {
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted: return .granted
        case kIOHIDAccessTypeDenied: return .denied
        default: return .notDetermined
        }
    }
}

/// 读取 SwitchBar 自己的代码签名，确认「强化运行时」已开启
enum CodeSignature {
    struct Info {
        /// 强化运行时：其他程序不能注入代码、不能用调试器附加
        let hardenedRuntime: Bool
        /// 临时签名（没有证书）
        let adHoc: Bool
        /// 证书名称（自签名证书时是 "SwitchBar Local"）
        let signer: String?
    }

    static func current() -> Info? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var information: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &information) == errSecSuccess,
              let dictionary = information as? [String: Any] else { return nil }

        let codeFlags = (dictionary[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
        let certificates = dictionary[kSecCodeInfoCertificates as String] as? [SecCertificate]
        let signer = certificates?.first.flatMap { SecCertificateCopySubjectSummary($0) as String? }
        return Info(hardenedRuntime: codeFlags & 0x1_0000 != 0, // kSecCodeSignatureRuntime
                    adHoc: codeFlags & 0x0002 != 0,             // kSecCodeSignatureAdhoc
                    signer: signer)
    }
}
