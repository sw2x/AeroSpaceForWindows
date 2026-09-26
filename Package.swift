// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "AeroSpaceForWindows",
    products: [
        .executable(name: "aerospace", targets: ["Cli"]),
        .executable(name: "AeroSpaceApp", targets: ["AeroSpaceApp"]),
        .executable(name: "WindowsSmoke", targets: ["WindowsSmoke"]),
    ],
    dependencies: [
        .package(url: "https://github.com/dduan/TOMLDecoder", exact: "0.4.4"),
        .package(url: "https://github.com/apple/swift-collections", exact: "1.3.0"),
    ],
    targets: [
        .target(name: "NativeWindows", publicHeadersPath: "include", linkerSettings: [
            .linkedLibrary("user32"), .linkedLibrary("dwmapi"), .linkedLibrary("shell32"),
            .linkedLibrary("ole32"), .linkedLibrary("advapi32"), .linkedLibrary("uuid"),
        ]),
        .target(name: "Common", dependencies: ["NativeWindows", .product(name: "Collections", package: "swift-collections")]),
        .target(name: "AppBundle", dependencies: ["Common", "NativeWindows",
            .product(name: "Collections", package: "swift-collections"),
            .product(name: "TOMLDecoder", package: "TOMLDecoder"),
        ], resources: [.copy("Resources/default-config.toml")]),
        .executableTarget(name: "AeroSpaceApp", dependencies: ["AppBundle", "Common", "NativeWindows"],
            linkerSettings: [.unsafeFlags(["-Xlinker", "/SUBSYSTEM:WINDOWS", "-Xlinker", "/ENTRY:mainCRTStartup"])]),
        .executableTarget(name: "Cli", dependencies: ["Common", "NativeWindows"]),
        .testTarget(name: "AppBundleTests", dependencies: ["AppBundle"], path: "Sources/AppBundleTests"),
        .executableTarget(name: "WindowsSmoke", dependencies: ["NativeWindows"], path: "Tests/WindowsSmoke", linkerSettings: [.linkedLibrary("swiftCore")]),
    ],
    swiftLanguageModes: [.v5]
)
