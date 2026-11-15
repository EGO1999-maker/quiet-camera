import AppIntents
import Combine
import Foundation

/// The intent and CameraView access this object on the main actor. Keeping a
/// pending request also handles cold launch and a photo deletion in progress.
final class CameraLaunchRequest: ObservableObject {
    static let shared = CameraLaunchRequest()
    @Published private(set) var pending = false

    @MainActor func request() { pending = true }
    @MainActor func consume() { pending = false }
}

struct OpenQuietCameraIntent: AppIntent {
    static let title: LocalizedStringResource = "카메라 열기"
    static let description = IntentDescription("Quiet Camera의 촬영 화면을 엽니다. 사진은 촬영 버튼을 눌러 찍습니다.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        CameraLaunchRequest.shared.request()
        return .result()
    }
}

struct QuietCameraShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenQuietCameraIntent(),
            phrases: ["\(.applicationName) 열기", "\(.applicationName) 촬영 준비"],
            shortTitle: "카메라 열기",
            systemImageName: "camera.fill"
        )
    }
}
