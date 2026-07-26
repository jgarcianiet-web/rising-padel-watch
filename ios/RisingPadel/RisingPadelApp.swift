import SwiftUI

@main
struct RisingPadelApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            SessionListView()
                .environmentObject(model)
        }
    }
}
