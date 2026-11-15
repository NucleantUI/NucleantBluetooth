//
//  BluetoothCharacteristic.swift
//  NucleantBluetooth
//
//  A characteristic of a service: a value to read, write or be notified of.
//

import Foundation
import Observation

/// A characteristic of a service, found by
/// `BluetoothService.discoverCharacteristics(_:)`.
@Observable
public final class BluetoothCharacteristic: Identifiable, @unchecked Sendable {

    /// What the characteristic is: `uuid.metadata?.name` is its assigned
    /// name ("Battery Level", "Manufacturer Name String") when it is a
    /// standard one.
    public let uuid: BluetoothUUID

    /// What can be done with it: read, write, notify, …
    public let properties: GATTCharacteristicProperties

    /// The value last read or notified; `nil` before the first.
    public internal(set) var value: Data?

    /// Whether the device sends the value each time it changes.
    public internal(set) var isNotifying = false

    /// The last request on this characteristic that failed. Cleared by the
    /// next one that succeeds.
    public internal(set) var error: BluetoothError?

    /// The service it belongs to.
    @ObservationIgnored public private(set) weak var service: BluetoothService?

    @ObservationIgnored let native: BluetoothCentral.NativeCharacteristic

    init(
        native: BluetoothCentral.NativeCharacteristic,
        uuid: BluetoothUUID,
        properties: GATTCharacteristicProperties,
        service: BluetoothService
    ) {
        self.native = native
        self.uuid = uuid
        self.properties = properties
        self.service = service
    }

    /// `value` decoded as `T` — PureSwift's GATT types, such as
    /// `GATTBatteryLevel`. `nil` when there is no value yet, when this is not
    /// `T`'s characteristic, or when the bytes are not a `T`.
    public func value<T: GATTCharacteristic>(as type: T.Type) -> T? {
        guard uuid == T.uuid, let value else { return nil }
        return T(data: value)
    }

    // MARK: - Requests

    /// Read the value into `value`.
    public func read() {
        guard let central else { return }
        central.read(self)
    }

    /// Write `value`. With a response, the device confirms it, and a
    /// failure lands in `error`; without, it is sent and not confirmed.
    public func write(_ value: Data, withResponse: Bool = true) {
        guard let central else { return }
        central.write(value, to: self, withResponse: withResponse)
    }

    /// Have the device send the value each time it changes, or stop.
    /// `isNotifying` follows once the device agrees.
    public func setNotifying(_ enabled: Bool) {
        guard let central else { return }
        central.setNotifying(enabled, for: self)
    }

    /// The central of the manager listing this characteristic's peripheral,
    /// while it is connected.
    private var central: BluetoothCentral? {
        guard let peripheral = service?.peripheral, peripheral.connectionState == .connected else { return nil }
        return peripheral.manager?.central
    }
}
