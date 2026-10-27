// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "StandbyLock",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "StandbyLock",
            path: "Sources/StandbyLock",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
