package org.nucleantui.bluetooth;

import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothGatt;
import android.bluetooth.BluetoothGattCallback;
import android.bluetooth.BluetoothGattCharacteristic;
import android.bluetooth.BluetoothGattDescriptor;
import android.bluetooth.BluetoothStatusCodes;
import android.content.Context;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;

import java.util.UUID;

/**
 * One connection of a Swift central. BluetoothGattCallback is an abstract
 * class, which Swift cannot subclass, so this one forwards every callback to
 * Swift with the connection's {@code handle}. {@link #disarm()} zeroes it
 * before the handle is released.
 *
 * <p>{@link #connect} has Android call back on the main thread. The static
 * methods are the GATT calls whose form changed in API 33; they pick the one
 * the device has.
 */
public final class GattCallbacks extends BluetoothGattCallback {
    /** The Client Characteristic Configuration descriptor. */
    private static final UUID CLIENT_CONFIGURATION = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb");

    private long handle;

    public GattCallbacks(long handle) {
        this.handle = handle;
    }

    public void disarm() {
        handle = 0;
    }

    /** Connect to {@code device} over LE, with the callbacks on the main thread. */
    public BluetoothGatt connect(Context context, BluetoothDevice device) {
        try {
            return device.connectGatt(
                context, false, this,
                BluetoothDevice.TRANSPORT_LE, BluetoothDevice.PHY_LE_1M_MASK,
                new Handler(Looper.getMainLooper()));
        } catch (RuntimeException e) {
            android.util.Log.w("NucleantBluetooth", "connectGatt failed", e);
            return null;
        }
    }

    /** Write {@code value}; false when Android would not start the write. */
    @SuppressWarnings("deprecation")
    public static boolean write(BluetoothGatt gatt, BluetoothGattCharacteristic characteristic, byte[] value, boolean withResponse) {
        int type = withResponse
            ? BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
            : BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE;
        try {
            if (Build.VERSION.SDK_INT >= 33) {
                return gatt.writeCharacteristic(characteristic, value, type) == BluetoothStatusCodes.SUCCESS;
            }
            characteristic.setWriteType(type);
            characteristic.setValue(value);
            return gatt.writeCharacteristic(characteristic);
        } catch (RuntimeException e) {
            android.util.Log.w("NucleantBluetooth", "writeCharacteristic failed", e);
            return false;
        }
    }

    /**
     * Turn notifications (or indications, when the characteristic only has
     * those) on or off: locally, then on the device by writing its Client
     * Characteristic Configuration descriptor. 0 when the write started, 1
     * when the characteristic has no such descriptor, 2 when Android would
     * not start it.
     */
    @SuppressWarnings("deprecation")
    public static int setNotifying(BluetoothGatt gatt, BluetoothGattCharacteristic characteristic, boolean enabled) {
        BluetoothGattDescriptor descriptor = characteristic.getDescriptor(CLIENT_CONFIGURATION);
        if (descriptor == null) {
            return 1;
        }
        byte[] value;
        if (!enabled) {
            value = BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE;
        } else if ((characteristic.getProperties() & BluetoothGattCharacteristic.PROPERTY_NOTIFY) != 0) {
            value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE;
        } else {
            value = BluetoothGattDescriptor.ENABLE_INDICATION_VALUE;
        }
        try {
            if (!gatt.setCharacteristicNotification(characteristic, enabled)) {
                return 2;
            }
            if (Build.VERSION.SDK_INT >= 33) {
                return gatt.writeDescriptor(descriptor, value) == BluetoothStatusCodes.SUCCESS ? 0 : 2;
            }
            descriptor.setValue(value);
            return gatt.writeDescriptor(descriptor) ? 0 : 2;
        } catch (RuntimeException e) {
            android.util.Log.w("NucleantBluetooth", "setCharacteristicNotification failed", e);
            return 2;
        }
    }

    @Override
    public void onConnectionStateChange(BluetoothGatt gatt, int status, int newState) {
        if (handle != 0) {
            nativeOnConnectionStateChange(handle, status, newState);
        }
    }

    @Override
    public void onServicesDiscovered(BluetoothGatt gatt, int status) {
        if (handle != 0) {
            nativeOnServicesDiscovered(handle, status);
        }
    }

    @Override
    public void onServiceChanged(BluetoothGatt gatt) {
        if (handle != 0) {
            nativeOnServiceChanged(handle);
        }
    }

    /** API 33 and up: the value comes with the callback. */
    @Override
    public void onCharacteristicRead(BluetoothGatt gatt, BluetoothGattCharacteristic characteristic, byte[] value, int status) {
        if (handle != 0) {
            nativeOnCharacteristicRead(handle, characteristic, value, status);
        }
    }

    /** Below API 33. From 33 on Android calls the one above instead. */
    @SuppressWarnings("deprecation")
    @Override
    public void onCharacteristicRead(BluetoothGatt gatt, BluetoothGattCharacteristic characteristic, int status) {
        if (handle != 0 && Build.VERSION.SDK_INT < 33) {
            nativeOnCharacteristicRead(handle, characteristic, characteristic.getValue(), status);
        }
    }

    @Override
    public void onCharacteristicWrite(BluetoothGatt gatt, BluetoothGattCharacteristic characteristic, int status) {
        if (handle != 0) {
            nativeOnCharacteristicWrite(handle, characteristic, status);
        }
    }

    /** API 33 and up. */
    @Override
    public void onCharacteristicChanged(BluetoothGatt gatt, BluetoothGattCharacteristic characteristic, byte[] value) {
        if (handle != 0) {
            nativeOnCharacteristicChanged(handle, characteristic, value);
        }
    }

    /** Below API 33. */
    @SuppressWarnings("deprecation")
    @Override
    public void onCharacteristicChanged(BluetoothGatt gatt, BluetoothGattCharacteristic characteristic) {
        if (handle != 0 && Build.VERSION.SDK_INT < 33) {
            nativeOnCharacteristicChanged(handle, characteristic, characteristic.getValue());
        }
    }

    @Override
    public void onDescriptorWrite(BluetoothGatt gatt, BluetoothGattDescriptor descriptor, int status) {
        if (handle != 0 && CLIENT_CONFIGURATION.equals(descriptor.getUuid())) {
            nativeOnNotificationStateWritten(handle, descriptor.getCharacteristic(), status);
        }
    }

    @Override
    public void onReadRemoteRssi(BluetoothGatt gatt, int rssi, int status) {
        if (handle != 0) {
            nativeOnReadRemoteRssi(handle, rssi, status);
        }
    }

    private static native void nativeOnConnectionStateChange(long handle, int status, int newState);

    private static native void nativeOnServicesDiscovered(long handle, int status);

    private static native void nativeOnServiceChanged(long handle);

    private static native void nativeOnCharacteristicRead(long handle, BluetoothGattCharacteristic characteristic, byte[] value, int status);

    private static native void nativeOnCharacteristicWrite(long handle, BluetoothGattCharacteristic characteristic, int status);

    private static native void nativeOnCharacteristicChanged(long handle, BluetoothGattCharacteristic characteristic, byte[] value);

    private static native void nativeOnNotificationStateWritten(long handle, BluetoothGattCharacteristic characteristic, int status);

    private static native void nativeOnReadRemoteRssi(long handle, int rssi, int status);
}
