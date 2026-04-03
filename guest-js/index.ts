import { invoke } from "@tauri-apps/api/core";

/**
 * Request push notification permission.
 *
 * On iOS, this triggers the system permission dialog and registers for remote notifications.
 * On Android 13+, this requests the POST_NOTIFICATIONS runtime permission.
 *
 * @returns Whether permission was granted
 */
export async function requestPermission(): Promise<boolean> {
  const result = await invoke<{ granted: boolean }>(
    "plugin:push-notifications|request_permission"
  );
  return result.granted;
}

/**
 * Get the native push token (FCM on Android, APNs on iOS).
 *
 * Returns the token if available, or throws if not yet received.
 * Call this after `requestPermission()`. The token may take 1-5 seconds
 * to arrive after permission is granted.
 *
 * @example
 * ```ts
 * await requestPermission();
 *
 * // Retry until token is available
 * let token: string | null = null;
 * for (let i = 0; i < 10; i++) {
 *   try {
 *     token = await getToken();
 *     break;
 *   } catch {
 *     await new Promise(r => setTimeout(r, 2000));
 *   }
 * }
 *
 * if (token) {
 *   // Send token to your server for push delivery
 *   await fetch('/api/push/register', {
 *     method: 'POST',
 *     body: JSON.stringify({ token, platform: 'android' | 'ios' }),
 *   });
 * }
 * ```
 */
export async function getToken(): Promise<string> {
  return await invoke<string>("plugin:push-notifications|get_token");
}
