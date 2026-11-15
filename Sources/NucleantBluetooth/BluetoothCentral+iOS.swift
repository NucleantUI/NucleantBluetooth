//
//  BluetoothCentral+iOS.swift
//  NucleantBluetooth
//
//  iOS: CoreBluetooth. One `CBCentralManager`, delegate of it and of every
//  `CBPeripheral` it finds, on the main queue — where the classes it updates
//  are used.
//

#if os(iOS)
import CoreBluetooth
import Foundation

final class BluetoothCentral: NSObject, BluetoothCentralPlatform {

    typealias NativePeripheral = CBPeripheral
    typealias NativeService = CBService
    typealias NativeCharacteristic = CBCharacteristic

    /// Owns this central.
    private unowned let manager: BluetoothManager

    private var central: CBCentralManager!

    init(manager: BluetoothManager) {
        self.manager = manager
        super.init()
        // The main queue: the delegate calls below arrive there.
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func scan(services: [BluetoothUUID]?, allowDuplicates: Bool) {
        central.scanForPeripherals(
            withServices: services?.map(CBUUID.init),
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: allowDuplicates]
        )
    }

    func stopScan() {
        central.stopScan()
    }

    func connect(_ peripheral: BluetoothPeripheral) {
        central.connect(peripheral.native)
    }

    func disconnect(_ peripheral: BluetoothPeripheral) {
        central.cancelPeripheralConnection(peripheral.native)
    }

    func readRSSI(of peripheral: BluetoothPeripheral) {
        peripheral.native.readRSSI()
    }

    func discoverServices(_ uuids: [BluetoothUUID]?, of peripheral: BluetoothPeripheral) {
        peripheral.native.discoverServices(uuids?.map(CBUUID.init))
    }

    func discoverCharacteristics(_ uuids: [BluetoothUUID]?, of service: BluetoothService) {
        service.peripheral?.native.discoverCharacteristics(uuids?.map(CBUUID.init), for: service.native)
    }

    func read(_ characteristic: BluetoothCharacteristic) {
        characteristic.service?.peripheral?.native.readValue(for: characteristic.native)
    }

    func write(_ value: Data, to characteristic: BluetoothCharacteristic, withResponse: Bool) {
        characteristic.service?.peripheral?.native.writeValue(
            value,
            for: characteristic.native,
            type: withResponse ? .withResponse : .withoutResponse
        )
    }

    func setNotifying(_ enabled: Bool, for characteristic: BluetoothCharacteristic) {
        characteristic.service?.peripheral?.native.setNotifyValue(enabled, for: characteristic.native)
    }

    /// The peripheral listed for `native`.
    private func known(_ native: CBPeripheral) -> BluetoothPeripheral? {
        manager.knownPeripheral(native.identifier)
    }
}

// MARK: - Central

extension BluetoothCentral: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        // `CBManagerState`'s values are `BluetoothState`'s.
        manager.stateDidChange(BluetoothState(rawValue: central.state.rawValue) ?? .unknown)
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover native: CBPeripheral,
        advertisementData: [String: Any],
        rssi number: NSNumber
    ) {
        let peripheral = manager.peripheral(native.identifier, native: native)
        native.delegate = self
        peripheral.update(\.name, native.name)
        // 127 is CoreBluetooth's "not available", outside `RSSI`'s range.
        peripheral.update(\.rssi, RSSI(rawValue: Int8(clamping: number.intValue)))
        peripheral.lastSeen = Date()
        peripheral.takeAdvertisement(advertisementData)
    }

    func centralManager(_ central: CBCentralManager, didConnect native: CBPeripheral) {
        known(native)?.didConnect()
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect native: CBPeripheral, error: (any Error)?) {
        known(native)?.didFailToConnect(.connectionFailed(error?.localizedDescription ?? "no reason given"))
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral native: CBPeripheral,
        error: (any Error)?
    ) {
        known(native)?.didDisconnect(error: error.map { .connectionLost($0.localizedDescription) })
    }
}

// MARK: - Peripherals

extension BluetoothCentral: CBPeripheralDelegate {

    func peripheralDidUpdateName(_ native: CBPeripheral) {
        known(native)?.update(\.name, native.name)
    }

    func peripheral(_ native: CBPeripheral, didReadRSSI number: NSNumber, error: (any Error)?) {
        guard let peripheral = known(native) else { return }
        if let error {
            peripheral.error = .rssiFailed(error.localizedDescription)
            return
        }
        peripheral.update(\.rssi, RSSI(rawValue: Int8(clamping: number.intValue)))
    }

    func peripheral(_ native: CBPeripheral, didDiscoverServices error: (any Error)?) {
        guard let peripheral = known(native) else { return }
        if let error {
            peripheral.error = .discoveryFailed(error.localizedDescription)
            return
        }
        // The ones found before stay the same objects, characteristics and
        // all; a discovery with a filter adds to them.
        peripheral.services = (native.services ?? []).map { service in
            peripheral.service(for: service)
                ?? BluetoothService(
                    native: service,
                    uuid: BluetoothUUID(service.uuid),
                    isPrimary: service.isPrimary,
                    peripheral: peripheral
                )
        }
    }

    func peripheral(_ native: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        guard let peripheral = known(native) else { return }
        peripheral.services.removeAll { service in
            invalidatedServices.contains { $0 === service.native }
        }
    }

    func peripheral(_ native: CBPeripheral, didDiscoverCharacteristicsFor nativeService: CBService, error: (any Error)?) {
        guard let service = known(native)?.service(for: nativeService) else { return }
        if let error {
            service.error = .discoveryFailed(error.localizedDescription)
            return
        }
        service.error = nil
        service.characteristics = (nativeService.characteristics ?? []).map { characteristic in
            service.characteristic(for: characteristic)
                ?? BluetoothCharacteristic(
                    native: characteristic,
                    uuid: BluetoothUUID(characteristic.uuid),
                    properties: GATTCharacteristicProperties(characteristic.properties),
                    service: service
                )
        }
    }

    func peripheral(
        _ native: CBPeripheral,
        didUpdateValueFor nativeCharacteristic: CBCharacteristic,
        error: (any Error)?
    ) {
        guard let characteristic = known(native)?.characteristic(for: nativeCharacteristic) else { return }
        if let error {
            characteristic.error = .readFailed(error.localizedDescription)
            return
        }
        characteristic.error = nil
        characteristic.value = nativeCharacteristic.value
    }

    func peripheral(
        _ native: CBPeripheral,
        didWriteValueFor nativeCharacteristic: CBCharacteristic,
        error: (any Error)?
    ) {
        guard let characteristic = known(native)?.characteristic(for: nativeCharacteristic) else { return }
        characteristic.error = error.map { .writeFailed($0.localizedDescription) }
    }

    func peripheral(
        _ native: CBPeripheral,
        didUpdateNotificationStateFor nativeCharacteristic: CBCharacteristic,
        error: (any Error)?
    ) {
        guard let characteristic = known(native)?.characteristic(for: nativeCharacteristic) else { return }
        if let error {
            characteristic.error = .notificationFailed(error.localizedDescription)
        } else {
            characteristic.error = nil
        }
        characteristic.isNotifying = nativeCharacteristic.isNotifying
    }
}

// MARK: - Advertisements

extension BluetoothPeripheral {

    /// The fields one advertisement packet carries. The ones it leaves out
    /// keep their values: the advertisement and the scan response arrive
    /// separately, each with part of them.
    func takeAdvertisement(_ data: [String: Any]) {
        if let name = data[CBAdvertisementDataLocalNameKey] as? String {
            update(\.localName, name)
        }
        if let bytes = data[CBAdvertisementDataManufacturerDataKey] as? Data {
            update(\.manufacturerData, GAPManufacturerSpecificData<Data>(data: bytes))
        }
        if let uuids = data[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
            update(\.serviceUUIDs, uuids.map(BluetoothUUID.init))
        }
        if let serviceData = data[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data] {
            update(\.serviceData, Dictionary(serviceData.map { (BluetoothUUID($0.key), $0.value) }) { first, _ in first })
        }
        if let power = data[CBAdvertisementDataTxPowerLevelKey] as? NSNumber {
            update(\.txPowerLevel, GAPTxPowerLevel(powerLevel: Int8(clamping: power.intValue)))
        }
        if let connectable = data[CBAdvertisementDataIsConnectable] as? NSNumber {
            update(\.isConnectable, connectable.boolValue)
        }
    }
}

// MARK: - CoreBluetooth's values

extension GATTCharacteristicProperties {

    /// CoreBluetooth's properties: GATT's bits, and above them two of its
    /// own (notify and indicate needing encryption), which GATT's leave out.
    init(_ properties: CBCharacteristicProperties) {
        self.init(rawValue: UInt8(truncatingIfNeeded: properties.rawValue))
    }
}
#endif
