//
//  BluetoothCentral+Android.swift
//  NucleantBluetooth
//
//  Android: android.bluetooth through swift-java. The adapter from the
//  Bluetooth system service, a BluetoothLeScanner scan, and one BluetoothGatt
//  per connection, with every callback on the main thread, where the classes
//  it updates are used.
//
//  What the app provides (README, Android): the Java in Android/java,
//  compiled with the app, the `BluetoothAppContext` provider in its manifest,
//  and the permissions. Android hands scan results only to an app with
//  ACCESS_FINE_LOCATION. From API 31 the app needs BLUETOOTH_SCAN and
//  BLUETOOTH_CONNECT, and location only when BLUETOOTH_SCAN is not declared
//  `neverForLocation`. The central asks for what it needs on the Activity in
//  front when it starts; until it has them the state is `.unauthorized`.
//
//  Android identifies a device by its address, so a peripheral's `id` is the
//  address in a UUID (`UUID(bluetoothAddress:)`). A GATT connection takes one
//  request at a time, so each connection queues its requests and sends the
//  next when the last is answered.
//

#if os(Android)
import Android
import Foundation
import SwiftJava

/// `BluetoothAdapter.STATE_*`.
enum AdapterState: Int32 {
    case off = 10
    case turningOn = 11
    case on = 12
    case turningOff = 13
}

final class BluetoothCentral: BluetoothCentralPlatform {

    typealias NativePeripheral = BluetoothDevice
    typealias NativeService = BluetoothGattService
    typealias NativeCharacteristic = BluetoothGattCharacteristic

    /// Owns this central.
    private unowned let manager: BluetoothManager

    private var environment: JNIEnvironment?
    private var context: Context?
    private var adapter: BluetoothAdapter?

    /// What scanning and connecting need (`requiredPermissions(sdkLevel:scanNeedsLocation:)`).
    private var requiredPermissions: [String] = []
    /// Whether scan results need location access, so the location setting
    /// on as well.
    private var scanNeedsLocation = true

    /// What the Java helpers carry back: this central, weakly.
    private var handle: Int64 = 0
    private var stateReceiver: AdapterStateReceiver?
    private var scanCallbacks: ScanCallbacks?

    /// Whether the scan running takes every advertisement, and the devices
    /// it has reported when it does not.
    private var scanTakesDuplicates = true
    private var reported: Set<UUID> = []

    /// The permissions are asked for once: asking again after a no would put
    /// the dialog back on every resume.
    private var askedForPermissions = false

    private var connections: [UUID: GattConnection] = [:]

    /// `PackageManager.PERMISSION_GRANTED`.
    private static let permissionGranted: Int32 = 0
    /// The request code the permissions are asked for with ("BT").
    private static let permissionRequestCode: Int32 = 0x4254

    init(manager: BluetoothManager) {
        self.manager = manager
        Self.pointMainBundleAtTheApp()

        do {
            let environment = try JavaVirtualMachine.shared().environment()
            self.environment = environment
            let sdkLevel = try JavaClass<BuildVersion>(environment: environment).SDK_INT
            let appContext = try JavaClass<BluetoothAppContext>(environment: environment)
            guard let context = appContext.context() else {
                log("""
                    org.nucleantui.bluetooth.BluetoothAppContext has no Context: \
                    declare it as a <provider> in the app's manifest (NucleantBluetooth's README, Android).
                    """)
                manager.stateDidChange(.unsupported)
                return
            }
            self.context = context
            scanNeedsLocation = appContext.scanNeedsLocation()
            requiredPermissions = Self.requiredPermissions(sdkLevel: sdkLevel, scanNeedsLocation: scanNeedsLocation)
            adapter = context.getSystemService("bluetooth")?.as(AndroidBluetoothManager.self)?.getAdapter()
        } catch {
            log("""
                no Android/java helpers (\(error)): compile NucleantBluetooth's Android/java \
                with the app (NucleantBluetooth's README, Android).
                """)
            manager.stateDidChange(.unsupported)
            return
        }

        guard let environment, let context, adapter != nil else {
            manager.stateDidChange(.unsupported)
            return
        }
        handle = NativeHandle.retain(self)
        let receiver = AdapterStateReceiver(handle, environment: environment)
        receiver.register(context)
        stateReceiver = receiver
        try? JavaClass<BluetoothAppContext>(environment: environment).addResumeListener(handle)
        refreshState()
    }

    deinit {
        guard handle != 0 else { return }
        for connection in connections.values {
            connection.close()
        }
        if let adapter, let scanCallbacks {
            scanCallbacks.stop(adapter)
            scanCallbacks.disarm()
        }
        if let stateReceiver, let context {
            stateReceiver.disarm()
            stateReceiver.unregister(context)
        }
        if let environment {
            try? JavaClass<BluetoothAppContext>(environment: environment).removeResumeListener(handle)
        }
        NativeHandle<BluetoothCentral>.release(handle)
    }

    // MARK: - Scanning

    func scan(services: [BluetoothUUID]?, allowDuplicates: Bool) {
        guard let environment, let adapter else { return }
        let callbacks = scanCallbacks ?? ScanCallbacks(handle, environment: environment)
        // A scan already running is replaced.
        if scanCallbacks != nil {
            callbacks.stop(adapter)
        }
        scanCallbacks = callbacks
        scanTakesDuplicates = allowDuplicates
        reported = []
        // Android's filters take 128-bit UUIDs.
        if !callbacks.start(adapter, (services ?? []).map(\.bit128.rawValue)) {
            log("the scan did not start")
            manager.isScanning = false
        }
    }

    func stopScan() {
        guard let adapter, let scanCallbacks else { return }
        scanCallbacks.stop(adapter)
    }

    /// One advertisement, or a scan response.
    func scanned(_ result: ScanResult) {
        guard let device = result.getDevice(), let id = UUID(bluetoothAddress: device.getAddress()) else { return }
        guard scanTakesDuplicates || reported.insert(id).inserted else { return }
        let peripheral = manager.peripheral(id, native: device)
        // Android forgets a device's name at times (after a connection
        // ends, for one) and answers with none; the name stays as known.
        if let name = try? device.getName(), !name.isEmpty {
            peripheral.update(\.name, name)
        }
        peripheral.update(\.rssi, RSSI(rawValue: Int8(clamping: result.getRssi())))
        peripheral.lastSeen = Date()
        peripheral.update(\.isConnectable, result.isConnectable())
        if let record = result.getScanRecord() {
            peripheral.take(AdvertisingData(Data(record.getBytes().map { UInt8(bitPattern: $0) })))
        }
    }

    /// `ScanCallback.SCAN_FAILED_*`. Starting more than five scans in 30
    /// seconds is one of them on some devices; on others the scan just
    /// finds nothing.
    func scanFailed(_ errorCode: Int32) {
        log("the scan failed: SCAN_FAILED code \(errorCode)")
        manager.isScanning = false
    }

    // MARK: - State

    /// Bluetooth turned on or off.
    func adapterStateChanged(_ state: Int32) {
        refreshState(adapterState: AdapterState(rawValue: state))
    }

    /// The app is in front again: the user may have answered the permission
    /// dialog, or changed something in Settings.
    func activityResumed() {
        refreshState()
    }

    private func refreshState(adapterState: AdapterState? = nil) {
        guard let context, let adapter else { return }
        guard requiredPermissions.allSatisfy({ context.checkSelfPermission($0) == Self.permissionGranted }) else {
            askForPermissions()
            endConnections()
            manager.stateDidChange(.unauthorized)
            return
        }
        let state = adapterState ?? AdapterState(rawValue: adapter.getState())
        if state == .on {
            if scanNeedsLocation, let environment,
               (try? JavaClass<BluetoothAppContext>(environment: environment).locationIsOn()) == false {
                log("location is off: Android gives no scan results until it is on")
            }
            manager.stateDidChange(.poweredOn)
        } else {
            // Turning off ends the scan and every connection.
            endConnections()
            manager.stateDidChange(.poweredOff)
        }
    }

    /// What scanning and connecting need: the Nearby devices permission from
    /// API 31, precise location before it, and from 31 precise location as
    /// well unless the app declares BLUETOOTH_SCAN `neverForLocation`.
    private static func requiredPermissions(sdkLevel: Int32, scanNeedsLocation: Bool) -> [String] {
        let location = "android.permission.ACCESS_FINE_LOCATION"
        guard sdkLevel >= 31 else { return [location] }
        let nearby = ["android.permission.BLUETOOTH_SCAN", "android.permission.BLUETOOTH_CONNECT"]
        return scanNeedsLocation ? nearby + [location] : nearby
    }

    /// Ask on the Activity in front. With none in front yet, the next
    /// resume asks.
    private func askForPermissions() {
        guard !askedForPermissions, let environment,
              let activity = try? JavaClass<BluetoothAppContext>(environment: environment).resumedActivity()
        else { return }
        askedForPermissions = true
        activity.requestPermissions(requiredPermissions, Self.permissionRequestCode)
    }

    private func endConnections() {
        for connection in connections.values {
            connection.close()
        }
        connections = [:]
    }

    // MARK: - Connections

    func connect(_ peripheral: BluetoothPeripheral) {
        guard let environment, let context else { return }
        let connection = GattConnection(peripheral: peripheral, central: self, environment: environment)
        guard let gatt = connection.callbacks.connect(context, peripheral.native) else {
            connection.close()
            peripheral.didFailToConnect(.connectionFailed("Android did not start the connection"))
            return
        }
        connection.gatt = gatt
        connections[peripheral.id] = connection
    }

    func disconnect(_ peripheral: BluetoothPeripheral) {
        guard let connection = connections[peripheral.id] else {
            peripheral.didDisconnect(error: nil)
            return
        }
        if connection.isConnected {
            // Android answers with onConnectionStateChange, which ends it.
            try? connection.gatt?.disconnect()
        } else {
            // Still connecting: closing stops it, and Android says nothing
            // more about a closed connection.
            connectionEnded(connection)
            peripheral.didDisconnect(error: nil)
        }
    }

    /// Close `connection` and forget it.
    func connectionEnded(_ connection: GattConnection) {
        connection.close()
        if let id = connection.peripheral?.id, connections[id] === connection {
            connections[id] = nil
        }
    }

    func readRSSI(of peripheral: BluetoothPeripheral) {
        connections[peripheral.id]?.enqueue(.readRSSI)
    }

    func discoverServices(_ uuids: [BluetoothUUID]?, of peripheral: BluetoothPeripheral) {
        connections[peripheral.id]?.enqueue(.discoverServices(uuids))
    }

    /// Android discovers the characteristics with the services, so they are
    /// there already.
    func discoverCharacteristics(_ uuids: [BluetoothUUID]?, of service: BluetoothService) {
        guard let id = service.peripheral?.id, let connection = connections[id] else { return }
        connection.listCharacteristics(uuids, of: service)
    }

    func read(_ characteristic: BluetoothCharacteristic) {
        connection(of: characteristic)?.enqueue(.read(characteristic))
    }

    func write(_ value: Data, to characteristic: BluetoothCharacteristic, withResponse: Bool) {
        connection(of: characteristic)?.enqueue(.write(characteristic, value, withResponse: withResponse))
    }

    func setNotifying(_ enabled: Bool, for characteristic: BluetoothCharacteristic) {
        connection(of: characteristic)?.enqueue(.setNotifying(characteristic, enabled))
    }

    private func connection(of characteristic: BluetoothCharacteristic) -> GattConnection? {
        guard let id = characteristic.service?.peripheral?.id else { return nil }
        return connections[id]
    }

    // MARK: - Bundles

    /// PureSwift's names (`uuid.metadata?.name`, `companyIdentifier.name`)
    /// come from its resource bundle, which `Bundle.module` looks for next to
    /// `Bundle.main`. In an Android app that is the zygote's directory, where
    /// it is not, and `Bundle.module` stops the app. nucleant unpacks the
    /// resource bundles into the app's files, `NUCLEANT_APP_PATH`, and
    /// Foundation takes `CFProcessPath` as the executable's path: pointing it
    /// into that directory makes `Bundle.main` the directory, which every
    /// `Bundle.module` then finds its bundle in. It has to be set before
    /// anything uses `Bundle.main`, and only when nothing else has set it.
    private static func pointMainBundleAtTheApp() {
        guard getenv("CFProcessPath") == nil, let appPath = getenv("NUCLEANT_APP_PATH") else { return }
        setenv("CFProcessPath", String(cString: appPath) + "/NucleantMain", 0)
    }

    fileprivate func log(_ message: String) {
        print("NucleantBluetooth: \(message)")
    }
}

// MARK: - A connection

/// What a GATT connection is asked for. Android takes one at a time.
enum GattRequest {
    case discoverServices([BluetoothUUID]?)
    case read(BluetoothCharacteristic)
    case write(BluetoothCharacteristic, Data, withResponse: Bool)
    case setNotifying(BluetoothCharacteristic, Bool)
    case readRSSI
}

/// One `BluetoothGatt`, from `connect` until it is closed: its requests, one
/// at a time, and the services and characteristics found on it by their
/// attribute handles, which Android's callbacks name them by.
final class GattConnection {

    private(set) weak var peripheral: BluetoothPeripheral?
    private unowned let central: BluetoothCentral

    var gatt: BluetoothGatt?
    private(set) var callbacks: GattCallbacks!
    private var handle: Int64 = 0
    private(set) var isConnected = false

    private var services: [Int32: BluetoothService] = [:]
    private var characteristics: [Int32: BluetoothCharacteristic] = [:]

    private var queue: [GattRequest] = []
    private var current: GattRequest?

    /// `BluetoothProfile.STATE_*`.
    private static let stateDisconnected: Int32 = 0
    private static let stateConnected: Int32 = 2

    init(peripheral: BluetoothPeripheral, central: BluetoothCentral, environment: JNIEnvironment) {
        self.peripheral = peripheral
        self.central = central
        handle = NativeHandle.retain(self)
        callbacks = GattCallbacks(handle, environment: environment)
    }

    /// Stop its callbacks and give the connection up. Nothing is reported.
    func close() {
        guard handle != 0 else { return }
        callbacks.disarm()
        try? gatt?.close()
        gatt = nil
        NativeHandle<GattConnection>.release(handle)
        handle = 0
        isConnected = false
        queue = []
        current = nil
    }

    // MARK: Requests

    func enqueue(_ request: GattRequest) {
        queue.append(request)
        startNext()
    }

    private func startNext() {
        guard current == nil, isConnected, let gatt else { return }
        while !queue.isEmpty {
            let request = queue.removeFirst()
            if start(request, on: gatt) {
                current = request
                return
            }
        }
    }

    /// Ask Android for `request`. `false`, with the failure reported, when
    /// it would not take it.
    private func start(_ request: GattRequest, on gatt: BluetoothGatt) -> Bool {
        switch request {
        case .discoverServices:
            if (try? gatt.discoverServices()) == true { return true }
            peripheral?.error = .discoveryFailed("Android did not start the discovery")
        case .read(let characteristic):
            if (try? gatt.readCharacteristic(characteristic.native)) == true { return true }
            characteristic.error = .readFailed("Android did not start the read")
        case .write(let characteristic, let value, let withResponse):
            let bytes = value.map { Int8(bitPattern: $0) }
            let started = try? JavaClass<GattCallbacks>(environment: gatt.javaEnvironment)
                .write(gatt, characteristic.native, bytes, withResponse)
            if started == true { return true }
            characteristic.error = .writeFailed("Android did not start the write")
        case .setNotifying(let characteristic, let enabled):
            let result = try? JavaClass<GattCallbacks>(environment: gatt.javaEnvironment)
                .setNotifying(gatt, characteristic.native, enabled)
            switch result {
            case 0?: return true
            case 1?: characteristic.error = .notificationFailed("it has no Client Characteristic Configuration descriptor")
            default: characteristic.error = .notificationFailed("Android did not start it")
            }
        case .readRSSI:
            if (try? gatt.readRemoteRssi()) == true { return true }
            peripheral?.error = .rssiFailed("Android did not start the read")
        }
        return false
    }

    /// The request sent is answered: send the next.
    private func finish() {
        current = nil
        startNext()
    }

    /// The elements of a `java.util.List`.
    private func elements<Element>(of list: List<Element>?) -> [Element] {
        guard let list else { return [] }
        return (0..<list.size()).compactMap { list.get($0) }
    }

    // MARK: From Android

    func connectionStateChanged(status: Int32, newState: Int32) {
        guard let peripheral else { return }
        if newState == Self.stateConnected, status == GattStatus.success.rawValue {
            isConnected = true
            peripheral.didConnect()
            startNext()
            return
        }
        guard newState == Self.stateDisconnected || status != GattStatus.success.rawValue else { return }
        let wasConnected = isConnected
        let asked = peripheral.connectionState == .disconnecting
        central.connectionEnded(self)
        let reason = GattConnectionStatus(rawValue: status)?.description ?? "status \(status)"
        if !wasConnected && !asked {
            peripheral.didFailToConnect(.connectionFailed(reason))
        } else {
            peripheral.didDisconnect(error: asked ? nil : .connectionLost(reason))
        }
    }

    func servicesDiscovered(status: Int32) {
        guard case .discoverServices(let uuids) = current else { return }
        defer { finish() }
        guard let peripheral, let gatt else { return }
        guard status == GattStatus.success.rawValue else {
            peripheral.error = .discoveryFailed(GattStatus.describe(status))
            return
        }
        var listed: [BluetoothService] = []
        for native in elements(of: gatt.getServices()) {
            let id = native.getInstanceId()
            if let known = services[id] {
                listed.append(known)
                continue
            }
            guard let uuid = native.getUuid().flatMap({ BluetoothUUID(uuidString: $0.toString()) }) else { continue }
            // A filtered discovery adds to the services found before, as
            // CoreBluetooth's does.
            guard uuids?.contains(uuid) ?? true else { continue }
            let service = BluetoothService(
                native: native,
                uuid: uuid,
                isPrimary: native.getType() == 0,
                peripheral: peripheral
            )
            services[id] = service
            listed.append(service)
        }
        peripheral.services = listed
    }

    /// Android 12 and up: the device's services changed, and the ones found
    /// are gone.
    func servicesChanged() {
        services = [:]
        characteristics = [:]
        peripheral?.services = []
    }

    /// `service`'s characteristics with any of `uuids` (all with `nil`), from
    /// what the service discovery found, added to the ones listed before.
    func listCharacteristics(_ uuids: [BluetoothUUID]?, of service: BluetoothService) {
        var listed: [BluetoothCharacteristic] = []
        for native in elements(of: service.native.getCharacteristics()) {
            let id = native.getInstanceId()
            if let known = characteristics[id] {
                listed.append(known)
                continue
            }
            guard let uuid = native.getUuid().flatMap({ BluetoothUUID(uuidString: $0.toString()) }),
                  uuids?.contains(uuid) ?? true
            else { continue }
            let characteristic = BluetoothCharacteristic(
                native: native,
                uuid: uuid,
                // Android's property bits are GATT's.
                properties: GATTCharacteristicProperties(rawValue: UInt8(truncatingIfNeeded: native.getProperties())),
                service: service
            )
            characteristics[id] = characteristic
            listed.append(characteristic)
        }
        service.error = nil
        service.characteristics = listed
    }

    func read(_ native: BluetoothGattCharacteristic, value: [Int8], status: Int32) {
        let characteristic = characteristics[native.getInstanceId()]
        if case .read(let asked) = current, asked === characteristic {
            finish()
        }
        guard let characteristic else { return }
        guard status == GattStatus.success.rawValue else {
            characteristic.error = .readFailed(GattStatus.describe(status))
            return
        }
        characteristic.error = nil
        characteristic.value = Data(value.map { UInt8(bitPattern: $0) })
    }

    func wrote(_ native: BluetoothGattCharacteristic, status: Int32) {
        let characteristic = characteristics[native.getInstanceId()]
        if case .write(let asked, _, _) = current, asked === characteristic {
            finish()
        }
        characteristic?.error = status == GattStatus.success.rawValue ? nil : .writeFailed(GattStatus.describe(status))
    }

    /// A notification or an indication.
    func changed(_ native: BluetoothGattCharacteristic, value: [Int8]) {
        guard let characteristic = characteristics[native.getInstanceId()] else { return }
        characteristic.value = Data(value.map { UInt8(bitPattern: $0) })
    }

    func notificationStateWritten(_ native: BluetoothGattCharacteristic, status: Int32) {
        guard case .setNotifying(let characteristic, let enabled) = current,
              characteristic === characteristics[native.getInstanceId()]
        else { return }
        finish()
        guard status == GattStatus.success.rawValue else {
            characteristic.error = .notificationFailed(GattStatus.describe(status))
            return
        }
        characteristic.error = nil
        characteristic.isNotifying = enabled
    }

    func readRSSI(_ rssi: Int32, status: Int32) {
        guard case .readRSSI = current else { return }
        finish()
        guard let peripheral else { return }
        guard status == GattStatus.success.rawValue else {
            peripheral.error = .rssiFailed(GattStatus.describe(status))
            return
        }
        peripheral.update(\.rssi, RSSI(rawValue: Int8(clamping: rssi)))
    }
}

// MARK: - Android's statuses

/// The status a GATT request is answered with: `BluetoothGatt.GATT_*`, the
/// ATT error codes, and the stack's own failure.
enum GattStatus: Int32 {
    case success = 0
    case readNotPermitted = 2
    case writeNotPermitted = 3
    case insufficientAuthentication = 5
    case requestNotSupported = 6
    case invalidOffset = 7
    case insufficientAuthorization = 8
    case invalidAttributeLength = 13
    case insufficientEncryption = 15
    case error = 133
    case connectionCongested = 143
    case failure = 257

    var description: String {
        switch self {
        case .success: "success"
        case .readNotPermitted: "reading is not permitted"
        case .writeNotPermitted: "writing is not permitted"
        case .insufficientAuthentication: "the device wants the connection paired"
        case .requestNotSupported: "the device does not support the request"
        case .invalidOffset: "invalid offset"
        case .insufficientAuthorization: "the device does not allow it"
        case .invalidAttributeLength: "the value has the wrong length"
        case .insufficientEncryption: "the device wants the connection encrypted"
        case .error: "GATT error"
        case .connectionCongested: "the connection is congested"
        case .failure: "GATT failure"
        }
    }

    static func describe(_ status: Int32) -> String {
        "\(GattStatus(rawValue: status)?.description ?? "GATT status") (\(status))"
    }
}

/// The status a connection ends with: the link layer's reason, or the
/// stack's own failure.
enum GattConnectionStatus: Int32 {
    case success = 0
    case connectionTimeout = 8
    case remoteTerminated = 19
    case localTerminated = 22
    case failedToEstablish = 62
    case error = 133

    var description: String {
        switch self {
        case .success: "disconnected (0)"
        case .connectionTimeout: "the device stopped answering (8)"
        case .remoteTerminated: "the device ended the connection (19)"
        case .localTerminated: "Android ended the connection (22)"
        case .failedToEstablish: "the connection could not be set up (62)"
        case .error: "GATT error (133)"
        }
    }
}
#endif
