//
//  AdvertisingData.swift
//  NucleantBluetooth
//
//  An advertising packet as the bytes the device sent, for the platforms
//  that hand those over (Android's ScanRecord). CoreBluetooth reads them
//  itself and gives a dictionary instead.
//

import Foundation

/// What one advertising packet says, read from its bytes: the advertising
/// data's structures, each a length, a type and a value (Core Specification,
/// Vol 3, Part C, §11), with any zero padding after them.
///
/// A field the packet leaves out is `nil`, so taking it leaves the
/// peripheral's value as it was.
struct AdvertisingData {
    var localName: String?
    var manufacturerData: GAPManufacturerSpecificData<Data>?
    var serviceUUIDs: [BluetoothUUID]?
    var serviceData: [BluetoothUUID: Data]?
    var txPowerLevel: GAPTxPowerLevel?

    init(_ data: Data) {
        let bytes = [UInt8](data)
        var completeName: String?
        var shortName: String?
        var offset = 0
        while offset < bytes.count {
            let length = Int(bytes[offset])
            // A zero length is the padding after the last structure; one
            // that runs past the end is cut off, and so is what follows it.
            guard length > 0, offset + length < bytes.count else { break }
            let type = GAPDataType(rawValue: bytes[offset + 1])
            let value = Data(bytes[(offset + 2)..<(offset + 1 + length)])
            offset += 1 + length

            switch type {
            case .completeLocalName:
                completeName = GAPCompleteLocalName(data: value)?.name
            case .shortLocalName:
                shortName = GAPShortLocalName(data: value)?.name
            case .manufacturerSpecificData:
                manufacturerData = GAPManufacturerSpecificData<Data>(data: value) ?? manufacturerData
            case .txPowerLevel:
                txPowerLevel = GAPTxPowerLevel(data: value) ?? txPowerLevel
            case .incompleteListOf16BitServiceClassUUIDs:
                add(GAPIncompleteListOf16BitServiceClassUUIDs(data: value)?.uuids.map(BluetoothUUID.bit16))
            case .completeListOf16CitServiceClassUUIDs:
                add(GAPCompleteListOf16BitServiceClassUUIDs(data: value)?.uuids.map(BluetoothUUID.bit16))
            case .incompleteListOf32BitServiceClassUUIDs:
                add(GAPIncompleteListOf32BitServiceClassUUIDs(data: value)?.uuids.map(BluetoothUUID.bit32))
            case .completeListOf32BitServiceClassUUIDs:
                add(GAPCompleteListOf32BitServiceClassUUIDs(data: value)?.uuids.map(BluetoothUUID.bit32))
            case .incompleteListOf128BitServiceClassUUIDs:
                add(GAPIncompleteListOf128BitServiceClassUUIDs(data: value)?.uuids.map(BluetoothUUID.init(uuid:)))
            case .completeListOf128BitServiceClassUUIDs:
                add(GAPCompleteListOf128BitServiceClassUUIDs(data: value)?.uuids.map(BluetoothUUID.init(uuid:)))
            case .serviceData16BitUUID:
                if let element = GAPServiceData16BitUUID<Data>(data: value) {
                    add(element.serviceData, for: .bit16(element.uuid))
                }
            case .serviceData32BitUUID:
                if let element = GAPServiceData32BitUUID<Data>(data: value) {
                    add(element.serviceData, for: .bit32(element.uuid))
                }
            case .serviceData128BitUUID:
                if let element = GAPServiceData128BitUUID<Data>(data: value) {
                    add(element.serviceData, for: BluetoothUUID(uuid: element.uuid))
                }
            default:
                break
            }
        }
        localName = completeName ?? shortName
    }

    /// One list of service UUIDs: a packet can carry several (16- and
    /// 128-bit, complete and not), and they are all its services.
    private mutating func add(_ uuids: [BluetoothUUID]?) {
        guard let uuids else { return }
        serviceUUIDs = (serviceUUIDs ?? []) + uuids
    }

    /// The data for one service.
    private mutating func add(_ data: Data, for uuid: BluetoothUUID) {
        var all = serviceData ?? [:]
        all[uuid] = data
        serviceData = all
    }
}

extension BluetoothPeripheral {

    /// The fields one advertising packet carries. The ones it leaves out
    /// keep their values: the advertisement and the scan response can
    /// arrive separately, each with part of them.
    func take(_ advertisement: AdvertisingData) {
        if let name = advertisement.localName {
            update(\.localName, name)
        }
        if let manufacturerData = advertisement.manufacturerData {
            update(\.manufacturerData, manufacturerData)
        }
        if let serviceUUIDs = advertisement.serviceUUIDs {
            update(\.serviceUUIDs, serviceUUIDs)
        }
        if let serviceData = advertisement.serviceData {
            update(\.serviceData, serviceData)
        }
        if let txPowerLevel = advertisement.txPowerLevel {
            update(\.txPowerLevel, txPowerLevel)
        }
    }
}

// MARK: - Identifiers

extension BluetoothUUID {

    /// From the 128-bit form some systems give every UUID in (Android,
    /// BlueZ), `0000180d-0000-1000-8000-00805f9b34fb`. An assigned number on
    /// the Bluetooth base UUID becomes its 16-bit form (`180D`), the way
    /// CoreBluetooth gives it, so it equals PureSwift's definitions and has
    /// its name.
    init?(uuidString: String) {
        guard let uuid = UUID(uuidString: uuidString) else { return nil }
        if let short = UInt16(bluetooth: uuid) {
            self = .bit16(short)
        } else {
            self.init(uuid: uuid)
        }
    }
}

extension UUID {

    /// A peripheral's `id` on systems that name a device by its address
    /// (`AA:BB:CC:DD:EE:FF`) instead of giving it an identifier: the six
    /// bytes of the address at the end of an otherwise zero UUID,
    /// `00000000-0000-0000-0000-AABBCCDDEEFF`. `nil` when it is not an
    /// address.
    init?(bluetoothAddress address: String) {
        let parts = address.split(separator: ":")
        guard parts.count == 6 else { return nil }
        var bytes = [UInt8](repeating: 0, count: 16)
        for (index, part) in parts.enumerated() {
            guard part.count == 2, let byte = UInt8(part, radix: 16) else { return nil }
            bytes[10 + index] = byte
        }
        self.init(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
