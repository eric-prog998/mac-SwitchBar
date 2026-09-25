import AppKit
import SwiftUI

/// 录制全局快捷键的按钮：点一下后按下组合键；Esc 取消，Delete 清除
struct HotKeyRecorder: View {
    let target: HotKeyTarget
    @ObservedObject var prefs: Preferences
    @ObservedObject private var manager = HotKeyManager.shared

    var body: some View {
        let recording = manager.recording == target
        let key = prefs.hotKey(for: target)

        HStack(spacing: 4) {
            Button {
                if recording {
                    manager.endRecording()
                } else {
                    manager.beginRecording(target)
                }
            } label: {
                HStack(spacing: 5) {
                    if recording {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 7, height: 7)
                        Text("请按下快捷键…")
                    } else if let key {
                        Text(key.displayString)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                    } else {
                        Text("设置快捷键")
                            .foregroundColor(.secondary)
                    }
                }
                .frame(minWidth: 96)
            }
            .controlSize(.small)

            Button {
                prefs.setHotKey(nil, for: target)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
            .help("清除快捷键")
            .opacity(key != nil && !recording ? 1 : 0)
            .disabled(key == nil || recording)
        }
        .onDisappear {
            if manager.recording == target { manager.endRecording() }
        }
    }
}
