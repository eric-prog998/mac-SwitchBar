import SwiftUI

/// 锁定键盘时屏幕中央的提示框
struct KeyboardLockView: View {
    let onUnlock: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "keyboard")
                .font(.system(size: 34))
            Text("键盘已锁定")
                .font(.title2.bold())
            Text("现在可以放心擦键盘了")
                .foregroundColor(.secondary)
            Button("解锁键盘", action: onUnlock)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(24)
        .frame(width: 300, height: 200)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// 清洁屏幕：全黑背景，按住按钮 2 秒才解锁，防止擦屏幕时误触
struct CleaningView: View {
    let showsControls: Bool
    let onUnlock: () -> Void

    @State private var pressing = false

    var body: some View {
        ZStack {
            Color.black
            if showsControls {
                VStack(spacing: 16) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 40))
                        .foregroundColor(.white.opacity(0.7))
                    Text("清洁模式")
                        .font(.title.bold())
                        .foregroundColor(.white)
                    Text("屏幕和键盘已锁定，可以放心擦拭")
                        .foregroundColor(.white.opacity(0.6))
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.25), lineWidth: 4)
                        Circle()
                            .trim(from: 0, to: pressing ? 1 : 0)
                            .stroke(Color.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(pressing ? .linear(duration: 2) : .easeOut(duration: 0.2), value: pressing)
                        Image(systemName: "lock.open.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                    }
                    .frame(width: 64, height: 64)
                    .contentShape(Circle())
                    .onLongPressGesture(minimumDuration: 2, maximumDistance: 40, perform: onUnlock,
                                        onPressingChanged: { pressing = $0 })
                    .padding(.top, 8)
                    Text(pressing ? "继续按住…" : "按住上面的按钮 2 秒解锁")
                        .font(.callout)
                        .foregroundColor(.white.opacity(0.6))
                }
            }
        }
    }
}
