import SwiftUI
import AppIntents

@main
struct QuietCameraApp: App {
    init() { QuietCameraShortcuts.updateAppShortcutParameters() }

    var body: some Scene {
        WindowGroup {
            CameraView().preferredColorScheme(.dark)
                .tint(Color(red: 1, green: 0.73, blue: 0.82))
        }
    }
}
