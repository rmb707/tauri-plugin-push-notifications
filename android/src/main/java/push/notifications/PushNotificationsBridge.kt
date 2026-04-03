package push.notifications

import android.util.Log

/**
 * JNI bridge to forward push tokens from Kotlin to Rust.
 *
 * The native method is implemented in lib.rs as:
 *   Java_push_notifications_PushNotificationsBridge_nativeSetToken
 *
 * IMPORTANT: The System.loadLibrary name must match the [lib] name
 * in your app's Cargo.toml. Update "your_app_lib" to your actual library name.
 */
object PushNotificationsBridge {
    private const val TAG = "PushNotificationsBridge"

    // TODO: Change this to match [lib] name in your app's Cargo.toml
    private const val NATIVE_LIB = "app"

    init {
        try {
            System.loadLibrary(NATIVE_LIB)
        } catch (e: UnsatisfiedLinkError) {
            Log.w(TAG, "Native library '$NATIVE_LIB' not loaded: ${e.message}")
            Log.w(TAG, "Make sure NATIVE_LIB matches the [lib] name in your Cargo.toml")
        }
    }

    @JvmStatic
    private external fun nativeSetToken(token: String)

    @JvmStatic
    fun setToken(token: String) {
        try {
            nativeSetToken(token)
            Log.d(TAG, "Token forwarded to Rust: ${token.take(12)}...")
        } catch (e: Exception) {
            Log.w(TAG, "Failed to forward token: ${e.message}")
        }
    }
}
