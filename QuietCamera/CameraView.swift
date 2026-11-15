import AVFoundation
import Photos
import SwiftUI
import UIKit

struct CameraView: View {
    @StateObject private var camera = CameraEngine()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingSettings = false
    private let mint = Color(red: 0.65, green: 0.94, blue: 0.82)

    var body: some View {
        ZStack {
            GeometryReader { geometry in
                CameraPreview(session: camera.session, front: camera.front)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Text("QUIET")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .tracking(4)
                    Spacer()
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 21))
                            .frame(width: 48, height: 48)
                            .background(.black.opacity(0.35), in: Circle())
                    }.accessibilityLabel("카메라 및 사진 권한 설정")
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .background(LinearGradient(colors: [.black.opacity(0.65), .clear],
                                           startPoint: .top, endPoint: .bottom).ignoresSafeArea(edges: .top))
                Spacer(minLength: 0)
                VStack(spacing: 14) {
                    Text(camera.status)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(mint)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(.black.opacity(0.4), in: Capsule())
                    HStack {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14).fill(.black.opacity(0.4))
                            if let image = camera.thumbnail {
                                Image(uiImage: image).resizable().scaledToFill()
                            } else {
                                Image(systemName: "photo").foregroundStyle(.white.opacity(0.7))
                            }
                        }
                        .frame(width: 54, height: 64).clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .accessibilityLabel("마지막으로 저장한 사진")
                        Spacer()
                        Button { camera.capture() } label: {
                            ZStack {
                                Circle().fill(.black.opacity(0.3)).frame(width: 88, height: 88)
                                Circle().strokeBorder(mint, lineWidth: 3).frame(width: 84, height: 84)
                                Circle().fill(camera.ready && !camera.busy ? mint : .gray)
                                    .frame(width: 68, height: 68)
                                if camera.busy { ProgressView().tint(.black) }
                            }
                        }
                        .disabled(!camera.ready || camera.busy)
                        .accessibilityLabel("사진 촬영")
                        Spacer()
                        Button { camera.switchCamera() } label: {
                            Image(systemName: "arrow.triangle.2.circlepath.camera")
                                .font(.system(size: 25)).frame(width: 54, height: 64)
                                .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(!camera.ready || camera.busy)
                        .accessibilityLabel("전면·후면 카메라 전환")
                    }
                    Text(camera.front ? "전면 · 셀카 방향으로 저장" : "후면 · 사진 앱에 저장")
                        .font(.caption2).foregroundStyle(.white.opacity(0.8))
                }
                .padding(.horizontal, 32).padding(.top, 36).padding(.bottom, 12)
                .background(LinearGradient(colors: [.clear, .black.opacity(0.7)],
                                           startPoint: .top, endPoint: .bottom).ignoresSafeArea(edges: .bottom))
            }

            if !camera.ready {
                VStack(spacing: 16) {
                    Image(systemName: "camera").font(.largeTitle).foregroundStyle(mint)
                    Text(camera.status).font(.callout).multilineTextAlignment(.center)
                    Button(camera.permissionDenied ? "설정 열기" : "다시 시도") {
                        if camera.permissionDenied { openAppSettings() }
                        else { camera.setActive(true) }
                    }.buttonStyle(.bordered)
                }
                .padding(28).background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 22))
                .padding(.horizontal, 24)
            }
        }
        .foregroundStyle(.white)
        .background(.black)
        .sheet(isPresented: $showingSettings) { CameraSettingsView() }
        .onAppear { camera.setActive(scenePhase == .active) }
        .onDisappear { camera.setActive(false) }
        .onChange(of: scenePhase) { phase in camera.setActive(phase == .active) }
        .alert("확인해 주세요", isPresented: Binding(
            get: { camera.message != nil }, set: { if !$0 { camera.message = nil } })) {
                Button("설정 열기") { openAppSettings() }
                Button("확인", role: .cancel) { }
            } message: { Text(camera.message ?? "") }
    }
}

private struct CameraSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var addStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
    @State private var libraryStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @State private var cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var requesting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("카메라") {
                    LabeledContent("접근 권한", value: cameraPermissionText)
                    Button("아이폰 설정에서 변경") { openAppSettings() }
                }
                Section {
                    LabeledContent("사진 저장", value: photoPermissionText(addStatus, addOnly: true))
                    LabeledContent("사진 보관함 접근", value: photoPermissionText(libraryStatus, addOnly: false))
                    Button("사진 추가 권한 요청") { requestPhotos(.addOnly) }
                        .disabled(requesting || addStatus == .authorized)
                    Button("선택한 사진·전체 사진 접근 설정") {
                        if libraryStatus == .notDetermined { requestPhotos(.readWrite) }
                        else { openAppSettings() }
                    }.disabled(requesting)
                    Button("아이폰 설정에서 권한 변경") { openAppSettings() }
                } header: {
                    Text("사진 접근 범위")
                } footer: {
                    Text("촬영한 사진을 저장하려면 ‘사진 추가만’으로 충분해요. 더 넓은 접근을 원하면 ‘선택한 사진·전체 사진 접근 설정’을 누르고 아이폰의 권한 화면에서 범위를 선택하세요. 이미 허용한 범위를 줄이거나 선택한 사진을 변경할 때는 아이폰 설정을 이용하세요.")
                }
                Section("미리보기") {
                    Text("카메라 영상을 화면 전체에 맞춰 크게 표시해요. 화면 비율에 따라 가장자리가 일부 잘려 보일 수 있지만 저장되는 사진은 원본 영상 프레임 전체예요.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    LabeledContent("버전", value: "1.1.0")
                    Text("사진은 아이폰에만 저장되며 외부로 전송하지 않아요.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { dismiss() } } }
        }
        .onAppear { refreshPermissions() }
        .onChange(of: scenePhase) { if $0 == .active { refreshPermissions() } }
    }

    private var cameraPermissionText: String {
        switch cameraStatus {
        case .authorized: return "허용됨"
        case .notDetermined: return "아직 선택하지 않음"
        case .restricted: return "기기에서 제한됨"
        case .denied: return "허용 안 함"
        @unknown default: return "확인 필요"
        }
    }

    private func photoPermissionText(_ status: PHAuthorizationStatus, addOnly: Bool) -> String {
        switch status {
        case .authorized: return addOnly ? "허용됨" : "전체 사진"
        case .limited: return "선택한 사진"
        case .notDetermined: return "아직 요청하지 않음"
        case .restricted: return "기기에서 제한됨"
        case .denied: return "허용 안 함"
        @unknown default: return "확인 필요"
        }
    }

    private func refreshPermissions() {
        addStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        libraryStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
    }

    private func requestPhotos(_ level: PHAccessLevel) {
        let status = PHPhotoLibrary.authorizationStatus(for: level)
        guard status == .notDetermined else { openAppSettings(); return }
        requesting = true
        PHPhotoLibrary.requestAuthorization(for: level) { _ in
            DispatchQueue.main.async {
                requesting = false
                refreshPermissions()
            }
        }
    }
}

private func openAppSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    UIApplication.shared.open(url)
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let front: Bool

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.preview.session = session
        view.preview.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        view.front = front
        view.setNeedsLayout()
    }
}

private final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    var front = false
    override func layoutSubviews() {
        super.layoutSubviews()
        guard let connection = preview.connection else { return }
        if connection.isVideoOrientationSupported { connection.videoOrientation = .portrait }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = front
        }
    }
}
