# NucleantBluetooth

Bluetooth Low Energy for NucleantUI apps, as a central: scan for the devices around, connect, discover services and characteristics, read, write and get notified. The values are [PureSwift/Bluetooth](https://github.com/PureSwift/Bluetooth)'s types (`BluetoothUUID`, `RSSI`, `CompanyIdentifier`, `GATTCharacteristicProperties`, the GAP and GATT definitions), which come along with `import NucleantBluetooth`.

Everything is an `@Observable` class: the manager, each peripheral, its services and their characteristics. A view rebuilds for the properties it read. A list of `ble.peripherals` rebuilds when a device is found, and a view given one peripheral rebuilds when that device's signal changes. The package has no views of its own. Its one piece of NucleantUI is the environment value the manager comes from:

```swift
@Environment(\.bluetoothManager) private var ble
```

## The API

- **`BluetoothManager`**: `state` (`.poweredOn`, `.poweredOff`, `.unauthorized`, …), `isScanning`, `peripherals`, `scan(for:allowDuplicates:)`, `stopScan()` and `removeDisconnectedPeripherals()`. A scan asked for before Bluetooth is on starts when it turns on, and a scan cut off by Bluetooth turning off starts again when it is back.
- **`BluetoothPeripheral`**: `name`, `rssi`, `lastSeen` and what the device advertises (`localName`, `manufacturerData`, `serviceUUIDs`, `serviceData`, `txPowerLevel`, `isConnectable`). Its connection is `connectionState`, `connect()`, `disconnect()` and `readRSSI()`, plus `discoverServices(_:)` into `services`.
- **`BluetoothService`**: `uuid`, `isPrimary`, and `discoverCharacteristics(_:)` into `characteristics`.
- **`BluetoothCharacteristic`**: `uuid`, `properties`, `value`, `isNotifying`, `read()`, `write(_:withResponse:)` and `setNotifying(_:)`. `value(as:)` decodes the value as one of PureSwift's GATT types, for example `characteristic.value(as: GATTBatteryLevel.self)`.

Requests don't throw. What they return lands on the object they were made on: a read in `value`, a discovery in `services`. A failure lands in that object's `error`. A standard UUID's name is `uuid.metadata?.name` ("Heart Rate"), and a company's is `companyIdentifier.name`.

Use the classes on the main thread. The system's answers arrive there too.

## Platforms

- **iOS**, over CoreBluetooth.
- **Android**, over `android.bluetooth` through [swift-java](https://github.com/swiftlang/swift-java).

macOS and Linux are still to come. Each platform has its own `BluetoothCentral+<Platform>.swift` behind the same API.

### Android

Android's callbacks come through abstract Java classes, which Swift can't subclass. [Android/java](Android/java) has a small Java helper for each one, and the app compiles them with its own Java. In a [nucleant](https://github.com/NucleantUI/NucleantProject) project, the app needs three things:

1. **The Java**, through `include_files` in nucleant.toml:

   ```toml
   include_files = [
       ["gradle/app/src/main/java/org/nucleantui", "<path to NucleantBluetooth>/Android/java/org/nucleantui/bluetooth"]
   ]
   ```

2. **The permissions**, in nucleant.toml's `permissions`:

   ```toml
   permissions = ["BLUETOOTH_SCAN", "BLUETOOTH_CONNECT", "ACCESS_FINE_LOCATION", "BLUETOOTH", "BLUETOOTH_ADMIN"]
   ```

   Android only hands scan results to an app with precise location. From Android 12 (API 31) that is waived when BLUETOOTH_SCAN is declared with `android:usesPermissionFlags="neverForLocation"` in the manifest. The central checks which way the app declared it and asks for what is needed when it starts: Nearby devices, plus location unless it is waived. Until they are given, `state` is `.unauthorized`. With location needed, the device's location setting has to be on as well.

3. **The provider**, inside `<application>` in AndroidManifest.tmpl.xml. Android creates it with the app, and it hands the central the app's Context and the Activity in front, which the permissions are asked on:

   ```xml
   <provider
       android:name="org.nucleantui.bluetooth.BluetoothAppContext"
       android:authorities="${applicationId}.nucleantbluetooth"
       android:exported="false" />
   ```

Android names a device by its address, so a peripheral's `id` is the address in the last six bytes of a UUID: `00000000-0000-0000-0000-AABBCCDDEEFF`. A connection takes one request at a time, so the central queues reads, writes and notification changes and sends each one when the last is answered. Android discovers the characteristics together with the services, so `discoverCharacteristics(_:)` lists them right away. Android also stops an app's scans for a while when they are started more than five times in 30 seconds.

PureSwift's names (`uuid.metadata?.name`, `companyIdentifier.name`) are read from its resource bundle, which `Bundle.module` can't find in an Android app on its own. The central points `Bundle.main` at the directory nucleant unpacks the bundles into (`NUCLEANT_APP_PATH`, through `CFProcessPath`) before anything reads it.

## Tests

The tests run in the iOS Simulator:

```sh
xcodebuild test -scheme NucleantBluetooth -destination 'platform=iOS Simulator,name=iPhone 17' -skipMacroValidation -skipPackagePluginValidation
```

`-skipMacroValidation` and `-skipPackagePluginValidation` stand in for Xcode's *Trust & Enable* prompts, for NucleantUI's macros and for PureSwift's code-generating build plugin. The tests cover the manager's state and scanning, the environment value, how CoreBluetooth's values map to NucleantBluetooth's, and the advertising data and identifiers Android hands over. The simulator has no Bluetooth, so finding and connecting to devices needs a real device.

The Android emulator does have Bluetooth: netsim, a virtual radio. [Bumble](https://github.com/google/bumble) can put fake peripherals on it, which the emulator finds and connects to like real ones.

## Demo

[Demo/](Demo) is a separate package: **BluetoothScanner**, a scanner app built on this one. It lists the devices around with their live signal strength and lets you sort and filter them. Each device has its own screen showing what it advertises. After you connect, the screen shows the device's services and characteristics, where you can read, write and turn on notifications.

[Demo/Xcode/BluetoothScanner.xcodeproj](Demo/Xcode/BluetoothScanner.xcodeproj) builds it as an iOS app. Open it, pick the **BluetoothScannerApp** scheme and your iPhone or iPad, and run.

- **Signing.** A device needs a team. Set it under *Signing & Capabilities*, or as `DEVELOPMENT_TEAM` in [Demo/Xcode/project.yml](Demo/Xcode/project.yml).
- **Trust & Enable.** The first build stops on the same two plugins until you choose *Trust & Enable* for each.
- **Changing the project.** `project.yml` is the source. Regenerate the checked-in project with [xcodegen](https://github.com/yonaskolb/XcodeGen): `cd Demo/Xcode && xcodegen`.
