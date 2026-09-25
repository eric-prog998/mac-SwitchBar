import AppKit

// 直接用 AppKit 启动，不用 SwiftUI 的 App 生命周期：
// 菜单栏应用用不到它的窗口和场景管理，少加载一层，常驻时更省内存。
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
