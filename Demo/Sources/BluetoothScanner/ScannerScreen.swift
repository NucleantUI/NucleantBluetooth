//
//  ScannerScreen.swift
//  BluetoothScanner
//
//  The devices around: one row each, with name, maker, services and signal.
//  Scanning starts when the screen appears and keeps every advertisement,
//  so the signal stays live. A row opens the device's screen.
//

import NucleantBluetooth
import NucleantUI

/// The order the rows are in.
enum ScanOrder {
    /// As they were found: rows stay put.
    case found
    /// Strongest signal first.
    case signal
}

@View
struct ScannerScreen {
    @Environment(\.bluetoothManager) private var ble
    @State private var namedOnly = false
    @State private var order = ScanOrder.found

    var body: some View {
        let shown = visiblePeripherals
        VStack(spacing: 0) {
            if ble.state != .poweredOn {
                StateBanner(state: ble.state)
            }
            ScanHeader(count: shown.count, total: ble.peripherals.count, isScanning: ble.isScanning)
            if shown.isEmpty {
                EmptyScan(isScanning: ble.isScanning, namedOnly: namedOnly)
            } else {
                List(shown) { peripheral in
                    NavigationLink(title: peripheral.displayName) {
                        PeripheralScreen(peripheral: peripheral)
                    } label: {
                        PeripheralRow(peripheral: peripheral)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(ble.isScanning ? "Stop" : "Scan") {
                    if ble.isScanning {
                        ble.stopScan()
                    } else {
                        ble.scan(allowDuplicates: true)
                    }
                }
                .disabled(ble.state != .poweredOn)
            }
            ToolbarItem(placement: .secondaryAction) {
                Button(namedOnly ? "Show unnamed devices" : "Hide unnamed devices") {
                    namedOnly.toggle()
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button(order == .found ? "Sort by signal" : "Sort as found") {
                    order = order == .found ? .signal : .found
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button("Clear list") { ble.removeDisconnectedPeripherals() }
            }
        }
        .onAppear { ble.scan(allowDuplicates: true) }
    }

    var visiblePeripherals: [BluetoothPeripheral] {
        var shown = ble.peripherals
        if namedOnly {
            shown = shown.filter { $0.localName != nil || $0.name != nil }
        }
        if order == .signal {
            shown.sort { ($0.rssi?.rawValue ?? -128) > ($1.rssi?.rawValue ?? -128) }
        }
        return shown
    }
}

/// Why nothing can be scanned, while Bluetooth is not on.
@View
struct StateBanner {
    let state: BluetoothState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(detail).font(.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(hex: 0xFFB020).opacity(0.18))
    }

    var title: String {
        switch state {
        case .unknown: "Starting Bluetooth…"
        case .resetting: "Bluetooth is restarting…"
        case .unsupported: "No Bluetooth Low Energy"
        case .unauthorized: "Bluetooth isn't allowed"
        case .poweredOff: "Bluetooth is off"
        case .poweredOn: "Bluetooth is on"
        }
    }

    var detail: String {
        switch state {
        case .unknown, .resetting: "Waiting for the system."
        case .unsupported: "This device can't scan for Bluetooth Low Energy devices."
        case .unauthorized: "Allow Bluetooth for this app in Settings."
        case .poweredOff: "Turn Bluetooth on in Settings or Control Center. Scanning starts when it is on."
        case .poweredOn: ""
        }
    }
}

@View
struct ScanHeader {
    let count: Int
    let total: Int
    let isScanning: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isScanning ? Color(hex: 0x3DD68C) : Color(white: 0.6))
                .frame(width: 8, height: 8)
            Text(isScanning ? "Scanning" : "Not scanning")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            Text(count == total ? "\(total) devices" : "\(count) of \(total) devices")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(horizontal: 16, vertical: 10)
    }
}

@View
struct EmptyScan {
    let isScanning: Bool
    let namedOnly: Bool

    var body: some View {
        VStack(spacing: 8) {
            Text(isScanning ? "Looking for devices…" : "No devices")
                .font(.headline)
            Text(namedOnly
                 ? "Unnamed devices are hidden; the toolbar's menu shows them."
                 : "Devices advertising nearby show up here.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@View
struct PeripheralRow {
    let peripheral: BluetoothPeripheral

    var body: some View {
        HStack(spacing: 12) {
            SignalBars(filled: signalBars(peripheral.rssi))
            VStack(alignment: .leading, spacing: 2) {
                Text(peripheral.displayName)
                    .font(.headline)
                    .foregroundStyle(peripheral.localName == nil && peripheral.name == nil ? .secondary : .primary)
                    .lineLimit(1)
                Text(peripheral.summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if peripheral.connectionState == .connected {
                Text("Connected")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(horizontal: 8, vertical: 3)
                    .background(Color(hex: 0x3D7DFF))
                    .cornerRadius(8)
            }
            Text(peripheral.rssi.map { "\($0.rawValue) dBm" } ?? "—")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.secondary)
            Text("›")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
        }
        .padding(vertical: 6)
    }
}

/// Four bars, `filled` of them lit.
@View
struct SignalBars {
    let filled: Int

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<4, id: \.self) { bar in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(bar < filled ? AnyShapeStyle(Color(hex: 0x3D7DFF)) : AnyShapeStyle(Color(white: 0.5, opacity: 0.3)))
                    .frame(width: 4, height: Double(5 + bar * 4))
            }
        }
        .frame(width: 22, height: 18, alignment: .bottom)
    }
}
