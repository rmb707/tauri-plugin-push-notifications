import UIKit
import WebKit
import UserNotifications
import Tauri
import ObjectiveC

/// Tauri v2 plugin for native push notifications on iOS.
///
/// On load, swizzles the AppDelegate to intercept APNs token delivery.
/// When JS calls `requestPermission`, registers for remote notifications.
/// Tokens are forwarded to Rust via the `push_notifications_set_token` FFI function.
class PushNotificationsPlugin: Plugin {

    private var didRegister = false

    override func load(webview: WKWebView) {
        NSLog("[push-notifications] Plugin loaded")
        PushAppDelegateSwizzler.swizzle()
    }

    private func ensureRegistered() {
        guard !didRegister else { return }
        didRegister = true

        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound]
        ) { granted, error in
            if let error = error {
                NSLog("[push-notifications] Permission error: \(error)")
                return
            }
            if granted {
                DispatchQueue.main.async {
                    NSLog("[push-notifications] Registering for remote notifications")
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }

    @objc func requestPermission(_ invoke: Invoke) {
        ensureRegistered()
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let granted = settings.authorizationStatus == .authorized ||
                          settings.authorizationStatus == .provisional
            invoke.resolve(["granted": granted])
        }
    }

    // NOTE: No getToken handler here. The Rust command handles token retrieval
    // from the global store. If we defined getToken in Swift, Tauri would dispatch
    // to it instead of Rust, and we'd always return "" instead of the real token.
}

@_cdecl("init_plugin_push_notifications")
func initPlugin() -> Plugin {
    return PushNotificationsPlugin()
}

// MARK: - FFI bridge to Rust

/// Declared in Rust lib.rs as #[no_mangle] extern "C" fn push_notifications_set_token
@_silgen_name("push_notifications_set_token")
private func push_notifications_set_token(_ token: UnsafePointer<CChar>)

/// Convert Data token to hex string and forward to Rust
func handleAPNsToken(_ deviceToken: Data) {
    let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
    NSLog("[push-notifications] APNs token: \(token.prefix(12))...")
    let cToken = (token as NSString).utf8String!
    push_notifications_set_token(cToken)
}

// MARK: - AppDelegate Swizzling

/// Swizzles UIApplicationDelegate to intercept didRegisterForRemoteNotificationsWithDeviceToken.
///
/// Tauri's auto-generated AppDelegate doesn't implement this method, so APNs tokens
/// would otherwise be silently dropped. This injects the method at runtime using the
/// Objective-C runtime.
class PushAppDelegateSwizzler: NSObject {
    private static var didSwizzle = false

    static func swizzle() {
        guard !didSwizzle else { return }
        didSwizzle = true

        guard let appDelegate = UIApplication.shared.delegate else {
            NSLog("[push-notifications] No app delegate found")
            return
        }

        let appDelegateClass: AnyClass = type(of: appDelegate)
        let selector = #selector(UIApplicationDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:))

        if class_getInstanceMethod(appDelegateClass, selector) != nil {
            NSLog("[push-notifications] Swizzling existing didRegisterForRemoteNotificationsWithDeviceToken")
            let originalMethod = class_getInstanceMethod(appDelegateClass, selector)!
            let swizzledSelector = #selector(PushAppDelegateSwizzler.swizzled_didRegister(_:didRegisterForRemoteNotificationsWithDeviceToken:))
            let swizzledMethod = class_getInstanceMethod(PushAppDelegateSwizzler.self, swizzledSelector)!
            method_exchangeImplementations(originalMethod, swizzledMethod)
        } else {
            NSLog("[push-notifications] Adding didRegisterForRemoteNotificationsWithDeviceToken to AppDelegate")
            let swizzledSelector = #selector(PushAppDelegateSwizzler.swizzled_didRegister(_:didRegisterForRemoteNotificationsWithDeviceToken:))
            let swizzledMethod = class_getInstanceMethod(PushAppDelegateSwizzler.self, swizzledSelector)!
            let imp = method_getImplementation(swizzledMethod)
            let types = method_getTypeEncoding(swizzledMethod)
            class_addMethod(appDelegateClass, selector, imp, types)
        }

        let failSelector = #selector(UIApplicationDelegate.application(_:didFailToRegisterForRemoteNotificationsWithError:))
        if class_getInstanceMethod(appDelegateClass, failSelector) == nil {
            let failSwizzledSelector = #selector(PushAppDelegateSwizzler.swizzled_didFailToRegister(_:didFailToRegisterForRemoteNotificationsWithError:))
            let failMethod = class_getInstanceMethod(PushAppDelegateSwizzler.self, failSwizzledSelector)!
            let imp = method_getImplementation(failMethod)
            let types = method_getTypeEncoding(failMethod)
            class_addMethod(appDelegateClass, failSelector, imp, types)
        }
    }

    @objc dynamic func swizzled_didRegister(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        NSLog("[push-notifications] Received APNs device token (\(deviceToken.count) bytes)")
        handleAPNsToken(deviceToken)
    }

    @objc dynamic func swizzled_didFailToRegister(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        NSLog("[push-notifications] Failed to register for remote notifications: \(error)")
    }
}
