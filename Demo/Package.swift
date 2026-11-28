// swift-tools-version: 6.3

import Foundation
import PackageDescription

// The NucleantBluetooth demo: a Bluetooth Low Energy scanner, built on the
// enclosing package. Its own package, so NucleantBluetooth itself has no
// UI. Built as an iOS app by Xcode/project.yml.

/// The same switch as NucleantBluetooth's own manifest: both have to take
/// NucleantUI from the same place.
let devMode: Bool = ["1", "true", "yes"].contains(
    (ProcessInfo.processInfo.environment["NUCLEANT_LOCAL_DEV"] ?? "").lowercased()
)

func nucleantUI() -> Package.Dependency {
    if devMode {
        return .package(path: "../../NucleantUI")
    }
    return .package(url: "https://github.com/NucleantUI/NucleantUI.git", .upToNextMinor(from: "0.3.1"))
}

let package = Package(
    name: "BluetoothScanner",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    dependencies: [
        .package(path: ".."),
        nucleantUI(),
    ],
    targets: [
        .executableTarget(
            name: "BluetoothScanner",
            dependencies: [
                .product(name: "NucleantBluetooth", package: "NucleantBluetooth"),
                .product(name: "NucleantUI", package: "NucleantUI"),
            ]
        ),
    ]
)
