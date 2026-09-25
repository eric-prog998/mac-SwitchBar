import AppKit
import SwiftUI

/// 屏幕下方短暂出现的提示（类似系统调节音量时的提示框），用于快捷键操作的反馈和错误提示。
/// 提示消失后窗口和界面都会释放，平时不占内存。
final class HUD {
    static let shared = HUD()

    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    /// 窗口编号（调试版截图用）
    var windowNumber: Int? { panel?.windowNumber }

    /// color 不为空时，图标用这个颜色显示（取色器用来展示取到的颜色）
    func show(_ text: String, symbol: String, color: NSColor? = nil, duration: TimeInterval = 1.4) {
        let panel = self.panel ?? makePanel()
        self.panel = panel

        let host = NSHostingView(rootView: HUDView(text: text, symbol: symbol, color: color.map(Color.init(nsColor:))))
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
        }, completionHandler: { [weak self] in
            // 渐隐过程中如果又显示了新提示，就不要把它藏起来
            guard let self, self.panel === panel, panel.alphaValue < 0.01 else { return }
            panel.orderOut(nil)
            panel.contentView = nil
            self.panel = nil
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
    var color: Color?

    var body: some View {
        HStack(spacing: 10) {
            icon
                .frame(width: 22)
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(width: text.count > 18 ? 320 : nil, alignment: .leading)
        .panelBackground(cornerRadius: 22)
    }

    @ViewBuilder
    private var icon: some View {
        if let color {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .foregroundColor(color)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 1))
        } else {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
        }
    }
}
