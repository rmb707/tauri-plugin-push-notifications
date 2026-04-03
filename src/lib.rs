//! # tauri-plugin-push-notifications
//!
//! Native push notifications for Tauri v2 mobile apps.
//!
//! Provides FCM (Android) and APNs (iOS) push token retrieval via a simple
//! two-command API: `request_permission` and `get_token`.
//!
//! ## How it works
//!
//! 1. Native platform code (Kotlin/Swift) receives push tokens from FCM/APNs
//! 2. Tokens are forwarded to Rust via JNI (Android) or FFI (iOS)
//! 3. Rust stores the token in a global `Mutex<Option<String>>`
//! 4. JavaScript retrieves the token via the `get_token` Tauri command
//!
//! ## Usage
//!
//! ```rust
//! fn main() {
//!     tauri::Builder::default()
//!         .plugin(tauri_plugin_push_notifications::init())
//!         .run(tauri::generate_context!())
//!         .expect("error while running tauri application");
//! }
//! ```

use std::sync::Mutex;

use tauri::{
    plugin::{Builder, TauriPlugin},
    Runtime,
};

mod commands;
mod error;

pub use error::{Error, Result};

#[cfg(mobile)]
mod mobile;

/// Global push token store. Written by native code (FFI/JNI), read by Tauri commands.
static PUSH_TOKEN: Mutex<Option<String>> = Mutex::new(None);

/// Store a push token (called from native side or from your own code).
pub fn set_token(token: String) {
    log::info!(
        "[push-notifications] Token set: {}...",
        &token[..token.len().min(12)]
    );
    *PUSH_TOKEN.lock().unwrap() = Some(token);
}

/// Retrieve the current push token, if available.
pub fn get_token_value() -> Option<String> {
    PUSH_TOKEN.lock().unwrap().clone()
}

// ── iOS FFI entry point ─────────────────────────────────────────────
// Called from Swift via @_silgen_name("push_notifications_set_token")

#[cfg(target_os = "ios")]
#[no_mangle]
pub extern "C" fn push_notifications_set_token(token: *const std::os::raw::c_char) {
    if token.is_null() {
        log::warn!("[push-notifications] set_token called with null");
        return;
    }
    let c_str = unsafe { std::ffi::CStr::from_ptr(token) };
    match c_str.to_str() {
        Ok(s) => set_token(s.to_string()),
        Err(e) => log::error!("[push-notifications] Invalid UTF-8 token: {}", e),
    }
}

// ── Android JNI entry point ─────────────────────────────────────────
// Called from Kotlin via PushNotificationsBridge.nativeSetToken()

#[cfg(target_os = "android")]
#[no_mangle]
pub extern "system" fn Java_push_notifications_PushNotificationsBridge_nativeSetToken(
    mut env: jni::JNIEnv,
    _class: jni::objects::JClass,
    token: jni::objects::JString,
) {
    let token_str: String = env
        .get_string(&token)
        .map(|s| s.into())
        .unwrap_or_default();
    if !token_str.is_empty() {
        set_token(token_str);
    }
}

// ── Tauri plugin builder ────────────────────────────────────────────

pub fn init<R: Runtime>() -> TauriPlugin<R> {
    Builder::<R, ()>::new("push-notifications")
        .invoke_handler(tauri::generate_handler![
            commands::request_permission,
            commands::get_token,
        ])
        .setup(|app, api| {
            #[cfg(mobile)]
            mobile::init(app, api)?;
            #[cfg(not(mobile))]
            let _ = (app, api);
            Ok(())
        })
        .build()
}
