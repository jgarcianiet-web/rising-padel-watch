import PadelCore
import SwiftUI

@main
struct RisingPadelWatchApp: App {
    @StateObject private var controller = SessionController()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(controller)
        }
    }
}
