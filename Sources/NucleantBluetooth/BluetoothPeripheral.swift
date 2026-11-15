//
//  BluetoothPeripheral.swift
//  NucleantBluetooth
//
//  A remote device: what it advertises, and once connected, its services.
//

import Foundation
import Observation

/// Where a peripheral's connection is.
public enum BluetoothConnectionState: Int, Sendable {
    case disconnected = 0
    case connecting = 1
    case connected = 2
    case disconnecting = 3
}

/// A device found by `BluetoothManager`. There is one for each device, kept
/// for as long as the manager lists it, so a view can hold on to it and
/// rebuild for the properties it read as they change.
///
/// What a device advertises comes in more than one packet — the
/// advertisement, the scan response — and not every packet carries every
/// field. A packet without a field keeps the value the last one gave.
@Observable
public final class BluetoothPeripheral: Identifiable, @unchecked Sendable {

    /// The system's identifier for the device. Stable on this device, not
    /// across devices; it is not the device's address.
    public let id: UUID

    /// The device's name as the system knows it (its GAP device name), if it
    /// has one.
    public internal(set) var name: String?

    /// The signal strength of the last advertisement, or of `readRSSI()`
    /// while connected. `nil` when the system could not tell.
    public internal(set) var rssi: RSSI?

    /// When the device last advertised; `nil` if it hasn't since it was
    /// listed.
    public internal(set) var lastSeen: Date?

    // MARK: Advertisement

    /// The name the device advertises.
    public internal(set) var localName: String?

    /// The manufacturer's data: who made the device, and bytes only they
    /// define.
    public internal(set) var manufacturerData: GAPManufacturerSpecificData<Data>?

    /// The services the device says it has.
    public internal(set) var serviceUUIDs: [BluetoothUUID] = []

    /// Data the device advertises for a service, by the service's UUID.
    public internal(set) var serviceData: [BluetoothUUID: Data] = [:]

    /// The power the device sends at, for telling distance from `rssi`.
    public internal(set) var txPowerLevel: GAPTxPowerLevel?

    /// Whether the device accepts connections, when it says.
    public internal(set) var isConnectable: Bool?

    // MARK: Connection

    public internal(set) var connectionState = BluetoothConnectionState.disconnected

    /// The services found by `discoverServices(_:)`. Emptied when the
    /// connection ends: services found on one connection can't be used on
    /// the next.
    public internal(set) var services: [BluetoothService] = []

    /// The last request on this peripheral that failed, or a connection that
    /// was lost. Cleared by the next `connect()`.
    public internal(set) var error: BluetoothError?

    /// The manager that lists it.
    @ObservationIgnored public private(set) weak var manager: BluetoothManager?

    @ObservationIgnored var native: BluetoothCentral.NativePeripheral

    init(id: UUID, native: BluetoothCentral.NativePeripheral, manager: BluetoothManager) {
        self.id = id
        self.native = native
        self.manager = manager
    }

    // MARK: - Requests

    /// Connect to the device. Needs Bluetooth on; does nothing while
    /// connected or connecting.
    public func connect() {
        guard connectionState == .disconnected, let manager, manager.state == .poweredOn else { return }
        error = nil
        connectionState = .connecting
        manager.central.connect(self)
    }

    /// End the connection, or stop connecting.
    public func disconnect() {
        guard connectionState == .connecting || connectionState == .connected, let manager else { return }
        connectionState = .disconnecting
        manager.central.disconnect(self)
    }

    /// Find the device's services with any of `uuids`, or all of them when
    /// it is `nil`, into `services`. Needs a connection.
    public func discoverServices(_ uuids: [BluetoothUUID]? = nil) {
        guard connectionState == .connected, let manager else { return }
        manager.central.discoverServices(uuids, of: self)
    }

    /// Read the signal strength of the connection into `rssi`.
    public func readRSSI() {
        guard connectionState == .connected, let manager else { return }
        manager.central.readRSSI(of: self)
    }

    // MARK: - From the platform

    /// Sets `keyPath` only when the value differs, so the views that read it
    /// are not rebuilt for an advertisement that repeats it.
    func update<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<BluetoothPeripheral, Value>, _ value: Value) {
        if self[keyPath: keyPath] != value {
            self[keyPath: keyPath] = value
        }
    }

    func didConnect() {
        connectionState = .connected
        error = nil
    }

    func didFailToConnect(_ error: BluetoothError) {
        connectionState = .disconnected
        self.error = error
    }

    /// The connection ended: asked for when `error` is `nil`.
    func didDisconnect(error: BluetoothError?) {
        connectionState = .disconnected
        services = []
        if let error {
            self.error = error
        }
    }

    /// The service for the system's `native` one, if it was discovered.
    func service(for native: BluetoothCentral.NativeService) -> BluetoothService? {
        services.first { $0.native === native }
    }

    /// The characteristic for the system's `native` one, in whichever
    /// service has it.
    func characteristic(for native: BluetoothCentral.NativeCharacteristic) -> BluetoothCharacteristic? {
        for service in services {
            if let characteristic = service.characteristic(for: native) {
                return characteristic
            }
        }
        return nil
    }
}
