//
//  BluetoothManager.swift
//  NucleantBluetooth
//
//  The app's side of Bluetooth Low Energy as a central: whether Bluetooth
//  can be used, scanning, and every peripheral found.
//

import Foundation
import Observation

/// Whether Bluetooth can be used right now.
public enum BluetoothState: Int, Sendable {
    /// Not known yet: the system has not answered.
    case unknown = 0
    /// The connection to the system's Bluetooth service was lost and is
    /// being set up again.
    case resetting = 1
    /// This device has no Bluetooth Low Energy.
    case unsupported = 2
    /// The app may not use Bluetooth: the user said no, or it is restricted.
    case unauthorized = 3
    /// Bluetooth is turned off.
    case poweredOff = 4
    /// Bluetooth is on and can be used.
    case poweredOn = 5
}

/// Bluetooth Low Energy as a central: scans for the peripherals around and
/// keeps one `BluetoothPeripheral` for each device found.
///
/// Views reach it with `@Environment(\.bluetoothManager)`. It is
/// `@Observable`: a view rebuilds for the properties it read — a list of
/// `peripherals` for a new one, a view of one peripheral for its own
/// signal. Create
/// and use it on the main thread; the system's answers arrive there too.
/// Making one asks the system for Bluetooth, which is when the user is asked
/// for permission the first time.
@Observable
public final class BluetoothManager: @unchecked Sendable {

    /// Whether Bluetooth can be used. `.unknown` until the system answers,
    /// soon after the manager is made.
    public internal(set) var state = BluetoothState.unknown

    /// Whether a scan is running. A scan asked for while Bluetooth is not on
    /// is not running yet: it starts once Bluetooth is on.
    public internal(set) var isScanning = false

    /// Every peripheral found, in the order they were found. A device found
    /// again — another advertisement, a new scan — updates its peripheral
    /// instead of adding one.
    public internal(set) var peripherals: [BluetoothPeripheral] = []

    /// The scan asked for, kept while Bluetooth is off so it can start (or
    /// start again) once it is on.
    @ObservationIgnored private var scanRequest: (services: [BluetoothUUID]?, allowDuplicates: Bool)?

    @ObservationIgnored private var peripheralsByID: [UUID: BluetoothPeripheral] = [:]

    @ObservationIgnored private(set) var central: BluetoothCentral!

    public init() {
        central = BluetoothCentral(manager: self)
    }

    // MARK: - Scanning

    /// Look for peripherals advertising any of `services`, or every
    /// peripheral when it is `nil`.
    ///
    /// With `allowDuplicates`, every advertisement a device sends is taken,
    /// so its signal strength stays current; without, the system reports a
    /// device about once per scan. Asked before Bluetooth is on, the scan
    /// starts when it is. A scan already running is replaced.
    public func scan(for services: [BluetoothUUID]? = nil, allowDuplicates: Bool = false) {
        scanRequest = (services, allowDuplicates)
        guard state == .poweredOn else { return }
        central.scan(services: services, allowDuplicates: allowDuplicates)
        isScanning = true
    }

    /// Stop scanning, and forget a scan that was waiting for Bluetooth.
    public func stopScan() {
        scanRequest = nil
        guard isScanning else { return }
        central.stopScan()
        isScanning = false
    }

    /// Drop the peripherals that are not connected or connecting. A device
    /// still around is added again when it next advertises.
    public func removeDisconnectedPeripherals() {
        peripherals.removeAll { peripheral in
            guard peripheral.connectionState == .disconnected else { return false }
            peripheralsByID[peripheral.id] = nil
            return true
        }
    }

    // MARK: - From the platform

    /// The system's Bluetooth turned on or off, or told the app what it may
    /// do. Off ends every connection.
    func stateDidChange(_ newState: BluetoothState) {
        guard newState != state else { return }
        state = newState
        if newState == .poweredOn {
            if let scanRequest {
                central.scan(services: scanRequest.services, allowDuplicates: scanRequest.allowDuplicates)
                isScanning = true
            }
        } else {
            isScanning = false
            for peripheral in peripherals where peripheral.connectionState != .disconnected {
                peripheral.didDisconnect(error: nil)
            }
        }
    }

    /// The peripheral for the device with `id`, added when it is new. A
    /// device the system hands a new object for — after Bluetooth was off —
    /// keeps its peripheral, which takes the new object.
    func peripheral(_ id: UUID, native: BluetoothCentral.NativePeripheral) -> BluetoothPeripheral {
        if let known = peripheralsByID[id] {
            if known.native !== native {
                known.native = native
            }
            return known
        }
        let found = BluetoothPeripheral(id: id, native: native, manager: self)
        peripheralsByID[id] = found
        peripherals.append(found)
        return found
    }

    /// The peripheral for the device with `id`, if it was found.
    func knownPeripheral(_ id: UUID) -> BluetoothPeripheral? {
        peripheralsByID[id]
    }
}
