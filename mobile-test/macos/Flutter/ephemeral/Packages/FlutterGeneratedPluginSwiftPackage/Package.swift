// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.
//
// Generated file. Do not edit.
//

import PackageDescription

let package = Package(
    name: "FlutterGeneratedPluginSwiftPackage",
    platforms: [
        .macOS("12.0")
    ],
    products: [
        .library(name: "FlutterGeneratedPluginSwiftPackage", type: .static, targets: ["FlutterGeneratedPluginSwiftPackage"])
    ],
    dependencies: [
        .package(name: "audioplayers_darwin", path: "../.packages/audioplayers_darwin-6.5.0"),
        .package(name: "file_picker", path: "../.packages/file_picker-10.3.10"),
        .package(name: "flutter_webrtc", path: "../.packages/flutter_webrtc-1.6.2+hotfix.4"),
        .package(name: "shared_preferences_foundation", path: "../.packages/shared_preferences_foundation-2.5.7"),
        .package(name: "speech_to_text", path: "../.packages/speech_to_text-7.4.0"),
        .package(name: "FlutterFramework", path: "../.packages/FlutterFramework")
    ],
    targets: [
        .target(
            name: "FlutterGeneratedPluginSwiftPackage",
            dependencies: [
                .product(name: "audioplayers-darwin", package: "audioplayers_darwin"),
                .product(name: "file-picker", package: "file_picker"),
                .product(name: "flutter-webrtc", package: "flutter_webrtc"),
                .product(name: "shared-preferences-foundation", package: "shared_preferences_foundation"),
                .product(name: "speech-to-text", package: "speech_to_text"),
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ]
        )
    ]
)
