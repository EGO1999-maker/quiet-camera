import SwiftUI

@main
struct QuietCameraApp: App {
    var body: some Scene {
        WindowGroup {
            CameraView().preferredColorScheme(.dark)
                .tint(Color(red: 1, green: 0.73, blue: 0.82))
        }
    }
}
