package push.notifications

import android.Manifest
import android.app.Activity
import android.webkit.WebView
import app.tauri.annotation.Command
import app.tauri.annotation.Permission
import app.tauri.annotation.PermissionCallback
import app.tauri.annotation.TauriPlugin
import app.tauri.plugin.Invoke
import app.tauri.plugin.JSObject
import app.tauri.plugin.Plugin
import com.google.firebase.messaging.FirebaseMessaging

/**
 * Tauri v2 plugin for native push notifications on Android.
 *
 * On load, fetches the current FCM token and forwards it to Rust via JNI.
 * Handles POST_NOTIFICATIONS permission for Android 13+.
 */
@TauriPlugin(
    permissions = [
        Permission(
            strings = [Manifest.permission.POST_NOTIFICATIONS],
            alias = "notifications"
        )
    ]
)
class PushNotificationsPlugin(private val activity: Activity) : Plugin(activity) {

    override fun load(webView: WebView) {
        super.load(webView)

        // Fetch initial FCM token and forward to Rust via JNI
        FirebaseMessaging.getInstance().token.addOnSuccessListener { token ->
            PushNotificationsBridge.setToken(token)
        }
    }

    @Command
    fun requestPermission(invoke: Invoke) {
        val state = getPermissionState("notifications")
        if (state.toString() == "granted") {
            val result = JSObject()
            result.put("granted", true)
            invoke.resolve(result)
        } else {
            requestPermissionForAlias("notifications", invoke, "onPermissionResult")
        }
    }

    @PermissionCallback
    fun onPermissionResult(invoke: Invoke) {
        val granted = getPermissionState("notifications").toString() == "granted"
        val result = JSObject()
        result.put("granted", granted)
        invoke.resolve(result)
    }

    @Command
    fun getToken(invoke: Invoke) {
        FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
            if (!task.isSuccessful) {
                invoke.reject("Failed to get FCM token: ${task.exception?.message}")
                return@addOnCompleteListener
            }
            val token = task.result
            if (token != null) {
                PushNotificationsBridge.setToken(token)
            }
            val result = JSObject()
            result.put("token", token ?: "")
            invoke.resolve(result)
        }
    }
}
