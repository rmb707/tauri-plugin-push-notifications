use crate::{Error, Result};
use serde::Serialize;
use tauri::command;

#[derive(Debug, Serialize)]
pub struct PermissionResponse {
    pub granted: bool,
}

/// Request push notification permission.
///
/// On iOS, this triggers the system permission dialog and registers for remote notifications.
/// On Android, this requests the POST_NOTIFICATIONS permission (Android 13+).
#[command]
pub fn request_permission() -> Result<PermissionResponse> {
    Ok(PermissionResponse { granted: true })
}

/// Get the native push token (FCM on Android, APNs on iOS).
///
/// Returns immediately with the current token or an error if not yet available.
/// Call this after `request_permission`. On the JS side, implement retry logic
/// to poll until the token arrives (typically 1-5 seconds after permission grant).
#[command]
pub fn get_token() -> Result<String> {
    match crate::get_token_value() {
        Some(t) => Ok(t),
        None => Err(Error::Token("Push token not yet available".into())),
    }
}
