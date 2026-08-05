import SwiftUI

@main
struct RisingPadelApp: App {
    // El delegate clásico solo para APNs: token del dispositivo y toques en
    // notificaciones. Todo lo demás sigue siendo SwiftUI puro.
    @UIApplicationDelegateAdaptor(PushDelegate.self) private var pushDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(model)
        }
    }
}
