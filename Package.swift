// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let bareSDK = "\(Context.packageDirectory)/bare-sdk"

let package = Package(
    name: "BareKitLinux",
    products: [
        .library(name: "BareKitLinux", targets: ["BareKit"])
    ],
    targets: [
        // C bridge — exposes bare-kit Linux headers to Swift
        .systemLibrary(
            name: "CBareKit",
            path: "Sources/CBareKit",
            pkgConfig: nil,
            providers: []
        ),

        // Clean Swift API — mirrors bare-kit-swift on iOS/macOS
        .target(
            name: "BareKit",
            dependencies: ["CBareKit"],
            path: "Sources/BareKit",
            swiftSettings: [
                .unsafeFlags([
                    "-Xcc", "-I\(bareSDK)/include",
                    "-Xcc", "-I\(bareSDK)/include/linux",
                    "-Xcc", "-I\(bareSDK)/include/posix",
                    "-Xcc", "-DBARE_KIT_LINUX",
                ])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-L\(bareSDK)/lib",
                    "-lbare-kit",
                    "-luv",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "\(bareSDK)/lib",
                    "-lpthread", "-ldl", "-lm", "-lstdc++",
                ])
            ]
        ),
    ]
)
