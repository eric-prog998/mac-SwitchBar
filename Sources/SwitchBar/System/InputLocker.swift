import AppKit
import ApplicationServices
import SwiftUI

/// 清洁屏幕：全屏变黑，同时锁住键盘、屏蔽触控板手势，擦屏幕时不会误触。
///
/// 原理：用 CGEventTap 在系统最前端拦截键盘和手势事件并丢弃（需要「辅助功能」权限）。
/// 安全性：拦截只在 SwitchBar 进程里生效，SwitchBar 退出或崩溃时系统会自动撤销，
/// 不会出现「键盘永久失灵」；鼠标 / 触控板点按始终可用，按住屏幕上的按钮 2 秒即可解锁。
final class InputLocker {
    private(set) var isLocked = false
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var windows: [NSWindow] = []
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    /// 锁定前在最前面的应用，解锁后把焦点还给它
    private var previousApp: NSRunningApplication?

    var onChange: (() -> Void)?

    static var hasPermission: Bool { AXIsProcessTrusted() }

    /// 弹出系统的「辅助功能」授权提示
    static func requestPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// 等用户松开修饰键后再开始锁定（否则通过快捷键触发时，⌃⌥ 等键的「松开」事件会被拦截，
    /// 导致解锁后系统以为这些键还按着）。completion 返回错误信息，nil 表示成功。
    func startWhenModifiersReleased(completion: @escaping (String?) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.waitForModifiers(attemptsLeft: 30, completion: completion)
        }
    }

    private func waitForModifiers(attemptsLeft: Int, completion: @escaping (String?) -> Void) {
        let modifiers: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift, .maskSecondaryFn]
        let held = CGEventSource.flagsState(.hidSystemState).intersection(modifiers)
        if held.isEmpty || attemptsLeft <= 0 {
            completion(start())
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.waitForModifiers(attemptsLeft: attemptsLeft - 1, completion: completion)
        }
    }

    /// 返回错误信息，nil 表示成功
    func start() -> String? {
        if isLocked { stop() }
        guard Self.hasPermission else {
            Self.requestPermission()
            return "清洁屏幕需要「辅助功能」权限：请在 系统设置 › 隐私与安全性 › 辅助功能 中打开 SwitchBar，然后再试一次。"
        }
        guard installTap() else {
            return "无法拦截键盘。如果刚重新安装过 SwitchBar，请在「辅助功能」列表里先删除它，再重新添加。"
        }
        isLocked = true
        installObservers()
        showOverlay()
        onChange?()
        return nil
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        removeObservers()

        let closing = windows
        windows.removeAll()
        for window in closing {
            window.orderOut(nil)
        }
        // 解锁按钮本身就在这些窗口里：等这次点击处理完再释放窗口
        DispatchQueue.main.async { _ = closing }

        guard isLocked else { return }
        isLocked = false
        if let previousApp { AppActivation.reactivate(previousApp) }
        previousApp = nil
        onChange?()
    }

    fileprivate func reenableTap() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    // MARK: - 自动解锁

    /// 安全保护：电脑睡眠、合上屏幕、锁屏、切换用户时自动解锁，避免回来后键盘无法输入密码。
    /// 只在锁定期间监听，平时不占任何资源。
    private func installObservers() {
        removeObservers()
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            let token = workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.stop()
            }
            observers.append((workspace, token))
        }
        let distributed = DistributedNotificationCenter.default()
        let token = distributed.addObserver(forName: Notification.Name("com.apple.screenIsLocked"),
                                            object: nil, queue: .main) { [weak self] _ in
            self?.stop()
        }
        observers.append((distributed, token))
    }

    private func removeObservers() {
        for (center, token) in observers {
            center.removeObserver(token)
        }
        observers.removeAll()
    }

    // MARK: - 事件拦截

    private func installTap() -> Bool {
        let types: [UInt32] = [
            CGEventType.keyDown.rawValue,
            CGEventType.keyUp.rawValue,
            CGEventType.flagsChanged.rawValue,
            14, // NSEventTypeSystemDefined：亮度、音量、播放等媒体键
            CGEventType.scrollWheel.rawValue,
            // 触控板手势（缩放、旋转、轻扫、调度中心等）
            18, 19, 20, 29, 30, 31, 32,
        ]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1)) }

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            // 系统可能因为超时暂停拦截，这时立刻重新启用
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let userInfo {
                    Unmanaged<InputLocker>.fromOpaque(userInfo).takeUnretainedValue().reenableTap()
                }
                return Unmanaged.passUnretained(event)
            }
            return nil // 丢弃事件
        }

        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        // HID 层级最早拦截，连 ⌘Tab、⌘空格 这类系统快捷键也能挡住；失败就退回会话层级
        let created = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: mask, callback: callback, userInfo: userInfo)
            ?? CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                 eventsOfInterest: mask, callback: callback, userInfo: userInfo)
        guard let created else { return false }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: created, enable: true)
        tap = created
        runLoopSource = source
        return true
    }

    // MARK: - 黑屏窗口

    private func showOverlay() {
        let frontmost = NSWorkspace.shared.frontmostApplication
        previousApp = frontmost == NSRunningApplication.current ? nil : frontmost
        AppActivation.activate()
        let mouseScreen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first

        for screen in NSScreen.screens {
            let showsControls = screen == mouseScreen
            let window = Self.makeOverlayWindow(frame: screen.frame, showsControls: showsControls) { [weak self] in
                self?.stop()
            }
            if showsControls {
                window.makeKeyAndOrderFront(nil)
            } else {
                window.orderFrontRegardless()
            }
            windows.append(window)
        }
    }

    /// 盖住一块屏幕的黑色窗口。先放界面、再设大小（反过来的话，SwiftUI 界面放进窗口时可能把窗口改小）
    static func makeOverlayWindow(frame: NSRect, showsControls: Bool, onUnlock: @escaping () -> Void) -> OverlayWindow {
        let window = OverlayWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: CleaningView(showsControls: showsControls, onUnlock: onUnlock))
        window.setFrame(frame, display: false)
        window.isOpaque = true
        window.backgroundColor = .black
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isReleasedWhenClosed = false
        return window
    }
}

/// 无边框窗口默认不能成为主窗口，这里放开，保证第一次点击就能点中按钮
final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
