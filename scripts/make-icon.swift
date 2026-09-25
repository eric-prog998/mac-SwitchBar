// 用代码画出应用图标（蓝紫渐变圆角方块 + 白色开关），生成 .iconset 目录，
// 再由 build-app.sh 调用系统自带的 iconutil 转成 .icns。这样仓库里不需要放任何二进制文件。
import AppKit

guard CommandLine.arguments.count > 1 else {
    print("用法：swift make-icon.swift <输出的 .iconset 目录>")
    exit(1)
}
let outputDirectory = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: outputDirectory, withIntermediateDirectories: true)

func render(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let s = CGFloat(pixels)
    // 按苹果图标网格：主体约占画布 80%，四周留出阴影空间
    let body = NSRect(x: s * 0.1, y: s * 0.11, width: s * 0.8, height: s * 0.8)
    let radius = s * 0.18
    let bodyPath = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)

    // 柔和投影
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = s * 0.025
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
    shadow.set()
    NSColor(calibratedRed: 0.25, green: 0.42, blue: 0.98, alpha: 1).setFill()
    bodyPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    // 蓝紫渐变底色
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.36, green: 0.70, blue: 1.00, alpha: 1),
        NSColor(calibratedRed: 0.27, green: 0.47, blue: 0.99, alpha: 1),
        NSColor(calibratedRed: 0.45, green: 0.30, blue: 0.92, alpha: 1),
    ])!
    gradient.draw(in: bodyPath, angle: -90)

    // 顶部的玻璃高光
    NSGraphicsContext.saveGraphicsState()
    bodyPath.addClip()
    let highlight = NSGradient(starting: NSColor.white.withAlphaComponent(0.32),
                               ending: NSColor.white.withAlphaComponent(0.0))!
    let highlightRect = NSRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2)
    highlight.draw(in: highlightRect, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // 细的内描边
    let rim = NSBezierPath(roundedRect: body.insetBy(dx: s * 0.004, dy: s * 0.004),
                           xRadius: radius - s * 0.004, yRadius: radius - s * 0.004)
    rim.lineWidth = s * 0.006
    NSColor.white.withAlphaComponent(0.28).setStroke()
    rim.stroke()

    // 开关：半透明白色的「胶囊」+ 右侧的圆形拨钮
    let pill = NSRect(x: s * 0.23, y: s * 0.385, width: s * 0.54, height: s * 0.25)
    let pillPath = NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2)
    NSColor.white.withAlphaComponent(0.92).setFill()
    pillPath.fill()

    let inset = pill.height * 0.11
    let knobSize = pill.height - inset * 2
    let knob = NSRect(x: pill.maxX - inset - knobSize, y: pill.minY + inset, width: knobSize, height: knobSize)
    let knobGradient = NSGradient(starting: NSColor(calibratedRed: 0.35, green: 0.62, blue: 1.0, alpha: 1),
                                  ending: NSColor(calibratedRed: 0.30, green: 0.40, blue: 0.96, alpha: 1))!
    knobGradient.draw(in: NSBezierPath(ovalIn: knob), angle: -90)

    // 左侧的小圆点，表示「关」的一端
    let dotSize = pill.height * 0.22
    let dot = NSRect(x: pill.minX + pill.height * 0.4 - dotSize / 2, y: pill.midY - dotSize / 2,
                     width: dotSize, height: dotSize)
    NSColor(calibratedRed: 0.30, green: 0.45, blue: 0.95, alpha: 0.35).setFill()
    NSBezierPath(ovalIn: dot).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let entries: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, pixels) in entries {
    try render(pixels).write(to: URL(fileURLWithPath: "\(outputDirectory)/\(name).png"))
}
print("图标已生成：\(outputDirectory)")
