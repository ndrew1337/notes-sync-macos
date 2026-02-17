// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "notes_sync_app",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "notes_sync_app", targets: ["notes_sync_app"])
    ],
    targets: [
        .executableTarget(
            name: "notes_sync_app",
            path: "Sources"
        )
    ]
)
