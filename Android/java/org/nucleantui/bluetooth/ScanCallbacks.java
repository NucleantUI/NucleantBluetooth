package org.nucleantui.bluetooth;

import android.bluetooth.BluetoothAdapter;
import android.bluetooth.le.BluetoothLeScanner;
import android.bluetooth.le.ScanCallback;
import android.bluetooth.le.ScanFilter;
import android.bluetooth.le.ScanResult;
import android.bluetooth.le.ScanSettings;
import android.os.ParcelUuid;

import java.util.ArrayList;
import java.util.List;

/**
 * A Swift central's scan. ScanCallback is an abstract class, which Swift
 * cannot subclass, so this one forwards its results to Swift with the
 * central's {@code handle}. {@link #disarm()} zeroes it before the handle is
 * released. BluetoothLeScanner calls back on the main thread.
 */
public final class ScanCallbacks extends ScanCallback {
    private long handle;

    public ScanCallbacks(long handle) {
        this.handle = handle;
    }

    public void disarm() {
        handle = 0;
    }

    /**
     * Scan for devices advertising any of {@code services} (128-bit UUID
     * strings), or for every device when there are none. False when Android
     * would not start it: Bluetooth off, or the app not allowed to scan.
     */
    public boolean start(BluetoothAdapter adapter, String[] services) {
        BluetoothLeScanner scanner = adapter.getBluetoothLeScanner();
        if (scanner == null) {
            return false;
        }
        List<ScanFilter> filters = null;
        if (services.length > 0) {
            filters = new ArrayList<>();
            for (String service : services) {
                filters.add(new ScanFilter.Builder().setServiceUuid(ParcelUuid.fromString(service)).build());
            }
        }
        ScanSettings settings = new ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build();
        try {
            scanner.startScan(filters, settings, this);
            return true;
        } catch (RuntimeException e) {
            android.util.Log.w("NucleantBluetooth", "startScan failed", e);
            return false;
        }
    }

    public void stop(BluetoothAdapter adapter) {
        BluetoothLeScanner scanner = adapter.getBluetoothLeScanner();
        if (scanner == null) {
            return;
        }
        try {
            scanner.stopScan(this);
        } catch (RuntimeException e) {
            android.util.Log.w("NucleantBluetooth", "stopScan failed", e);
        }
    }

    @Override
    public void onScanResult(int callbackType, ScanResult result) {
        if (handle != 0) {
            nativeOnScanResult(handle, result);
        }
    }

    @Override
    public void onBatchScanResults(List<ScanResult> results) {
        for (ScanResult result : results) {
            if (handle == 0) {
                return;
            }
            nativeOnScanResult(handle, result);
        }
    }

    @Override
    public void onScanFailed(int errorCode) {
        if (handle != 0) {
            nativeOnScanFailed(handle, errorCode);
        }
    }

    private static native void nativeOnScanResult(long handle, ScanResult result);

    private static native void nativeOnScanFailed(long handle, int errorCode);
}
