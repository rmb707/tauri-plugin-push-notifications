// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "tauri-plugin-push-notifications",
    platforms: [
        .iOS(.v14),
    ],
    products: [
        .library(
            name: "tauri-plugin-push-notifications",
            type: .static,
            targets: ["tauri-plugin-push-notifications"]
        ),
    ],
    dependencies: [
        .package(name: "Tauri", path: "../.tauri/tauri-api"),
    ],
    targets: [
        .target(
            name: "tauri-plugin-push-notifications",
            dependencies: [
                .byName(name: "Tauri"),
            ],
            path: "Sources"
        ),
    ]
)
