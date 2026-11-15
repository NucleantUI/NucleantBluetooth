//
//  BluetoothService.swift
//  NucleantBluetooth
//
//  A service on a connected peripheral, and its characteristics.
//

import Foundation
import Observation

/// A service a connected peripheral has, found by
/// `BluetoothPeripheral.discoverServices(_:)`.
@Observable
public final class BluetoothService: Identifiable, @unchecked Sendable {

    /// What the service is: `uuid.metadata?.name` is its assigned name
    /// ("Battery", "Heart Rate") when it is a standard one.
    public let uuid: BluetoothUUID

    /// Whether it is one of the device's primary services, rather than one
    /// only another service includes.
    public let isPrimary: Bool

    /// The characteristics found by `discoverCharacteristics(_:)`.
    public internal(set) var characteristics: [BluetoothCharacteristic] = []

    /// The last request on this service that failed.
    public internal(set) var error: BluetoothError?

    /// The peripheral it is on.
    @ObservationIgnored public private(set) weak var peripheral: BluetoothPeripheral?

    @ObservationIgnored let native: BluetoothCentral.NativeService

    init(native: BluetoothCentral.NativeService, uuid: BluetoothUUID, isPrimary: Bool, peripheral: BluetoothPeripheral) {
        self.native = native
        self.uuid = uuid
        self.isPrimary = isPrimary
        self.peripheral = peripheral
    }

    /// Find the service's characteristics with any of `uuids`, or all of
    /// them when it is `nil`, into `characteristics`.
    public func discoverCharacteristics(_ uuids: [BluetoothUUID]? = nil) {
        guard let peripheral, peripheral.connectionState == .connected, let manager = peripheral.manager else { return }
        manager.central.discoverCharacteristics(uuids, of: self)
    }

    /// The characteristic for the system's `native` one, if it was
    /// discovered.
    func characteristic(for native: BluetoothCentral.NativeCharacteristic) -> BluetoothCharacteristic? {
        characteristics.first { $0.native === native }
    }
}
