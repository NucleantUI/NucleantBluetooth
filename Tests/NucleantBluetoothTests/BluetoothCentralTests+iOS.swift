//
//  BluetoothCentralTests+iOS.swift
//  NucleantBluetoothTests
//
//  iOS: CoreBluetooth's values as NucleantBluetooth's. The simulator has no
//  Bluetooth, so it is also where `.unsupported` is checked.
//

#if os(iOS)
import CoreBluetooth
import Foundation
import Testing
@testable import NucleantBluetooth

@MainActor
@Suite struct BluetoothCentralTests {

    @Test(arguments: [
        (CBManagerState.unknown, BluetoothState.unknown),
        (.resetting, .resetting),
        (.unsupported, .unsupported),
        (.unauthorized, .unauthorized),
        (.poweredOff, .poweredOff),
        (.poweredOn, .poweredOn),
    ])
    func managerState(_ native: CBManagerState, _ state: BluetoothState) {
        #expect(BluetoothState(rawValue: native.rawValue) == state)
    }

    @Test(arguments: [
        (CBPeripheralState.disconnected, BluetoothConnectionState.disconnected),
        (.connecting, .connecting),
        (.connected, .connected),
        (.disconnecting, .disconnecting),
    ])
    func connectionState(_ native: CBPeripheralState, _ state: BluetoothConnectionState) {
        #expect(BluetoothConnectionState(rawValue: native.rawValue) == state)
    }

    @Test func characteristicProperties() {
        let native: CBCharacteristicProperties = [
            .broadcast, .read, .writeWithoutResponse, .write, .notify, .indicate,
            .authenticatedSignedWrites, .extendedProperties,
            // CoreBluetooth's own, with no GATT bit.
            .notifyEncryptionRequired, .indicateEncryptionRequired,
        ]
        let properties = GATTCharacteristicProperties(native)
        #expect(properties == [
            .broadcast, .read, .writeWithoutResponse, .write, .notify, .indicate,
            .signedWrite, .extendedProperties,
        ])
        #expect(GATTCharacteristicProperties(CBCharacteristicProperties([.read, .notify])) == [.read, .notify])
    }

    @Test func uuidsAndTheirNames() {
        let heartRate = BluetoothUUID(CBUUID(string: "180D"))
        #expect(heartRate == .bit16(0x180D))
        #expect(heartRate.metadata?.name == "Heart Rate")

        let custom = UUID()
        #expect(BluetoothUUID(CBUUID(nsuuid: custom)) == BluetoothUUID(uuid: custom))
        #expect(CBUUID(BluetoothUUID(uuid: custom)) == CBUUID(nsuuid: custom))
    }

    #if targetEnvironment(simulator)
    @Test func simulatorHasNoBluetooth() async throws {
        let manager = BluetoothManager()
        let deadline = ContinuousClock.now + .seconds(10)
        while manager.state == .unknown, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(manager.state == .unsupported)
        manager.scan()
        #expect(!manager.isScanning)
    }
    #endif
}
#endif
