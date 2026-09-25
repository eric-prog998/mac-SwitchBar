import Foundation

// 夜览和原彩显示没有公开接口，系统设置本身用的是 CoreBrightness 私有框架。
// 这里在运行时动态加载它，只调用「读状态 / 开 / 关」这几个方法；
// 如果未来 macOS 改掉了这些方法，对应开关会自动变成不可用，而不会崩溃。

private let coreBrightnessLoaded: Bool = {
    dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY) != nil
}()

private func makeClient(_ className: String) -> NSObject? {
    guard coreBrightnessLoaded, let cls = NSClassFromString(className) as? NSObject.Type else { return nil }
    return cls.init()
}

/// 用 Objective-C 运行时安全地调用返回 BOOL 的方法
private enum ObjCCall {
    static func bool(_ object: NSObject, _ name: String) -> Bool? {
        let selector = NSSelectorFromString(name)
        guard object.responds(to: selector) else { return nil }
        typealias Function = @convention(c) (NSObject, Selector) -> Bool
        let function = unsafeBitCast(object.method(for: selector), to: Function.self)
        return function(object, selector)
    }

    static func setBool(_ object: NSObject, _ name: String, _ value: Bool) -> Bool? {
        let selector = NSSelectorFromString(name)
        guard object.responds(to: selector) else { return nil }
        typealias Function = @convention(c) (NSObject, Selector, Bool) -> Bool
        let function = unsafeBitCast(object.method(for: selector), to: Function.self)
        return function(object, selector, value)
    }

    static func classBool(_ className: String, _ name: String) -> Bool? {
        guard let cls = NSClassFromString(className) else { return nil }
        let selector = NSSelectorFromString(name)
        guard let method = class_getClassMethod(cls, selector) else { return nil }
        typealias Function = @convention(c) (AnyObject, Selector) -> Bool
        let function = unsafeBitCast(method_getImplementation(method), to: Function.self)
        return function(cls as AnyObject, selector)
    }
}

/// 夜览（CBBlueLightClient）
final class NightShift {
    private let client = makeClient("CBBlueLightClient")

    var isSupported: Bool {
        guard client != nil else { return false }
        return ObjCCall.classBool("CBBlueLightClient", "supportsBlueLightReduction") ?? true
    }

    var isEnabled: Bool {
        guard let client else { return false }
        let selector = NSSelectorFromString("getBlueLightStatus:")
        guard client.responds(to: selector) else { return false }
        typealias Function = @convention(c) (NSObject, Selector, UnsafeMutableRawPointer) -> Bool
        let function = unsafeBitCast(client.method(for: selector), to: Function.self)
        // 状态结构体：{ BOOL active; BOOL enabled; … }，第 2 个字节就是「是否开启」。
        // 多分配一些空间，即使以后结构体变大也不会越界写。
        let size = 256
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 16)
        defer { buffer.deallocate() }
        buffer.initializeMemory(as: UInt8.self, repeating: 0, count: size)
        guard function(client, selector, buffer) else { return false }
        return buffer.load(fromByteOffset: 1, as: UInt8.self) != 0
    }

    /// 返回是否成功调用
    func setEnabled(_ enabled: Bool) -> Bool {
        guard let client else { return false }
        return ObjCCall.setBool(client, "setEnabled:", enabled) != nil
    }
}

/// 原彩显示（CBTrueToneClient）
final class TrueTone {
    private let client = makeClient("CBTrueToneClient")

    var isSupported: Bool {
        guard let client else { return false }
        return (ObjCCall.bool(client, "supported") ?? false) && (ObjCCall.bool(client, "available") ?? false)
    }

    var isEnabled: Bool {
        guard let client else { return false }
        return ObjCCall.bool(client, "enabled") ?? false
    }

    func setEnabled(_ enabled: Bool) -> Bool {
        guard let client else { return false }
        return ObjCCall.setBool(client, "setEnabled:", enabled) != nil
    }
}
