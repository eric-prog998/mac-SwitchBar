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
    let background = NSRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8)
    let backgroundPath = NSBezierPath(roundedRect: background, xRadius: s * 0.18, yRadius: s * 0.18)
    let gradient = NSGradient(starting: NSColor(calibratedRed: 0.22, green: 0.56, blue: 1.0, alpha: 1),
                              ending: NSColor(calibratedRed: 0.40, green: 0.30, blue: 0.93, alpha: 1))!
    gradient.draw(in: backgroundPath, angle: -90)

    let pill = NSRect(x: s * 0.24, y: s * 0.38, width: s * 0.52, height: s * 0.24)
    NSColor.white.setFill()
    NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()

    let inset = pill.height * 0.12
    let knobSize = pill.height - inset * 2
    let knob = NSRect(x: pill.maxX - inset - knobSize, y: pill.minY + inset, width: knobSize, height: knobSize)
    NSColor(calibratedRed: 0.28, green: 0.47, blue: 1.0, alpha: 1).setFill()
    NSBezierPath(ovalIn: knob).fill()

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
