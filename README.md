# tauri-plugin-push-notifications

Native push notifications for Tauri v2 mobile apps. Gets you FCM tokens on Android and APNs tokens on iOS with two commands.

---

## Quick Start

### 1. Add the dependency

In your app's `src-tauri/Cargo.toml`:

```toml
[target.'cfg(any(target_os = "android", target_os = "ios"))'.dependencies]
tauri-plugin-push-notifications = { git = "https://github.com/rmb707/tauri-plugin-push-notifications" }
```

### 2. Register the plugin

In your `src-tauri/src/lib.rs` (or `main.rs`):

```rust
fn main() {
    let mut builder = tauri::Builder::default();

    #[cfg(any(target_os = "android", target_os = "ios"))]
    {
        builder = builder.plugin(tauri_plugin_push_notifications::init());
    }

    builder
        .run(tauri::generate_context!())
        .expect("error running app");
}
```

### 3. Add capabilities

Create or update `src-tauri/capabilities/mobile.json`:

```json
{
  "identifier": "mobile",
  "platforms": ["android", "iOS"],
  "permissions": [
    "push-notifications:default"
  ]
}
```

### 4. Get tokens in JavaScript

Using the included TypeScript bindings:

```typescript
import { requestPermission, getToken } from "tauri-plugin-push-notifications-api";

const granted = await requestPermission();

// Token arrives asynchronously — retry a few times
let token = null;
for (let i = 0; i < 10; i++) {
  try {
    token = await getToken();
    break;
  } catch {
    await new Promise(r => setTimeout(r, 2000));
  }
}

if (token) {
  // Send to your backend
  await fetch("/api/register-device", {
    method: "POST",
    body: JSON.stringify({ token, platform: "android" }),
  });
}
```

Or use `invoke` directly:

```typescript
import { invoke } from "@tauri-apps/api/core";

await invoke("plugin:push-notifications|request_permission");
const token = await invoke<string>("plugin:push-notifications|get_token");
```

---

## Platform Setup

### Android

You need Firebase Cloud Messaging configured in your Android project.

**Step 1** — Get `google-services.json` from the [Firebase Console](https://console.firebase.google.com/) and place it in your Android app module directory:

```
src-tauri/gen/android/app/google-services.json
```

**Step 2** — Add the google-services plugin and Firebase dependency to your app's `build.gradle.kts`:

```kotlin
// src-tauri/gen/android/app/build.gradle.kts
plugins {
    id("com.google.gms.google-services")
}

dependencies {
    implementation("com.google.firebase:firebase-messaging:24.1.0")
}
```

And the classpath to your project's `build.gradle.kts`:

```kotlin
// src-tauri/gen/android/build.gradle.kts
buildscript {
    dependencies {
        classpath("com.google.gms:google-services:4.4.2")
    }
}
```

**Step 3** — Update the JNI library name in `PushNotificationsBridge.kt`. Open the file in the plugin's `android/` directory and change `NATIVE_LIB` to match the `[lib] name` in your app's `Cargo.toml`:

```kotlin
// If your Cargo.toml has: [lib] name = "my_app"
private const val NATIVE_LIB = "my_app"
```

**Step 4** *(optional)* — To receive push messages while the app is in the foreground, add a Firebase Messaging service to your app. See the [Firebase docs](https://firebase.google.com/docs/cloud-messaging/android/receive) for details.

### iOS

The plugin handles everything automatically:

- Requests notification permission via the system dialog
- Registers for remote notifications
- Intercepts APNs token delivery by swizzling the AppDelegate at runtime
- Forwards tokens to Rust via FFI

**The only thing you need to do:**

1. Open your Xcode project
2. Go to **Signing & Capabilities**
3. Click **+ Capability**
4. Add **Push Notifications**

That's it. No AppDelegate code needed, no manual token handling.

> Note: Push notifications only work on physical iOS devices, not simulators.

---

## How It Works

```
┌─────────────────────────────────────────────────┐
│                    Your App                      │
│                                                  │
│  JavaScript                                      │
│  ┌──────────────────────────────────────┐       │
│  │ await requestPermission()            │       │
│  │ const token = await getToken()       │       │
│  └────────────────┬─────────────────────┘       │
│                   │ Tauri IPC                     │
│  Rust             ▼                              │
│  ┌──────────────────────────────────────┐       │
│  │ PUSH_TOKEN: Mutex<Option<String>>    │       │
│  └──────┬───────────────────┬───────────┘       │
│         │ JNI               │ FFI                │
│  Android▼                   ▼ iOS                │
│  ┌──────────────┐   ┌──────────────────┐        │
│  │ Kotlin Plugin│   │ Swift Plugin     │        │
│  │ + FCM SDK    │   │ + AppDelegate    │        │
│  │              │   │   swizzle        │        │
│  └──────┬───────┘   └────────┬─────────┘        │
│         │                    │                   │
└─────────┼────────────────────┼───────────────────┘
          │                    │
          ▼                    ▼
   Firebase Cloud        Apple Push
   Messaging             Notification
                         service
```

**Token flow:**

1. JS calls `requestPermission` → native OS shows permission dialog
2. On grant, the OS registers with FCM/APNs and delivers a device token
3. The native plugin layer (Kotlin/Swift) receives the token
4. Token is forwarded to Rust via JNI (Android) or FFI (iOS)
5. Rust stores it in a global `Mutex<Option<String>>`
6. JS calls `getToken` → Rust returns the stored token

---

## Design Decisions

**Non-blocking `get_token`** — Returns immediately with the current token or an error. No sleeping, no polling. On iOS, Tauri runs plugin commands on the main thread, so any blocking would freeze the entire WebView.

**AppDelegate swizzling (iOS)** — When iOS gets an APNs token, it delivers it to `application:didRegisterForRemoteNotificationsWithDeviceToken:` on the AppDelegate. Tauri auto-generates the AppDelegate and doesn't implement this method. The plugin injects it at runtime using the Objective-C runtime so you don't have to touch any native code.

**Passive load** — The plugin does nothing on startup except prepare the iOS AppDelegate swizzle. Push registration only happens when your JS code explicitly calls `requestPermission`. This means the plugin never interferes with your app's startup.

---

## Debugging

### Android

```bash
adb logcat -s PushNotificationsBridge:D
```

You should see:
```
D PushNotificationsBridge: Token forwarded to Rust: dKx8f2mR...
```

### iOS

In Xcode's console, filter for `[push-notifications]`:

```
[push-notifications] Plugin loaded
[push-notifications] Adding didRegisterForRemoteNotificationsWithDeviceToken to AppDelegate
[push-notifications] Registering for remote notifications
[push-notifications] Received APNs device token (32 bytes)
[push-notifications] APNs token: a1b2c3d4e5f6...
```

---

## API Reference

### `requestPermission(): Promise<boolean>`

Requests push notification permission from the OS. On iOS, shows the system permission dialog on first call. On Android 13+, requests the `POST_NOTIFICATIONS` runtime permission. Returns `true` if granted.

### `getToken(): Promise<string>`

Returns the native push token. Throws if the token hasn't arrived yet. Call this after `requestPermission()` with retry logic since the token arrives asynchronously (typically 1-5 seconds).

---

## Requirements

- Tauri v2
- Android: Firebase project + `google-services.json`
- iOS: Push Notifications capability in Xcode
- Rust targets: `aarch64-linux-android`, `aarch64-apple-ios`

## License

MIT OR Apache-2.0
