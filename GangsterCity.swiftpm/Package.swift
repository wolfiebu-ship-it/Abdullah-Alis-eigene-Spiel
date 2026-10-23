// swift-tools-version: 5.9

// Dieses Paket ist ein "App Playground": Es lässt sich direkt in
// Swift Playgrounds (iPad / Mac) oder in Xcode 15+ öffnen und starten.

import PackageDescription
import AppleProductTypes

let package = Package(
    name: "GangsterCity",
    platforms: [
        .iOS("17.0")
    ],
    products: [
        .iOSApplication(
            name: "Gangster City",
            targets: ["AppModule"],
            bundleIdentifier: "com.abdullahali.gangstercity",
            teamIdentifier: "",
            displayVersion: "1.0",
            bundleVersion: "1",
            appIcon: .placeholder(icon: .car),
            accentColor: .presetColor(.orange),
            supportedDeviceFamilies: [
                .pad,
                .phone
            ],
            supportedInterfaceOrientations: [
                .landscapeRight,
                .landscapeLeft
            ]
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: "."
        )
    ]
)
