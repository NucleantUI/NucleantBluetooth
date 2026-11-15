//
//  BluetoothScannerApp.swift
//  BluetoothScanner
//
//  A Bluetooth Low Energy scanner on NucleantBluetooth: the devices around
//  with their live signal strength, and a screen per device with what it
//  advertises and, once connected, its services and characteristics — read,
//  write and notify.
//
//  Everything comes from `@Environment(\.bluetoothManager)`; the rows and
//  screens take the peripheral or characteristic they show as a plain `let`
//  and rebuild for what they read of it.
//
//  An iOS app: Demo/Xcode/BluetoothScanner.xcodeproj, scheme
//  BluetoothScannerApp.
//

import NucleantBluetooth
import NucleantUI

@main
struct BluetoothScannerApp: NucleantApp {
    var body: some Scene {
        WindowGroup("Bluetooth Scanner") {
            NavigationStack("Nearby") {
                ScannerScreen()
            }
            // The framework's surface color, so the page is drawn in the
            // same appearance as its text.
            .background(BackgroundStyle.background)
        }
        .defaultSize(width: 430, height: 860)
    }
}
