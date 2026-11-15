// swift-tools-version: 6.2

import Foundation
import PackageDescription

/// Build against the sibling checkout (`../NucleantUI`) or against its
/// releases on GitHub.
///
/// GitHub unless `NUCLEANT_LOCAL_DEV=1` is in the environment: the sibling
/// checkout is used only when that turns it on, never just because it is
/// there.
let devMode: Bool = ["1", "true", "yes"].contains(
    (ProcessInfo.processInfo.environment["NUCLEANT_LOCAL_DEV"] ?? "").lowercased()
)

func nucleantUI() -> Package.Dependency {
    if devMode {
        return .package(path: "../NucleantUI")
    }
    // By version, up to its next minor: its new 0.3.x releases are picked up
    // as they come; its 0.4.0 only once this line is moved to it.
    return .package(url: "https://github.com/NucleantUI/NucleantUI.git", .upToNextMinor(from: "0.3.1"))
}

let package = Package(
    name: "NucleantBluetooth",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "NucleantBluetooth", targets: ["NucleantBluetooth"]),
    ],
    dependencies: [
        nucleantUI(),
        // PureSwift's Bluetooth types: UUIDs, RSSI, company identifiers,
        // GAP advertising data and GATT definitions. `Metadata` adds the
        // assigned-numbers names (`uuid.metadata?.name`, `company.name`).
        .package(url: "https://github.com/PureSwift/Bluetooth.git", from: "8.2.1", traits: ["Metadata"]),
    ],
    targets: [
        .target(
            name: "NucleantBluetooth",
            dependencies: [
                .product(name: "Bluetooth", package: "Bluetooth"),
                .product(name: "BluetoothGAP", package: "Bluetooth"),
                .product(name: "BluetoothGATT", package: "Bluetooth"),
                .product(name: "NucleantUI", package: "NucleantUI"),
            ]
        ),
        .testTarget(
            name: "NucleantBluetoothTests",
            dependencies: [
                "NucleantBluetooth",
                .product(name: "NucleantUI", package: "NucleantUI"),
            ]
        ),
    ]
)
