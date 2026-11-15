//
//  BluetoothJava+Android.swift
//  NucleantBluetooth
//
//  swift-java wrappers for what the Android central calls: the framework's
//  android.bluetooth classes, and the helpers in Android/java that Android's
//  callbacks come back through.
//
//  Written by hand, method by method, rather than generated: only what is
//  called is declared. Each `@JavaMethod` is looked up by its name and the
//  JNI signature its Swift types spell, so they name the exact Java types.
//  A method that can throw (a SecurityException without the permission)
//  is `throws`.
//
//  All of them are made and used on the main thread, where Android calls
//  back: a wrapper keeps the JNIEnv of the thread that made it.
//

#if os(Android)
import SwiftJava

// MARK: - android.content / android.app / android.os

@JavaClass("android.content.Context")
class Context: JavaObject {
    /// `Object getSystemService(String)`; cast the result with `as(_:)`.
    @JavaMethod
    func getSystemService(_ name: String) -> JavaObject!

    @JavaMethod
    func checkSelfPermission(_ permission: String) -> Int32
}

@JavaClass("android.app.Activity")
class Activity: Context {
    @JavaMethod
    func requestPermissions(_ permissions: [String], _ requestCode: Int32)
}

@JavaClass("android.os.Build$VERSION")
class BuildVersion: JavaObject {}

extension JavaClass<BuildVersion> {
    @JavaStaticField(isFinal: true)
    var SDK_INT: Int32
}

// MARK: - android.bluetooth

/// `android.bluetooth.BluetoothManager`, the system service. Named apart
/// from NucleantBluetooth's own `BluetoothManager`.
@JavaClass("android.bluetooth.BluetoothManager")
class AndroidBluetoothManager: JavaObject {
    @JavaMethod
    func getAdapter() -> BluetoothAdapter!
}

@JavaClass("android.bluetooth.BluetoothAdapter")
class BluetoothAdapter: JavaObject {
    @JavaMethod
    func getState() -> Int32
}

@JavaClass("android.bluetooth.BluetoothDevice")
class BluetoothDevice: JavaObject {
    @JavaMethod
    func getAddress() -> String

    /// Empty when the device has no name yet.
    @JavaMethod
    func getName() throws -> String
}

@JavaClass("android.bluetooth.BluetoothGatt")
class BluetoothGatt: JavaObject {
    @JavaMethod
    func discoverServices() throws -> Bool

    @JavaMethod
    func getServices() -> List<BluetoothGattService>!

    @JavaMethod
    func readCharacteristic(_ characteristic: BluetoothGattCharacteristic?) throws -> Bool

    @JavaMethod
    func readRemoteRssi() throws -> Bool

    @JavaMethod
    func disconnect() throws

    @JavaMethod
    func close() throws
}

@JavaClass("android.bluetooth.BluetoothGattService")
class BluetoothGattService: JavaObject {
    @JavaMethod
    func getUuid() -> JavaUUID!

    /// `SERVICE_TYPE_PRIMARY` (0) or `SERVICE_TYPE_SECONDARY` (1).
    @JavaMethod
    func getType() -> Int32

    /// Its attribute handle: unique on the connection.
    @JavaMethod
    func getInstanceId() -> Int32

    @JavaMethod
    func getCharacteristics() -> List<BluetoothGattCharacteristic>!
}

@JavaClass("android.bluetooth.BluetoothGattCharacteristic")
class BluetoothGattCharacteristic: JavaObject {
    @JavaMethod
    func getUuid() -> JavaUUID!

    /// GATT's property bits, `PROPERTY_*`.
    @JavaMethod
    func getProperties() -> Int32

    /// Its attribute handle: unique on the connection.
    @JavaMethod
    func getInstanceId() -> Int32
}

@JavaClass("android.bluetooth.le.ScanResult")
class ScanResult: JavaObject {
    @JavaMethod
    func getDevice() -> BluetoothDevice!

    @JavaMethod
    func getRssi() -> Int32

    @JavaMethod
    func getScanRecord() -> ScanRecord!

    @JavaMethod
    func isConnectable() -> Bool
}

@JavaClass("android.bluetooth.le.ScanRecord")
class ScanRecord: JavaObject {
    /// The advertising data as sent, the scan response after it.
    @JavaMethod
    func getBytes() -> [Int8]
}

/// `java.util.UUID`; `toString()` is its 128-bit form.
@JavaClass("java.util.UUID")
class JavaUUID: JavaObject {}

// MARK: - Android/java
//
// The `native` methods take Java objects as `JavaObject` and cast them:
// `@JavaImplementation` makes its JNI entry points public, and a public
// function can't name these internal wrappers. JNI finds a native by its
// name alone, so the parameter's Swift type is free.

@JavaClass("org.nucleantui.bluetooth.BluetoothAppContext")
class BluetoothAppContext: JavaObject {}

extension JavaClass<BluetoothAppContext> {
    @JavaStaticMethod
    func context() -> Context!

    @JavaStaticMethod
    func resumedActivity() -> Activity!

    @JavaStaticMethod
    func scanNeedsLocation() -> Bool

    @JavaStaticMethod
    func locationIsOn() -> Bool

    @JavaStaticMethod
    func addResumeListener(_ handle: Int64)

    @JavaStaticMethod
    func removeResumeListener(_ handle: Int64)
}

@JavaImplementation("org.nucleantui.bluetooth.BluetoothAppContext")
extension BluetoothAppContext {
    @JavaMethod
    static func nativeActivityResumed(_ handle: Int64, environment: JNIEnvironment) {
        NativeHandle<BluetoothCentral>.owner(handle)?.activityResumed()
    }
}

@JavaClass("org.nucleantui.bluetooth.AdapterStateReceiver")
class AdapterStateReceiver: JavaObject {
    @JavaMethod
    convenience init(_ handle: Int64, environment: JNIEnvironment? = nil)

    @JavaMethod
    func register(_ context: Context?)

    @JavaMethod
    func unregister(_ context: Context?)

    @JavaMethod
    func disarm()
}

@JavaImplementation("org.nucleantui.bluetooth.AdapterStateReceiver")
extension AdapterStateReceiver {
    @JavaMethod
    static func nativeOnStateChanged(_ handle: Int64, _ state: Int32, environment: JNIEnvironment) {
        NativeHandle<BluetoothCentral>.owner(handle)?.adapterStateChanged(state)
    }
}

@JavaClass("org.nucleantui.bluetooth.ScanCallbacks")
class ScanCallbacks: JavaObject {
    @JavaMethod
    convenience init(_ handle: Int64, environment: JNIEnvironment? = nil)

    @JavaMethod
    func start(_ adapter: BluetoothAdapter?, _ services: [String]) -> Bool

    @JavaMethod
    func stop(_ adapter: BluetoothAdapter?)

    @JavaMethod
    func disarm()
}

@JavaImplementation("org.nucleantui.bluetooth.ScanCallbacks")
extension ScanCallbacks {
    @JavaMethod
    static func nativeOnScanResult(_ handle: Int64, _ result: JavaObject?, environment: JNIEnvironment) {
        guard let result = result?.as(ScanResult.self) else { return }
        NativeHandle<BluetoothCentral>.owner(handle)?.scanned(result)
    }

    @JavaMethod
    static func nativeOnScanFailed(_ handle: Int64, _ errorCode: Int32, environment: JNIEnvironment) {
        NativeHandle<BluetoothCentral>.owner(handle)?.scanFailed(errorCode)
    }
}

@JavaClass("org.nucleantui.bluetooth.GattCallbacks")
class GattCallbacks: JavaObject {
    @JavaMethod
    convenience init(_ handle: Int64, environment: JNIEnvironment? = nil)

    @JavaMethod
    func connect(_ context: Context?, _ device: BluetoothDevice?) -> BluetoothGatt!

    @JavaMethod
    func disarm()
}

extension JavaClass<GattCallbacks> {
    @JavaStaticMethod
    func write(
        _ gatt: BluetoothGatt?,
        _ characteristic: BluetoothGattCharacteristic?,
        _ value: [Int8],
        _ withResponse: Bool
    ) -> Bool

    /// 0: started; 1: no Client Characteristic Configuration descriptor;
    /// 2: Android would not start it.
    @JavaStaticMethod
    func setNotifying(_ gatt: BluetoothGatt?, _ characteristic: BluetoothGattCharacteristic?, _ enabled: Bool) -> Int32
}

@JavaImplementation("org.nucleantui.bluetooth.GattCallbacks")
extension GattCallbacks {
    @JavaMethod
    static func nativeOnConnectionStateChange(_ handle: Int64, _ status: Int32, _ newState: Int32, environment: JNIEnvironment) {
        NativeHandle<GattConnection>.owner(handle)?.connectionStateChanged(status: status, newState: newState)
    }

    @JavaMethod
    static func nativeOnServicesDiscovered(_ handle: Int64, _ status: Int32, environment: JNIEnvironment) {
        NativeHandle<GattConnection>.owner(handle)?.servicesDiscovered(status: status)
    }

    @JavaMethod
    static func nativeOnServiceChanged(_ handle: Int64, environment: JNIEnvironment) {
        NativeHandle<GattConnection>.owner(handle)?.servicesChanged()
    }

    @JavaMethod
    static func nativeOnCharacteristicRead(
        _ handle: Int64,
        _ characteristic: JavaObject?,
        _ value: [Int8],
        _ status: Int32,
        environment: JNIEnvironment
    ) {
        guard let characteristic = characteristic?.as(BluetoothGattCharacteristic.self) else { return }
        NativeHandle<GattConnection>.owner(handle)?.read(characteristic, value: value, status: status)
    }

    @JavaMethod
    static func nativeOnCharacteristicWrite(
        _ handle: Int64,
        _ characteristic: JavaObject?,
        _ status: Int32,
        environment: JNIEnvironment
    ) {
        guard let characteristic = characteristic?.as(BluetoothGattCharacteristic.self) else { return }
        NativeHandle<GattConnection>.owner(handle)?.wrote(characteristic, status: status)
    }

    @JavaMethod
    static func nativeOnCharacteristicChanged(
        _ handle: Int64,
        _ characteristic: JavaObject?,
        _ value: [Int8],
        environment: JNIEnvironment
    ) {
        guard let characteristic = characteristic?.as(BluetoothGattCharacteristic.self) else { return }
        NativeHandle<GattConnection>.owner(handle)?.changed(characteristic, value: value)
    }

    @JavaMethod
    static func nativeOnNotificationStateWritten(
        _ handle: Int64,
        _ characteristic: JavaObject?,
        _ status: Int32,
        environment: JNIEnvironment
    ) {
        guard let characteristic = characteristic?.as(BluetoothGattCharacteristic.self) else { return }
        NativeHandle<GattConnection>.owner(handle)?.notificationStateWritten(characteristic, status: status)
    }

    @JavaMethod
    static func nativeOnReadRemoteRssi(_ handle: Int64, _ rssi: Int32, _ status: Int32, environment: JNIEnvironment) {
        NativeHandle<GattConnection>.owner(handle)?.readRSSI(rssi, status: status)
    }
}

// MARK: - Handles

/// The `long` a Java helper carries back into Swift: a retained box holding
/// its Swift owner weakly, so a callback that comes after the owner is gone
/// finds `nil` instead of freed memory. The box lives until `release(_:)`,
/// which the owner calls once it has disarmed the helper.
final class NativeHandle<Owner: AnyObject>: @unchecked Sendable {
    private weak var owner: Owner?

    private init(_ owner: Owner) {
        self.owner = owner
    }

    static func retain(_ owner: Owner) -> Int64 {
        Int64(Int(bitPattern: Unmanaged.passRetained(NativeHandle(owner)).toOpaque()))
    }

    static func owner(_ handle: Int64) -> Owner? {
        guard let pointer = UnsafeRawPointer(bitPattern: Int(handle)) else { return nil }
        return Unmanaged<NativeHandle<Owner>>.fromOpaque(pointer).takeUnretainedValue().owner
    }

    static func release(_ handle: Int64) {
        guard let pointer = UnsafeRawPointer(bitPattern: Int(handle)) else { return }
        Unmanaged<NativeHandle<Owner>>.fromOpaque(pointer).release()
    }
}
#endif
