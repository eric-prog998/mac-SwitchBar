import SwiftUI

/// 清洁屏幕：全黑背景，按住按钮 2 秒才解锁，防止擦屏幕时误触
struct CleaningView: View {
    let showsControls: Bool
    let onUnlock: () -> Void

    @State private var pressing = false

    var body: some View {
        ZStack {
            Color.black
            if showsControls {
                VStack(spacing: 14) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 40))
                        .foregroundColor(.white.opacity(0.75))
                    Text("清洁模式")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)
                    Text("屏幕和键盘已锁定，可以放心擦拭")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.6))
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.08))
                        Circle()
                            .stroke(Color.white.opacity(0.2), lineWidth: 4)
                        Circle()
                            .trim(from: 0, to: pressing ? 1 : 0)
                            .stroke(Color.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(pressing ? .linear(duration: 2) : .easeOut(duration: 0.2), value: pressing)
                        Image(systemName: "lock.open.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.white)
                    }
                    .frame(width: 72, height: 72)
                    .contentShape(Circle())
                    .onLongPressGesture(minimumDuration: 2, maximumDistance: 40, perform: onUnlock,
                                        onPressingChanged: { pressing = $0 })
                    .padding(.top, 10)
                    Text(pressing ? "继续按住…" : "按住上面的按钮 2 秒解锁")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
        }
    }
}
