import AVFoundation
import Photos
import SwiftUI
import UIKit

struct CameraView: View {
    @StateObject private var camera = CameraEngine()
    @StateObject private var gallery = PhotoGalleryStore.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingSettings = false
    @State private var showingReview = false
    @State private var showingExposure = false
    @State private var viewportSize = CGSize.zero
    private let mint = Color(red: 0.65, green: 0.94, blue: 0.82)

    var body: some View {
        ZStack {
            GeometryReader { geometry in
                CameraPreview(
                    session: camera.session, front: camera.front,
                    zoom: camera.zoom, minimumZoom: camera.minimumZoom, maximumZoom: camera.maximumZoom,
                    interactive: camera.ready && !camera.busy,
                    canFocus: camera.canTargetFocusOrExposure,
                    onZoom: { camera.setZoom($0) },
                    onFocus: { camera.focus(at: $0) },
                    onSize: { viewportSize = $0 }
                )
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
            }.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Spacer(minLength: 0)
                controls
            }
            if !camera.ready { unavailableOverlay }
        }
        .foregroundStyle(.white)
        .background(.black)
        .sheet(isPresented: $showingSettings) { CameraSettingsView() }
        .fullScreenCover(isPresented: $showingReview) {
            PhotoGalleryView(gallery: gallery)
        }
        .onAppear { camera.setActive(scenePhase == .active && !showingReview) }
        .onDisappear { camera.setActive(false) }
        .onChange(of: scenePhase) { phase in
            camera.setActive(phase == .active && !showingReview)
            if phase == .active { gallery.refresh() }
        }
        .onChange(of: showingReview) { value in camera.setActive(scenePhase == .active && !value) }
        .alert("확인해 주세요", isPresented: Binding(
            get: { camera.message != nil }, set: { if !$0 { camera.message = nil } })) {
                Button("설정 열기") { openAppSettings() }
                Button("확인", role: .cancel) { }
            } message: { Text(camera.message ?? "") }
    }

    private var header: some View {
        HStack {
            Text("QUIET").font(.system(size: 18, weight: .semibold, design: .rounded)).tracking(4)
            Spacer()
            Button { showingExposure.toggle() } label: {
                Image(systemName: "sun.max.fill")
                    .foregroundStyle(showingExposure ? mint : .white)
                    .frame(width: 48, height: 48)
                    .background(.black.opacity(0.35), in: Circle())
            }
            .disabled(!camera.ready || camera.busy || !camera.canAdjustExposure)
            .accessibilityLabel("밝기 조절 표시")
            Button { showingSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .frame(width: 48, height: 48)
                    .background(.black.opacity(0.35), in: Circle())
            }.accessibilityLabel("카메라 및 사진 권한 설정")
        }
        .font(.system(size: 21))
        .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 24)
        .background(LinearGradient(colors: [.black.opacity(0.65), .clear],
                                   startPoint: .top, endPoint: .bottom).ignoresSafeArea(edges: .top))
    }

    private var controls: some View {
        VStack(spacing: 10) {
            if showingExposure && camera.canAdjustExposure { exposureControl }
            zoomControl
            Text(camera.status)
                .font(.caption.weight(.medium)).foregroundStyle(mint)
                .lineLimit(2).multilineTextAlignment(.center)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(.black.opacity(0.4), in: Capsule())
            HStack {
                Button { showingReview = true } label: { thumbnail }
                    .disabled(camera.busy)
                    .accessibilityLabel("촬영한 사진 갤러리 열기")
                Spacer()
                Button { camera.capture(viewportSize: viewportSize) } label: {
                    ZStack {
                        Circle().fill(.black.opacity(0.3)).frame(width: 88, height: 88)
                        Circle().strokeBorder(mint, lineWidth: 3).frame(width: 84, height: 84)
                        Circle().fill(camera.ready && !camera.busy ? mint : .gray).frame(width: 68, height: 68)
                        if camera.busy { ProgressView().tint(.black) }
                    }
                }
                .disabled(!camera.ready || camera.busy || viewportSize.width <= 0 || viewportSize.height <= 0)
                .accessibilityLabel("사진 촬영")
                Spacer()
                Button { showingExposure = false; camera.switchCamera() } label: {
                    Image(systemName: "arrow.triangle.2.circlepath.camera")
                        .font(.system(size: 25)).frame(width: 54, height: 64)
                        .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
                }.disabled(!camera.ready || camera.busy).accessibilityLabel("전면·후면 카메라 전환")
            }
            Text(camera.front ? "전면 · 보이는 구도로 저장" : "후면 · 보이는 구도로 저장")
                .font(.caption2).foregroundStyle(.white.opacity(0.8))
        }
        .padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 12)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.75)],
                                   startPoint: .top, endPoint: .bottom).ignoresSafeArea(edges: .bottom))
    }

    private var zoomControl: some View {
        HStack(spacing: 12) {
            Button("1×") { camera.setZoom(1) }.frame(minWidth: 40, minHeight: 40)
                .accessibilityLabel("기본 배율로 축소")
            Slider(value: Binding(get: { Double(camera.zoom) }, set: { camera.setZoom(CGFloat($0)) }),
                   in: Double(camera.minimumZoom)...Double(max(camera.maximumZoom, camera.minimumZoom + 0.001)))
                .tint(mint).accessibilityLabel("카메라 확대 축소")
            Text(String(format: "%.1f×", Double(camera.zoom)))
                .monospacedDigit().font(.callout.weight(.semibold)).frame(width: 50)
        }
        .padding(.horizontal, 12).background(.black.opacity(0.45), in: Capsule())
        .disabled(!camera.ready || camera.busy || camera.maximumZoom <= camera.minimumZoom)
    }

    private var exposureControl: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "sun.min")
                Slider(value: Binding(get: { Double(camera.exposureBias) }, set: { camera.setExposureBias(Float($0)) }),
                       in: Double(camera.minimumExposureBias)...Double(max(camera.maximumExposureBias, camera.minimumExposureBias + 0.001)),
                       step: 0.1)
                    .tint(mint).accessibilityLabel("노출 보정")
                Image(systemName: "sun.max.fill")
            }
            HStack {
                Text(String(format: "%+.1f EV", Double(camera.exposureBias))).monospacedDigit()
                Spacer()
                Button("초점·밝기 자동 복원") { camera.resetFocusAndExposure() }.padding(.vertical, 8)
            }.font(.caption)
        }
        .padding(.horizontal, 14).padding(.top, 8)
        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 16))
        .disabled(!camera.ready || camera.busy)
    }

    private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14).fill(.black.opacity(0.4))
            if let record = gallery.visibleRecords.last, let asset = gallery.assets[record.id] {
                GalleryImage(asset: asset, fullSize: false)
            } else if !gallery.canRead, let image = camera.thumbnail {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "photo").foregroundStyle(.white.opacity(0.7))
            }
        }
        .frame(width: 54, height: 64).clipped().clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var unavailableOverlay: some View {
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
                    Text("미리보기에서 보이는 구도로 사진을 잘라 저장해요. 두 손가락 또는 배율 슬라이더로 확대·축소하고, 화면을 눌러 초점을 맞출 수 있어요. 위쪽 해 모양 버튼에서 밝기를 조절하세요. 줌은 기본 렌즈의 디지털 확대이며 0.5배 초광각 렌즈 전환은 포함하지 않아요.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    LabeledContent("버전", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
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
    let zoom: CGFloat
    let minimumZoom: CGFloat
    let maximumZoom: CGFloat
    let interactive: Bool
    let canFocus: Bool
    let onZoom: (CGFloat) -> Void
    let onFocus: (CGPoint) -> Void
    let onSize: (CGSize) -> Void

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.preview.session = session
        view.preview.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        if view.front != front { view.hideFocusIndicator() }
        view.front = front
        view.currentZoom = zoom
        view.minimumZoom = minimumZoom
        view.maximumZoom = maximumZoom
        view.interactive = interactive
        view.canFocus = canFocus
        view.onZoom = onZoom
        view.onFocus = onFocus
        view.onSize = onSize
        view.setNeedsLayout()
    }
}

private final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    var front = false
    var currentZoom: CGFloat = 1
    var minimumZoom: CGFloat = 1
    var maximumZoom: CGFloat = 1
    var interactive = false
    var canFocus = false
    var onZoom: ((CGFloat) -> Void)?
    var onFocus: ((CGPoint) -> Void)?
    var onSize: ((CGSize) -> Void)?
    private var pinchStartZoom: CGFloat = 1
    private var reportedSize = CGSize.zero
    private let focusIndicator = UIView()
    private var focusID = UUID()

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:)))
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        tap.require(toFail: pinch)
        addGestureRecognizer(pinch)
        addGestureRecognizer(tap)
        focusIndicator.isUserInteractionEnabled = false
        focusIndicator.layer.borderWidth = 1.5
        focusIndicator.layer.borderColor = UIColor.systemYellow.cgColor
        focusIndicator.layer.cornerRadius = 8
        focusIndicator.alpha = 0
        addSubview(focusIndicator)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let connection = preview.connection {
            if connection.isVideoOrientationSupported { connection.videoOrientation = .portrait }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = front
            }
        }
        if bounds.size != reportedSize, bounds.width > 0, bounds.height > 0 {
            reportedSize = bounds.size
            let size = bounds.size
            DispatchQueue.main.async { [weak self] in self?.onSize?(size) }
        }
    }

    @objc private func pinched(_ gesture: UIPinchGestureRecognizer) {
        guard interactive else { return }
        if gesture.state == .began {
            pinchStartZoom = currentZoom
            hideFocusIndicator()
        }
        if gesture.state == .began || gesture.state == .changed || gesture.state == .ended {
            let value = min(max(pinchStartZoom * gesture.scale, minimumZoom), maximumZoom)
            onZoom?(value)
        }
    }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        guard interactive, canFocus, gesture.state == .ended, preview.connection != nil else { return }
        let point = gesture.location(in: self)
        // AVFoundation accounts for preview cropping, portrait rotation and selfie mirroring.
        onFocus?(preview.captureDevicePointConverted(fromLayerPoint: point))
        let id = UUID()
        focusID = id
        focusIndicator.layer.removeAllAnimations()
        focusIndicator.frame = CGRect(x: point.x - 30, y: point.y - 30, width: 60, height: 60)
        focusIndicator.alpha = 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, self.focusID == id else { return }
            UIView.animate(withDuration: 0.25) { self.focusIndicator.alpha = 0 }
        }
    }

    func hideFocusIndicator() {
        focusID = UUID()
        focusIndicator.layer.removeAllAnimations()
        focusIndicator.alpha = 0
    }
}

struct ZoomablePhoto: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> PhotoScrollView {
        let view = PhotoScrollView()
        view.imageView.image = image
        return view
    }

    func updateUIView(_ view: PhotoScrollView, context: Context) {
        if view.imageView.image !== image {
            view.imageView.image = image
            view.setZoomScale(1, animated: false)
        }
    }
}

final class PhotoScrollView: UIScrollView, UIScrollViewDelegate {
    let imageView = UIImageView()
    private var lastSize = CGSize.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 5
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        backgroundColor = .black
        imageView.contentMode = .scaleAspectFit
        imageView.isAccessibilityElement = true
        imageView.accessibilityLabel = "선택한 촬영 사진"
        addSubview(imageView)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(resetZoom))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != lastSize {
            lastSize = bounds.size
            setZoomScale(1, animated: false)
            imageView.frame = CGRect(origin: .zero, size: bounds.size)
            contentSize = bounds.size
        }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
    @objc private func resetZoom() { setZoomScale(1, animated: true) }
}
