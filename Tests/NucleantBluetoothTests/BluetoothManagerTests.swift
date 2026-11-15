//
//  BluetoothManagerTests.swift
//  NucleantBluetoothTests
//
//  The manager's own bookkeeping: its state, a scan waiting for Bluetooth,
//  and the environment value views reach it through.
//

import Foundation
import NucleantUI
import Testing
@testable import NucleantBluetooth

@MainActor
@Suite struct BluetoothManagerTests {

    @Test func startsEmpty() {
        let manager = BluetoothManager()
        #expect(manager.state == .unknown)
        #expect(!manager.isScanning)
        #expect(manager.peripherals.isEmpty)
    }

    @Test func systemAnswersWithItsState() async throws {
        let manager = BluetoothManager()
        let deadline = ContinuousClock.now + .seconds(10)
        while manager.state == .unknown, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(manager.state != .unknown)
    }

    @Test func scanAskedBeforeBluetoothIsOnStartsWhenItIs() {
        let manager = BluetoothManager()
        manager.stateDidChange(.poweredOff)
        manager.scan(allowDuplicates: true)
        #expect(!manager.isScanning)

        manager.stateDidChange(.poweredOn)
        #expect(manager.isScanning)
    }

    @Test func scanStopsWhenBluetoothTurnsOffAndResumesWhenItIsBack() {
        let manager = BluetoothManager()
        manager.stateDidChange(.poweredOn)
        manager.scan()
        #expect(manager.isScanning)

        manager.stateDidChange(.poweredOff)
        #expect(!manager.isScanning)

        manager.stateDidChange(.poweredOn)
        #expect(manager.isScanning)
    }

    @Test func stoppedScanStaysStopped() {
        let manager = BluetoothManager()
        manager.stateDidChange(.poweredOn)
        manager.scan()
        manager.stopScan()
        #expect(!manager.isScanning)

        manager.stateDidChange(.poweredOff)
        manager.stateDidChange(.poweredOn)
        #expect(!manager.isScanning)
    }

    @Test func environmentHasOneManagerUnlessGivenAnother() {
        let shared = EnvironmentValues().bluetoothManager
        #expect(EnvironmentValues().bluetoothManager === shared)

        var values = EnvironmentValues()
        let other = BluetoothManager()
        values.bluetoothManager = other
        #expect(values.bluetoothManager === other)
        #expect(values.bluetoothManager !== shared)
    }
}
