//
//  PeripheralScreen.swift
//  BluetoothScanner
//
//  One device: what it advertises, its connection, and once connected its
//  services. Connecting discovers the services, each new service discovers
//  its characteristics, and each readable characteristic reads its value
//  when it shows.
//
//  The sections are written straight into the Form, which finds its rows by
//  walking its content: a view of our own is one row. The values that
//  change with every advertisement — the signal, when it was last seen —
//  are rows of their own, so only they rebuild for each packet.
//

import Foundation
import NucleantBluetooth
import NucleantUI

@View
struct PeripheralScreen {
    let peripheral: BluetoothPeripheral

    var body: some View {
        Form {
            Section("Connection") {
                LabeledContent("State", value: stateName)
                SignalRow(peripheral: peripheral)
                if let error = peripheral.error {
                    ErrorText(error: error)
                }
                if peripheral.connectionState == .connected {
                    Button("Read signal strength") { peripheral.readRSSI() }
                }
            }

            Section("Advertisement") {
                LabeledContent("Local name", value: peripheral.localName ?? "None")
                LabeledContent("Device name", value: peripheral.name ?? "None")
                LabeledContent("Connectable", value: connectable)
                if let power = peripheral.txPowerLevel {
                    LabeledContent("Transmit power", value: "\(power.powerLevel) dBm")
                }
                if let maker = peripheral.manufacturerData {
                    LabeledContent(
                        "Manufacturer",
                        value: maker.companyIdentifier.name ?? "Company \(maker.companyIdentifier.rawValue)"
                    )
                    if !maker.additionalData.isEmpty {
                        ValueText(label: "Manufacturer data", text: maker.additionalData.hex)
                    }
                }
                ForEach(peripheral.serviceUUIDs, id: \.self) { uuid in
                    LabeledContent("Service", value: uuid.displayName)
                }
                ForEach(serviceData, id: \.0) { uuid, data in
                    ValueText(label: "Data for \(uuid.displayName)", text: data.hex)
                }
                LastSeenRow(peripheral: peripheral)
                ValueText(label: "Identifier", text: peripheral.id.uuidString)
            }

            if peripheral.connectionState == .connected {
                if peripheral.services.isEmpty {
                    Section("Services") {
                        Text("Discovering services…").foregroundStyle(.secondary)
                    }
                }
                ForEach(peripheral.services) { service in
                    Section(service.uuid.displayName) {
                        if service.uuid.metadata != nil {
                            ValueText(label: "UUID", text: service.uuid.description)
                        }
                        if let error = service.error {
                            ErrorText(error: error)
                        }
                        if service.characteristics.isEmpty {
                            Text("Discovering characteristics…").foregroundStyle(.secondary)
                        }
                        ForEach(service.characteristics) { characteristic in
                            CharacteristicRow(characteristic: characteristic)
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                switch peripheral.connectionState {
                case .disconnected:
                    Button("Connect") { peripheral.connect() }
                        .disabled(peripheral.isConnectable == false)
                case .connecting, .connected:
                    Button("Disconnect") { peripheral.disconnect() }
                case .disconnecting:
                    Button("Disconnecting…") {}
                        .disabled(true)
                }
            }
        }
        .onChange(of: peripheral.connectionState) { _, state in
            if state == .connected {
                peripheral.discoverServices()
                peripheral.readRSSI()
            }
        }
        .onChange(of: peripheral.services.map(\.id)) {
            for service in peripheral.services where service.characteristics.isEmpty {
                service.discoverCharacteristics()
            }
        }
    }

    var stateName: String {
        switch peripheral.connectionState {
        case .disconnected: "Not connected"
        case .connecting: "Connecting…"
        case .connected: "Connected"
        case .disconnecting: "Disconnecting…"
        }
    }

    var connectable: String {
        switch peripheral.isConnectable {
        case true?: "Yes"
        case false?: "No"
        case nil: "Not advertised"
        }
    }

    /// In a fixed order, so the rows don't move between advertisements.
    var serviceData: [(BluetoothUUID, Data)] {
        peripheral.serviceData
            .map { ($0.key, $0.value) }
            .sorted { $0.0.description < $1.0.description }
    }
}

/// The signal strength, which changes with every advertisement.
@View
struct SignalRow {
    let peripheral: BluetoothPeripheral

    var body: some View {
        HStack(spacing: 8) {
            Text("Signal")
            Spacer()
            SignalBars(filled: signalBars(peripheral.rssi))
            Text(peripheral.rssi.map { "\($0.rawValue) dBm" } ?? "Unknown")
                .foregroundStyle(.secondary)
        }
    }
}

/// When the device last advertised, which changes with every advertisement.
@View
struct LastSeenRow {
    let peripheral: BluetoothPeripheral

    var body: some View {
        HStack {
            Text("Last seen")
            Spacer()
            Text(peripheral.lastSeen.map { $0.formatted(date: .omitted, time: .standard) } ?? "Not since listed")
                .foregroundStyle(.secondary)
        }
    }
}

@View
struct ErrorText {
    let error: BluetoothError

    var body: some View {
        Text(error.description)
            .font(.footnote)
            .foregroundStyle(Color(hex: 0xE5484D))
    }
}

/// A label over a value in monospaced type: bytes, identifiers.
@View
struct ValueText {
    let label: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 13, design: .monospaced))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A characteristic: what it is, what it allows, its value, and the
/// controls for what it allows — read, notify, write as hex or text.
@View
struct CharacteristicRow {
    let characteristic: BluetoothCharacteristic
    @State private var draft = ""
    @State private var draftIsText = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(characteristic.uuid.displayName).font(.headline)
                if characteristic.uuid.metadata != nil {
                    Text(characteristic.uuid.description)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Text(characteristic.properties.names)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let value = characteristic.value {
                if let meaning = meaning(of: value) {
                    Text(meaning)
                }
                ValueText(label: "\(value.count) bytes", text: value.isEmpty ? "Empty" : value.hex)
            }

            if let error = characteristic.error {
                ErrorText(error: error)
            }

            HStack(spacing: 12) {
                if characteristic.properties.contains(.read) {
                    Button("Read") { characteristic.read() }
                }
                if canNotify {
                    Toggle("Notify", isOn: Binding(
                        get: { characteristic.isNotifying },
                        set: { characteristic.setNotifying($0) }
                    ))
                }
            }

            if canWrite {
                HStack(spacing: 8) {
                    TextField(draftIsText ? "Text" : "Hex, e.g. 01 FF", text: $draft)
                    Button(draftIsText ? "Hex" : "Text") { draftIsText.toggle() }
                    Button("Write") { write() }
                        .disabled(bytes == nil)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(vertical: 4)
        .onAppear {
            if characteristic.properties.contains(.read), characteristic.value == nil {
                characteristic.read()
            }
        }
    }

    var canNotify: Bool {
        characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate)
    }

    var canWrite: Bool {
        characteristic.properties.contains(.write) || characteristic.properties.contains(.writeWithoutResponse)
    }

    /// What the draft says as bytes; `nil` while it isn't valid hex.
    var bytes: Data? {
        draftIsText ? (draft.isEmpty ? nil : Data(draft.utf8)) : Data(hexDigits: draft)
    }

    func write() {
        guard let bytes else { return }
        characteristic.write(bytes, withResponse: characteristic.properties.contains(.write))
        draft = ""
    }

    /// The value read as what it is, where that is known: a battery level,
    /// or text.
    func meaning(of value: Data) -> String? {
        if let battery = characteristic.value(as: GATTBatteryLevel.self) {
            return "\(battery.level.rawValue) %"
        }
        return value.printableText.map { "“\($0)”" }
    }
}
