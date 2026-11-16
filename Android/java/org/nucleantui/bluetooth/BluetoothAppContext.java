package org.nucleantui.bluetooth;

import android.app.Activity;
import android.app.Application;
import android.content.ContentProvider;
import android.content.ContentValues;
import android.content.Context;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.database.Cursor;
import android.location.LocationManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;

import java.lang.ref.WeakReference;
import java.util.concurrent.CopyOnWriteArrayList;

/**
 * NucleantBluetooth's way into the app: the application Context, which the
 * Bluetooth system service comes from, and the Activity in front, which the
 * runtime permissions are asked on.
 *
 * <p>A ContentProvider because Android creates one with the app, before any
 * Activity, and hands it a Context. That is how a library starts without the
 * app having to call it. It provides no content. The app declares it inside
 * {@code <application>} in its manifest:
 *
 * <pre>
 * &lt;provider
 *     android:name="org.nucleantui.bluetooth.BluetoothAppContext"
 *     android:authorities="${applicationId}.nucleantbluetooth"
 *     android:exported="false" /&gt;
 * </pre>
 *
 * <p>Every {@code onResume} of an Activity is passed on to the Swift centrals
 * listening: the permission dialog pauses the Activity, and the user's answer
 * is in by the time it resumes.
 */
public final class BluetoothAppContext extends ContentProvider {
    private static Context context;
    private static WeakReference<Activity> resumed = new WeakReference<>(null);
    private static final CopyOnWriteArrayList<Long> resumeListeners = new CopyOnWriteArrayList<>();

    @Override
    public boolean onCreate() {
        Context app = getContext().getApplicationContext();
        context = app;
        ((Application) app).registerActivityLifecycleCallbacks(new Application.ActivityLifecycleCallbacks() {
            @Override
            public void onActivityResumed(Activity activity) {
                resumed = new WeakReference<>(activity);
                for (long handle : resumeListeners) {
                    nativeActivityResumed(handle);
                }
            }

            @Override
            public void onActivityPaused(Activity activity) {
                if (resumed.get() == activity) {
                    resumed = new WeakReference<>(null);
                }
            }

            @Override
            public void onActivityCreated(Activity activity, Bundle savedInstanceState) {}

            @Override
            public void onActivityStarted(Activity activity) {}

            @Override
            public void onActivityStopped(Activity activity) {}

            @Override
            public void onActivitySaveInstanceState(Activity activity, Bundle outState) {}

            @Override
            public void onActivityDestroyed(Activity activity) {}
        });
        return true;
    }

    /** The application Context; null when the provider is not in the manifest. */
    public static Context context() {
        return context;
    }

    /** The Activity in front, if one is. */
    public static Activity resumedActivity() {
        return resumed.get();
    }

    /**
     * Whether scan results need location access as well. Android only hands
     * them to an app with ACCESS_FINE_LOCATION, unless (from API 31) the app
     * declares BLUETOOTH_SCAN with {@code usesPermissionFlags="neverForLocation"}.
     */
    public static boolean scanNeedsLocation() {
        if (Build.VERSION.SDK_INT < 31) {
            return true;
        }
        try {
            PackageInfo info = context.getPackageManager()
                .getPackageInfo(context.getPackageName(), PackageManager.GET_PERMISSIONS);
            String[] names = info.requestedPermissions;
            int[] flags = info.requestedPermissionsFlags;
            for (int i = 0; names != null && i < names.length; i++) {
                if ("android.permission.BLUETOOTH_SCAN".equals(names[i])) {
                    return (flags[i] & PackageInfo.REQUESTED_PERMISSION_NEVER_FOR_LOCATION) == 0;
                }
            }
        } catch (PackageManager.NameNotFoundException e) {
            // Its own package: always there.
        }
        return true;
    }

    /**
     * Whether the device's location setting is on. Scan results that need
     * location access also need it on.
     */
    public static boolean locationIsOn() {
        LocationManager manager = (LocationManager) context.getSystemService(Context.LOCATION_SERVICE);
        return manager == null || manager.isLocationEnabled();
    }

    /** Pass every Activity resume to {@code handle} from now on. Main thread. */
    public static void addResumeListener(long handle) {
        resumeListeners.add(handle);
    }

    public static void removeResumeListener(long handle) {
        resumeListeners.remove(handle);
    }

    private static native void nativeActivityResumed(long handle);

    @Override
    public Cursor query(Uri uri, String[] projection, String selection, String[] selectionArgs, String sortOrder) {
        return null;
    }

    @Override
    public String getType(Uri uri) {
        return null;
    }

    @Override
    public Uri insert(Uri uri, ContentValues values) {
        return null;
    }

    @Override
    public int delete(Uri uri, String selection, String[] selectionArgs) {
        return 0;
    }

    @Override
    public int update(Uri uri, ContentValues values, String selection, String[] selectionArgs) {
        return 0;
    }
}
