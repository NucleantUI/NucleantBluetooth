//
//  AdvertisingDataTests.swift
//  NucleantBluetoothTests
//
//  Advertising packets read from their bytes, the way Android hands them
//  over, and the identifiers of the systems that name devices by address
//  and UUIDs in their 128-bit form.
//

import Foundation
import Testing
@testable import NucleantBluetooth

@Suite struct AdvertisingDataTests {

    /// A packet with one of each field, then zeros up to the 62 bytes
    /// Android's ScanRecord holds.
    static let packet: [UInt8] = [
        0x02, 0x01, 0x06,                                   // flags
        0x06, 0x09, 0x48, 0x65, 0x61, 0x72, 0x74,           // complete name "Heart"
        0x05, 0x03, 0x0D, 0x18, 0x0F, 0x18,                 // 16-bit services 180D, 180F
        0x02, 0x0A, 0xFC,                                   // transmit power -4 dBm
        0x06, 0xFF, 0x4C, 0x00, 0x01, 0x02, 0x03,           // Apple (0x004C), 01 02 03
        0x05, 0x16, 0x1A, 0x18, 0xAB, 0xCD,                 // data for 181A: AB CD
    ]

    static func padded(_ bytes: [UInt8]) -> Data {
        Data(bytes + [UInt8](repeating: 0, count: max(0, 62 - bytes.count)))
    }

    @Test func everyField() {
        let advertisement = AdvertisingData(Self.padded(Self.packet))
        #expect(advertisement.localName == "Heart")
        #expect(advertisement.serviceUUIDs == [.bit16(0x180D), .bit16(0x180F)])
        #expect(advertisement.txPowerLevel?.powerLevel == -4)
        #expect(advertisement.manufacturerData?.companyIdentifier == CompanyIdentifier(rawValue: 0x004C))
        #expect(advertisement.manufacturerData?.additionalData == Data([0x01, 0x02, 0x03]))
        #expect(advertisement.serviceData == [.bit16(0x181A): Data([0xAB, 0xCD])])
    }

    @Test func fieldsLeftOutAreNil() {
        let advertisement = AdvertisingData(Self.padded([0x02, 0x01, 0x06]))
        #expect(advertisement.localName == nil)
        #expect(advertisement.serviceUUIDs == nil)
        #expect(advertisement.serviceData == nil)
        #expect(advertisement.manufacturerData == nil)
        #expect(advertisement.txPowerLevel == nil)
    }

    @Test func completeNameOverShortName() {
        let short: [UInt8] = [0x03, 0x08, 0x48, 0x65]                   // short name "He"
        let complete: [UInt8] = [0x06, 0x09, 0x48, 0x65, 0x61, 0x72, 0x74]
        #expect(AdvertisingData(Data(short)).localName == "He")
        #expect(AdvertisingData(Data(short + complete)).localName == "Heart")
        #expect(AdvertisingData(Data(complete + short)).localName == "Heart")
    }

    @Test func everyServiceListIsTaken() {
        // A complete 16-bit list, an incomplete one, and a 128-bit one,
        // whose bytes are the UUID's in reverse.
        let uuid = UUID(uuidString: "12345678-1234-5678-1234-56789ABCDEF0")!
        let uuidBytes = withUnsafeBytes(of: uuid.uuid) { [UInt8]($0) }
        let bytes: [UInt8] = [0x03, 0x03, 0x0D, 0x18, 0x03, 0x02, 0x0F, 0x18, 0x11, 0x07] + uuidBytes.reversed()
        let advertisement = AdvertisingData(Data(bytes))
        #expect(advertisement.serviceUUIDs == [.bit16(0x180D), .bit16(0x180F), BluetoothUUID(uuid: uuid)])
    }

    @Test func aCutOffStructureEndsThePacket() {
        // The name says 5 bytes and has 2; the services after it are not read.
        let bytes: [UInt8] = [0x02, 0x0A, 0xFC, 0x05, 0x09, 0x41, 0x42]
        let advertisement = AdvertisingData(Data(bytes))
        #expect(advertisement.txPowerLevel?.powerLevel == -4)
        #expect(advertisement.localName == nil)
        #expect(AdvertisingData(Data()).localName == nil)
    }

    // MARK: - Identifiers

    @Test func assignedNumbersBecomeTheir16BitForm() {
        let heartRate = BluetoothUUID(uuidString: "0000180d-0000-1000-8000-00805f9b34fb")
        #expect(heartRate == .bit16(0x180D))
        #expect(heartRate?.metadata?.name == "Heart Rate")
        #expect(BluetoothUUID(uuidString: "00002A19-0000-1000-8000-00805F9B34FB") == GATTBatteryLevel.uuid)
    }

    @Test func otherUUIDsStay128Bit() {
        let uuid = UUID(uuidString: "12345678-1234-5678-1234-56789ABCDEF0")!
        #expect(BluetoothUUID(uuidString: uuid.uuidString) == BluetoothUUID(uuid: uuid))
        #expect(BluetoothUUID(uuidString: "not a uuid") == nil)
    }

    @Test func addressesBecomeIdentifiers() {
        #expect(UUID(bluetoothAddress: "AA:BB:CC:DD:EE:0F")?.uuidString == "00000000-0000-0000-0000-AABBCCDDEE0F")
        #expect(UUID(bluetoothAddress: "aa:bb:cc:dd:ee:0f") == UUID(bluetoothAddress: "AA:BB:CC:DD:EE:0F"))
        #expect(UUID(bluetoothAddress: "AA:BB:CC:DD:EE") == nil)
        #expect(UUID(bluetoothAddress: "AA:BB:CC:DD:EE:GG") == nil)
    }
}
