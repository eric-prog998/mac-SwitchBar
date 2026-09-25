// swift-tools-version:5.9
// SwitchBar：只依赖苹果系统框架，没有任何第三方依赖。
import PackageDescription

let package = Package(
    name: "SwitchBar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "SwitchBar",
            path: "Sources/SwitchBar",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("IOBluetooth"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
    ]
)
