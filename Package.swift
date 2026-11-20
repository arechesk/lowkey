// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Lowkey",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "Vendor/BobukKit")],
    targets: [
        // Pure logic: configuration, deep links, address input, history, link policy, themes. No AppKit.
        // BobukCore is Foundation-only (layout swap, recent list, message port).
        .target(name: "LowkeyCore", dependencies: [.product(name: "BobukCore", package: "BobukKit")],
                path: "Sources/LowkeyCore",
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "lowkeyctl", dependencies: ["LowkeyCore", .product(name: "BobukCore", package: "BobukKit")],
                          swiftSettings: [.swiftLanguageMode(.v5)]),
        // The browser app (AppKit + WebKit + SwiftUI settings).
        .executableTarget(name: "Lowkey", dependencies: ["LowkeyCore",
                                                         .product(name: "BobukCore", package: "BobukKit"),
                                                         .product(name: "BobukSystem", package: "BobukKit"),
                                                         .product(name: "BobukUI", package: "BobukKit")],
                          path: "Sources/Lowkey",
                          swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "LowkeyCoreTests", dependencies: ["LowkeyCore"], path: "Tests/LowkeyCoreTests",
                    swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "LowkeyAppTests", dependencies: ["Lowkey", .product(name: "BobukUI", package: "BobukKit")], path: "Tests/LowkeyAppTests",
                    swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
