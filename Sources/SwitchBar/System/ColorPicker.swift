import AppKit

/// 取色器：弹出系统自带的取色放大镜（NSColorSampler），点一下屏幕上任意位置取色，按 Esc 取消。
/// 放大镜由系统提供，SwitchBar 自己看不到屏幕内容，所以不需要「屏幕录制」权限。
enum ColorPicker {
    /// 取色期间保持引用，取完就释放
    private static var sampler: NSColorSampler?

    /// 取到颜色后在主线程回调（色值 #RRGGBB，颜色）；取消时不回调
    static func pick(completion: @escaping (String, NSColor) -> Void) {
        let sampler = NSColorSampler()
        self.sampler = sampler
        sampler.show { color in
            DispatchQueue.main.async {
                self.sampler = nil
                guard let color, let hex = hexString(color) else { return }
                completion(hex, color)
            }
        }
    }

    /// 转成 sRGB 后的十六进制色值（网页、设计软件通用的格式）
    static func hexString(_ color: NSColor) -> String? {
        guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
        let channels = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent].map { component in
            Int((min(max(component, 0), 1) * 255).rounded())
        }
        return String(format: "#%02X%02X%02X", channels[0], channels[1], channels[2])
    }
}
