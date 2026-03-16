// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SnapPin",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/soffes/HotKey", from: "0.2.1")
    ],
    targets: [
        .executableTarget(
            name: "SnapPin",
            dependencies: ["HotKey"],
            path: "SnapPin",
            exclude: ["Info.plist", "SnapPin.entitlements"],
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ScreenCaptureKit")
            ]
        )
    ]
)
