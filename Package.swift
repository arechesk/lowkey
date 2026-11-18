// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Lowkey",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure logic: configuration, deep links, address input, history, link policy, themes. No AppKit.
        .target(name: "LowkeyCore", path: "Sources/LowkeyCore",
                swiftSettings: [.swiftLanguageMode(.v5)]),
        // The browser app (AppKit + WebKit + SwiftUI settings).
        .executableTarget(name: "Lowkey", dependencies: ["LowkeyCore"], path: "Sources/Lowkey",
                          swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "LowkeyCoreTests", dependencies: ["LowkeyCore"], path: "Tests/LowkeyCoreTests",
                    swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "LowkeyAppTests", dependencies: ["Lowkey"], path: "Tests/LowkeyAppTests",
                    swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
