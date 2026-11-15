import AVFoundation
import SwiftUI
import UIKit

struct CameraView: View {
    @StateObject private var camera = CameraEngine()
    @Environment(\.scenePhase) private var scenePhase
    private let mint = Color(red: 0.65, green: 0.94, blue: 0.82)

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("QUIET").font(.system(size: 22, weight: .semibold, design: .rounded)).tracking(5)
                        Text("지금 이 순간을 담아요").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Label("사진", systemImage: "camera").font(.caption.weight(.medium))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(mint.opacity(0.12), in: Capsule()).foregroundStyle(mint)
                }
                .padding(.horizontal, 24)

                ZStack {
                    Color.black
                    CameraPreview(session: camera.session, front: camera.front)
                    if !camera.ready {
                        VStack(spacing: 16) {
                            Image(systemName: camera.permissionDenied ? "camera.fill" : "camera")
                                .font(.largeTitle).foregroundStyle(mint)
                            Text(camera.status).font(.callout).multilineTextAlignment(.center)
                            Button(camera.permissionDenied ? "설정 열기" : "다시 시도") {
                                if camera.permissionDenied { openSettings() }
                                else { camera.setActive(true) }
                            }.buttonStyle(.bordered)
                        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.black.opacity(0.8))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.08)))
                .padding(.horizontal, 16)

                Text(camera.status)
                    .font(.footnote).foregroundStyle(camera.busy ? .white : mint)
                    .accessibilityLabel(camera.status)
                    .frame(height: 20)

                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.07))
                        if let image = camera.thumbnail {
                            Image(uiImage: image).resizable().scaledToFill()
                        } else {
                            Image(systemName: "photo").foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 54, height: 64).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .accessibilityLabel("마지막으로 저장한 사진")
                    Spacer()
                    Button { camera.capture() } label: {
                        ZStack {
                            Circle().strokeBorder(mint.opacity(0.65), lineWidth: 2).frame(width: 82, height: 82)
                            Circle().fill(camera.ready && !camera.busy ? mint : .gray).frame(width: 68, height: 68)
                            if camera.busy { ProgressView().tint(.black) }
                        }
                    }
                    .disabled(!camera.ready || camera.busy)
                    .accessibilityLabel("사진 촬영")
                    Spacer()
                    Button { camera.switchCamera() } label: {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .font(.system(size: 25)).foregroundStyle(.white)
                            .frame(width: 54, height: 64)
                    }.disabled(!camera.ready || camera.busy)
                        .accessibilityLabel("전면·후면 카메라 전환")
                }.padding(.horizontal, 38)

                Text(camera.front ? "전면 · 화면에 보이는 방향으로 저장" : "후면 · 사진 앱에 바로 저장")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.top, 12).padding(.bottom, 12)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(Color(red: 0.035, green: 0.047, blue: 0.043).ignoresSafeArea())
        .onAppear { camera.setActive(scenePhase == .active) }
        .onDisappear { camera.setActive(false) }
        .onChange(of: scenePhase) { phase in camera.setActive(phase == .active) }
        .alert("확인해 주세요", isPresented: Binding(
            get: { camera.message != nil }, set: { if !$0 { camera.message = nil } })) {
                Button("설정 열기") { openSettings() }
                Button("확인", role: .cancel) { }
            } message: { Text(camera.message ?? "") }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let front: Bool

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.preview.session = session
        view.preview.videoGravity = .resizeAspect
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
