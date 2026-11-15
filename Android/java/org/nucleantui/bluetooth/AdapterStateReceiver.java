package org.nucleantui.bluetooth;

import android.bluetooth.BluetoothAdapter;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;

/**
 * Receives {@code BluetoothAdapter.ACTION_STATE_CHANGED} (Bluetooth turning
 * on or off) for a Swift central. {@code handle} is the central's handle;
 * {@link #disarm()} zeroes it before the handle is released. Registered with
 * a main-Looper Handler, so called on the main thread only.
 */
public final class AdapterStateReceiver extends BroadcastReceiver {
    private long handle;

    public AdapterStateReceiver(long handle) {
        this.handle = handle;
    }

    public void register(Context context) {
        IntentFilter filter = new IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED);
        Handler main = new Handler(Looper.getMainLooper());
        // A system broadcast: the receiver needs no export to get it.
        int flags = Build.VERSION.SDK_INT >= 33 ? Context.RECEIVER_NOT_EXPORTED : 0;
        context.registerReceiver(this, filter, null, main, flags);
    }

    public void unregister(Context context) {
        context.unregisterReceiver(this);
    }

    public void disarm() {
        handle = 0;
    }

    @Override
    public void onReceive(Context context, Intent intent) {
        if (handle != 0) {
            nativeOnStateChanged(handle, intent.getIntExtra(BluetoothAdapter.EXTRA_STATE, BluetoothAdapter.ERROR));
        }
    }

    private static native void nativeOnStateChanged(long handle, int state);
}
