import SwiftUI
import UserNotifications

/// El puente con APNs: recoge el token del dispositivo y las notificaciones tocadas,
/// y las reparte por NotificationCenter — el modelo de la comunidad las escucha sin
/// que el delegate tenga que conocerlo.
final class PushDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        NotificationCenter.default.post(name: .apnsToken, object: token)
    }

    /// Un toque en "fulano está jugando" abre su partido directamente.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        if let live = info["live"] as? [String: Any],
           let alias = live["alias"] as? String,
           let sessionId = live["sessionId"] as? String {
            NotificationCenter.default.post(
                name: .abrirEnVivo,
                object: ComunidadEnVivo(alias: alias, sessionId: sessionId)
            )
        }
    }

    /// Con la app abierta las notificaciones también se enseñan: un "está jugando"
    /// perdido porque estabas mirando el muro sería absurdo.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
