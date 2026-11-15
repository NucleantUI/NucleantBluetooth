//
//  Environment.swift
//  NucleantBluetooth
//
//  `@Environment(\.bluetoothManager)`: the manager every view reaches.
//

import NucleantUI

private struct BluetoothManagerKey: EnvironmentKey {
    /// Made the first time a view reads it.
    static let defaultValue = BluetoothManager()
}

extension EnvironmentValues {
    /// The Bluetooth manager views use:
    ///
    /// ```swift
    /// @Environment(\.bluetoothManager) private var ble
    /// ```
    ///
    /// One for the whole app, made the first time a view reads it — which is
    /// when the system asks the user for Bluetooth the first time. A subtree
    /// can be given another with `.environment(\.bluetoothManager, manager)`.
    public var bluetoothManager: BluetoothManager {
        get { self[BluetoothManagerKey.self] }
        set { self[BluetoothManagerKey.self] = newValue }
    }
}
