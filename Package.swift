import Foundation
import PackageDescription

let bareSDK =
    ProcessInfo.processInfo.environment["BARE_SDK_DIR"]
    ?? "\(Context.packageDirectory)/bare-sdk"

let package = Package(
    name: "BareKitLinux",
    products: [
        .library(name: "BareKitLinux", targets: ["BareKit"])
    ],
    targets: [
        .systemLibrary(
            name: "CBareKit",
            path: "Sources/CBareKit",
            pkgConfig: nil,
            providers: []
        ),
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
