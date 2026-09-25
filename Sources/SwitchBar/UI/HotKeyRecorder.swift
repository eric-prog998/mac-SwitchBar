import AppKit
import Carbon.HIToolbox
import SwiftUI

/// 录制全局快捷键的按钮：点一下后按下组合键；Esc 取消，Delete 清除
struct HotKeyRecorder: View {
    let feature: FeatureID
    @ObservedObject var prefs: Preferences

    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 4) {
            Button(action: toggleRecording) {
                Text(label)
                    .frame(minWidth: 96)
                    .foregroundColor(recording ? .accentColor : (prefs.hotKeys[feature] == nil ? .secondary : .primary))
            }
            if prefs.hotKeys[feature] != nil && !recording {
                Button {
                    prefs.setHotKey(nil, for: feature)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help("清除快捷键")
            }
        }
        .onDisappear(perform: stopRecording)
    }

    private var label: String {
        if recording { return "请按下快捷键…" }
        return prefs.hotKeys[feature]?.displayString ?? "录制快捷键"
    }

    private func toggleRecording() {
        if recording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        recording = true
        HotKeyManager.shared.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil
        }
    }

    private func handle(_ event: NSEvent) {
        let keyCode = UInt32(event.keyCode)
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])

        if keyCode == UInt32(kVK_Escape) && flags.isEmpty {
            stopRecording()
            return
        }
        if (keyCode == UInt32(kVK_Delete) || keyCode == UInt32(kVK_ForwardDelete)) && flags.isEmpty {
            prefs.setHotKey(nil, for: feature)
            stopRecording()
            return
        }
        // 必须带 ⌘ / ⌥ / ⌃ 中的至少一个（F1–F20 除外），否则会和正常打字冲突
        guard !flags.subtracting(.shift).isEmpty || KeyNames.isFunctionKey(keyCode) else {
            NSSound.beep()
            return
        }
        prefs.setHotKey(HotKey(keyCode: keyCode, modifiers: HotKey.carbonModifiers(from: flags)), for: feature)
        stopRecording()
    }

    private func stopRecording() {
        guard recording else { return }
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        recording = false
        HotKeyManager.shared.resume()
    }
}
