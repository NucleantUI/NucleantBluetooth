//
//  BluetoothCentral.swift
//  NucleantBluetooth
//
//  What each platform's central does. Every platform file defines one
//  `BluetoothCentral` conforming to this — `BluetoothCentral+iOS.swift` over
//  CoreBluetooth — so the shared classes call it, and name its native
//  objects, without an `#if`.
//
//  The central asks the system; the answers come back as calls on the
//  shared classes (`stateDidChange`, `didConnect`, …), which are what views
//  observe.
//

import Foundation

protocol BluetoothCentralPlatform: AnyObject {

    /// The system's object for a remote device.
    associatedtype NativePeripheral: AnyObject
    /// The system's object for a service on a remote device.
    associatedtype NativeService: AnyObject
    /// The system's object for a characteristic of a service.
    associatedtype NativeCharacteristic: AnyObject

    /// The central for `manager`, which owns it. The system reports its
    /// state some time after.
    init(manager: BluetoothManager)

    func scan(services: [BluetoothUUID]?, allowDuplicates: Bool)
    func stopScan()

    func connect(_ peripheral: BluetoothPeripheral)
    func disconnect(_ peripheral: BluetoothPeripheral)
    func readRSSI(of peripheral: BluetoothPeripheral)
    func discoverServices(_ uuids: [BluetoothUUID]?, of peripheral: BluetoothPeripheral)

    func discoverCharacteristics(_ uuids: [BluetoothUUID]?, of service: BluetoothService)

    func read(_ characteristic: BluetoothCharacteristic)
    func write(_ value: Data, to characteristic: BluetoothCharacteristic, withResponse: Bool)
    func setNotifying(_ enabled: Bool, for characteristic: BluetoothCharacteristic)
}
