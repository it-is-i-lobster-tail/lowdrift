import SwiftUI

@main
struct LowdriftApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            MainView(controller: AppEnvironment.shared.controller)
                .tint(Theme.accent)
                .onChange(of: scenePhase) { _, phase in
                    // Coming back to the app: make sure Play/Pause shows what the
                    // engine is really doing.
                    if phase == .active {
                        AppEnvironment.shared.controller.reconcile()
                    }
                }
        }
    }
}
