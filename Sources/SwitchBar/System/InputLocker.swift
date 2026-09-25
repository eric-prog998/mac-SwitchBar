import AppKit
import ApplicationServices
import SwiftUI

/// 锁定键盘 / 清洁屏幕。
///
/// 原理：用 CGEventTap 在系统最前端拦截键盘事件并丢弃（需要「辅助功能」权限）。
/// 安全性：拦截只在 SwitchBar 进程里生效，SwitchBar 退出或崩溃时系统会自动撤销，
/// 不会出现「键盘永久失灵」；鼠标 / 触控板始终可用，随时可以点按钮解锁。
final class InputLocker {
    enum Mode {
        /// 只锁键盘，屏幕中央显示一个解锁按钮
        case keyboard
        /// 全屏变黑 + 锁键盘 + 屏蔽触控板手势，按住按钮 2 秒解锁
        case cleaning
    }

    private(set) var mode: Mode?
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var windows: [NSWindow] = []

    var onChange: (() -> Void)?

    init() {
        // 安全保护：电脑睡眠、合上屏幕、锁屏时自动解锁，避免回来后键盘无法输入密码
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.stopIfLocked()
            }
        }
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in
            self?.stopIfLocked()
        }
    }

    private func stopIfLocked() {
        if mode != nil { stop() }
    }

    static var hasPermission: Bool { AXIsProcessTrusted() }

    /// 弹出系统的「辅助功能」授权提示
    static func requestPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// 等用户松开修饰键后再开始锁定（否则通过快捷键触发时，⌘⌥ 等键的「松开」事件会被拦截，
    /// 导致解锁后系统以为这些键还按着）。completion 返回错误信息，nil 表示成功。
    func startWhenModifiersReleased(_ mode: Mode, completion: @escaping (String?) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.waitForModifiers(mode, attemptsLeft: 30, completion: completion)
        }
    }

    private func waitForModifiers(_ mode: Mode, attemptsLeft: Int, completion: @escaping (String?) -> Void) {
        let modifiers: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift, .maskSecondaryFn]
        let held = CGEventSource.flagsState(.hidSystemState).intersection(modifiers)
        if held.isEmpty || attemptsLeft <= 0 {
            completion(start(mode))
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.waitForModifiers(mode, attemptsLeft: attemptsLeft - 1, completion: completion)
        }
    }

    /// 返回错误信息，nil 表示成功
    func start(_ mode: Mode) -> String? {
        if self.mode != nil { stop() }
        guard Self.hasPermission else {
            Self.requestPermission()
            return "锁定键盘需要「辅助功能」权限：请在 系统设置 › 隐私与安全性 › 辅助功能 中打开 SwitchBar，然后再试一次。"
        }
        guard installTap(for: mode) else {
            return "无法拦截键盘。如果刚重新编译过 SwitchBar，请在「辅助功能」列表里先删除它，再重新添加。"
        }
        self.mode = mode
        showOverlay(for: mode)
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
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
        let wasLocked = mode != nil
        mode = nil
        if wasLocked { onChange?() }
    }

    fileprivate func reenableTap() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    // MARK: - 事件拦截

    private func installTap(for mode: Mode) -> Bool {
        var types: [UInt32] = [
            CGEventType.keyDown.rawValue,
            CGEventType.keyUp.rawValue,
            CGEventType.flagsChanged.rawValue,
            14, // NSEventTypeSystemDefined：亮度、音量、播放等媒体键
        ]
        if mode == .cleaning {
            // 滚动和触控板手势（缩放、旋转、轻扫、调度中心等）
            types += [CGEventType.scrollWheel.rawValue, 18, 19, 20, 29, 30, 31, 32]
        }
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

    // MARK: - 覆盖窗口

    private func showOverlay(for mode: Mode) {
        AppActivation.activate()
        let mouseScreen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first

        switch mode {
        case .keyboard:
            let hosting = NSHostingView(rootView: KeyboardLockView { [weak self] in self?.stop() })
            let size = hosting.fittingSize
            let window = OverlayWindow(contentRect: NSRect(origin: .zero, size: size),
                                       styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = hosting
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.level = .statusBar
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isReleasedWhenClosed = false
            if let frame = mouseScreen?.frame {
                window.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2))
            }
            window.makeKeyAndOrderFront(nil)
            windows = [window]

        case .cleaning:
            for screen in NSScreen.screens {
                let window = OverlayWindow(contentRect: screen.frame, styleMask: [.borderless],
                                           backing: .buffered, defer: false)
                window.setFrame(screen.frame, display: false)
                let showsControls = screen == mouseScreen
                window.contentView = NSHostingView(rootView: CleaningView(showsControls: showsControls) { [weak self] in
                    self?.stop()
                })
                window.isOpaque = true
                window.backgroundColor = .black
                window.level = .screenSaver
                window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
                window.isReleasedWhenClosed = false
                if showsControls {
                    window.makeKeyAndOrderFront(nil)
                } else {
                    window.orderFrontRegardless()
                }
                windows.append(window)
            }
        }
    }
}

/// 无边框窗口默认不能成为主窗口，这里放开，保证第一次点击就能点中按钮
final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
