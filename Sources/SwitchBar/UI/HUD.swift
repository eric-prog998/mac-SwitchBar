import AppKit
import SwiftUI

/// 屏幕下方短暂出现的提示（类似系统调节音量时的提示框），用于快捷键操作的反馈和错误提示
final class HUD {
    static let shared = HUD()

    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    /// 窗口编号（调试版截图用）
    var windowNumber: Int? { panel?.windowNumber }

    func show(_ text: String, symbol: String, duration: TimeInterval = 1.4,
              colors: [Color] = FeatureColors.pair(0x6F8BFF, 0x3B6BFF)) {
        let panel = self.panel ?? makePanel()
        self.panel = panel

        let host = NSHostingView(rootView: HUDView(text: text, symbol: symbol, colors: colors))
        let size = host.fittingSize
        panel.contentView = host

        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            let origin = NSPoint(x: frame.midX - size.width / 2, y: frame.minY + frame.height * 0.14)
            panel.setFrame(NSRect(origin: origin, size: size), display: true)
        }
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        panel.invalidateShadow()

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.fadeOut() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    private func fadeOut() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            panel.animator().alphaValue = 0
        }, completionHandler: {
            // 渐隐过程中如果又显示了新提示，就不要把它藏起来
            if panel.alphaValue < 0.01 {
                panel.orderOut(nil)
            }
        })
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return panel
    }
}

struct HUDView: View {
    let text: String
    let symbol: String
    var colors: [Color] = FeatureColors.pair(0x6F8BFF, 0x3B6BFF)

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 38, height: 38)
                .background(Circle().fill(colors.diagonalGradient))
                .shadow(color: colors[1].opacity(0.45), radius: 6, y: 2)
            Text(text)
                .font(Theme.rounded(14, .semibold))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 12)
        .padding(.trailing, 20)
        .padding(.vertical, 12)
        .frame(width: text.count > 16 ? 330 : nil, alignment: .leading)
        .panelBackground(cornerRadius: 31)
    }
}
