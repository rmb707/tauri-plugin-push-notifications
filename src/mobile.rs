use tauri::{plugin::PluginApi, AppHandle, Runtime};

#[cfg(target_os = "ios")]
tauri::ios_plugin_binding!(init_plugin_push_notifications);

pub fn init<R: Runtime>(
    _app: &AppHandle<R>,
    api: PluginApi<R, ()>,
) -> crate::Result<()> {
    #[cfg(target_os = "android")]
    {
        let _handle = api.register_android_plugin("push.notifications", "PushNotificationsPlugin")?;
    }
    #[cfg(target_os = "ios")]
    {
        let _handle = api.register_ios_plugin(init_plugin_push_notifications)?;
    }
    Ok(())
}
