import AVFoundation
import Combine
import CoreImage
import Photos
import UIKit

/// All capture-session state belongs to queue. Published UI state changes on main.
final class CameraEngine: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published private(set) var ready = false
    @Published private(set) var busy = false
    @Published private(set) var front = false
    @Published private(set) var status = "카메라 준비 중"
    @Published private(set) var thumbnail: UIImage?
    @Published var message: String?
    @Published private(set) var permissionDenied = false
    @Published private(set) var zoom: CGFloat = 1
    @Published private(set) var minimumZoom: CGFloat = 1
    @Published private(set) var maximumZoom: CGFloat = 1
    @Published private(set) var exposureBias: Float = 0
    @Published private(set) var minimumExposureBias: Float = -2
    @Published private(set) var maximumExposureBias: Float = 2
    @Published private(set) var canAdjustExposure = false
    @Published private(set) var canTargetFocusOrExposure = false

    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "QuietCamera.capture", qos: .userInitiated)
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let output = AVCaptureVideoDataOutput()
    private var input: AVCaptureDeviceInput?
    private var configured = false
    private var active = false
    private var waitingForFirstFrame = true
    private var captureID: UUID?
    private var pendingFrame = false
    private var pendingViewport = CGSize.zero
    private var pendingOrientation: AVCaptureVideoOrientation = .portrait
    private var rotationFramesToDiscard = 0
    private var observers: [NSObjectProtocol] = []

    override init() {
        super.init()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVCaptureSession.wasInterruptedNotification,
            object: session, queue: nil) { [weak self] _ in
                self?.queue.async { [weak self] in
                    guard let self else { return }
                    self.cancelPendingFrame()
                    self.publish { $0.ready = false; $0.status = "카메라가 일시 중지됐어요" }
                }
            })
        observers.append(center.addObserver(forName: AVCaptureSession.interruptionEndedNotification,
            object: session, queue: nil) { [weak self] _ in
                self?.queue.async { [weak self] in self?.startIfNeeded() }
            })
        observers.append(center.addObserver(forName: AVCaptureSession.runtimeErrorNotification,
            object: session, queue: nil) { [weak self] _ in
                self?.queue.async { [weak self] in
                    guard let self else { return }
                    self.cancelPendingFrame()
                    self.publish {
                        $0.ready = false
                        $0.status = "카메라를 다시 시작해 주세요"
                        $0.message = "카메라 연결이 중단됐어요. 다시 시도를 눌러 주세요."
                    }
                }
            })
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    private func publish(_ update: @escaping (CameraEngine) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            update(self)
        }
    }

    func setActive(_ value: Bool) {
        queue.async {
            self.active = value
            if value {
                self.authorizeAndStart()
            } else {
                self.cancelPendingFrame()
                self.waitingForFirstFrame = true
                if self.session.isRunning { self.session.stopRunning() }
                self.publish { $0.ready = false }
            }
        }
    }

    private func authorizeAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            publish { $0.permissionDenied = false }
            startIfNeeded()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] _ in
                self?.queue.async { [weak self] in
                    guard let self, self.active else { return }
                    self.authorizeAndStart()
                }
            }
        default:
            publish {
                $0.ready = false
                $0.permissionDenied = true
                $0.status = "설정에서 카메라 접근을 허용해 주세요"
            }
        }
    }

    private func startIfNeeded() {
        guard active, AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }
        do {
            if !configured {
                try configure()
                try resetDeviceZoom()
            }
            publishDeviceControls()
            waitingForFirstFrame = true
            if !session.isRunning { session.startRunning() }
            publish { $0.status = "카메라 준비 중" }
        } catch {
            publish { $0.ready = false; $0.status = "카메라를 사용할 수 없어요"; $0.message = error.localizedDescription }
        }
    }

    private func makeInput(_ position: AVCaptureDevice.Position) throws -> AVCaptureDeviceInput {
        let types: [AVCaptureDevice.DeviceType] = position == .back
            ? [.builtInTripleCamera, .builtInDualWideCamera, .builtInWideAngleCamera]
            : [.builtInWideAngleCamera]
        guard let device = types.compactMap({ AVCaptureDevice.default($0, for: .video, position: position) }).first else {
            throw CameraError.unavailable
        }
        try device.lockForConfiguration()
        if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
        if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
        if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) { device.whiteBalanceMode = .continuousAutoWhiteBalance }
        device.unlockForConfiguration()
        return try AVCaptureDeviceInput(device: device)
    }

    private func configure() throws {
        let newInput = try makeInput(.back)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        guard session.canAddInput(newInput) else { throw CameraError.unavailable }
        session.addInput(newInput)
        guard session.canAddOutput(output) else {
            session.removeInput(newInput)
            throw CameraError.unavailable
        }
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        session.addOutput(output)
        input = newInput
        setCaptureFormat()
        configured = true
    }

    private func setCaptureFormat() {
        session.sessionPreset = session.canSetSessionPreset(.hd1920x1080) ? .hd1920x1080 : .high
        if let connection = output.connection(with: .video) {
            if connection.isVideoOrientationSupported { connection.videoOrientation = .portrait }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = input?.device.position == .front
            }
        }
    }

    private func zoomScale(for device: AVCaptureDevice) -> CameraZoom {
        var wideSwitch: Double?
        let lenses = device.constituentDevices
        if lenses.contains(where: { $0.deviceType == .builtInUltraWideCamera }),
           let wideIndex = lenses.firstIndex(where: { $0.deviceType == .builtInWideAngleCamera }),
           wideIndex > 0, device.virtualDeviceSwitchOverVideoZoomFactors.indices.contains(wideIndex - 1) {
            wideSwitch = device.virtualDeviceSwitchOverVideoZoomFactors[wideIndex - 1].doubleValue
        }
        return CameraZoom(wideSwitchFactor: wideSwitch,
                          minimum: Double(device.minAvailableVideoZoomFactor),
                          maximum: Double(device.maxAvailableVideoZoomFactor))
    }

    private func resetDeviceZoom() throws {
        guard let device = input?.device else { return }
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        device.videoZoomFactor = CGFloat(zoomScale(for: device).nativeFactor(for: 1))
    }

    // All device reads/writes occur on the same queue as capture and camera switching.
    private func publishDeviceControls() {
        guard let device = input?.device else { return }
        let scale = zoomScale(for: device)
        let lower = CGFloat(scale.minimum)
        let upper = CGFloat(scale.maximum)
        let biasLower = max(device.minExposureTargetBias, -2)
        let biasUpper = min(device.maxExposureTargetBias, 2)
        let canExpose = device.isExposureModeSupported(.continuousAutoExposure) && biasUpper > biasLower
        let canFocus = (device.isFocusPointOfInterestSupported &&
            (device.isFocusModeSupported(.autoFocus) || device.isFocusModeSupported(.continuousAutoFocus))) ||
            (device.isExposurePointOfInterestSupported && device.isExposureModeSupported(.continuousAutoExposure))
        let currentZoom = CGFloat(scale.displayFactor(for: Double(device.videoZoomFactor)))
        let currentBias = device.exposureTargetBias
        publish {
            $0.minimumZoom = lower; $0.maximumZoom = upper; $0.zoom = currentZoom
            $0.minimumExposureBias = biasLower; $0.maximumExposureBias = biasUpper
            $0.exposureBias = currentBias; $0.canAdjustExposure = canExpose
            $0.canTargetFocusOrExposure = canFocus
        }
    }

    func setZoom(_ requested: CGFloat) {
        guard requested.isFinite else { return }
        queue.async {
            guard self.active, self.captureID == nil, !self.waitingForFirstFrame,
                  let device = self.input?.device else { return }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                let scale = self.zoomScale(for: device)
                device.videoZoomFactor = CGFloat(scale.nativeFactor(for: Double(requested)))
                let value = CGFloat(scale.displayFactor(for: Double(device.videoZoomFactor)))
                self.publish { $0.zoom = value }
            } catch { self.publish { $0.message = "배율을 변경하지 못했어요. 다시 시도해 주세요." } }
        }
    }

    func focus(at point: CGPoint) {
        guard point.x.isFinite, point.y.isFinite else { return }
        queue.async {
            guard self.active, self.captureID == nil, !self.waitingForFirstFrame,
                  let device = self.input?.device else { return }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                let target = CGPoint(x: min(max(point.x, 0), 1), y: min(max(point.y, 0), 1))
                var adjusted = false
                if device.isFocusPointOfInterestSupported &&
                    (device.isFocusModeSupported(.autoFocus) || device.isFocusModeSupported(.continuousAutoFocus)) {
                    device.focusPointOfInterest = target
                    device.focusMode = device.isFocusModeSupported(.autoFocus) ? .autoFocus : .continuousAutoFocus
                    adjusted = true
                }
                if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposurePointOfInterest = target
                    device.exposureMode = .continuousAutoExposure
                    adjusted = true
                }
                self.publish { $0.status = adjusted ? "선택한 위치에 초점·노출 조절 중" : "이 카메라는 터치 초점을 지원하지 않아요" }
            } catch { self.publish { $0.message = "초점을 조절하지 못했어요. 다시 시도해 주세요." } }
        }
    }

    func setExposureBias(_ requested: Float) {
        guard requested.isFinite else { return }
        queue.async {
            guard self.active, self.captureID == nil, !self.waitingForFirstFrame,
                  let device = self.input?.device,
                  device.isExposureModeSupported(.continuousAutoExposure) else { return }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                let value = min(max(requested, max(device.minExposureTargetBias, -2)), min(device.maxExposureTargetBias, 2))
                device.setExposureTargetBias(value, completionHandler: nil)
                self.publish { $0.exposureBias = value }
            } catch { self.publish { $0.message = "밝기를 조절하지 못했어요. 다시 시도해 주세요." } }
        }
    }

    func resetFocusAndExposure() {
        queue.async {
            guard self.active, self.captureID == nil, let device = self.input?.device else { return }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5) }
                if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
                if device.isExposurePointOfInterestSupported { device.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5) }
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                    device.setExposureTargetBias(0, completionHandler: nil)
                }
                self.publish { $0.exposureBias = 0; $0.status = "자동 초점·밝기로 복원했어요" }
            } catch { self.publish { $0.message = "자동 설정으로 복원하지 못했어요." } }
        }
    }

    func switchCamera() {
        queue.async {
            guard self.active, self.configured, self.captureID == nil,
                  !self.waitingForFirstFrame, let old = self.input else { return }
            do {
                let next = try self.makeInput(old.device.position == .back ? .front : .back)
                self.publish { $0.ready = false; $0.status = "카메라 전환 중" }
                self.session.beginConfiguration()
                self.session.removeInput(old)
                if self.session.canAddInput(next) {
                    self.session.addInput(next)
                    self.input = next
                } else {
                    self.session.addInput(old)
                }
                self.setCaptureFormat()
                self.session.commitConfiguration()
                if self.input?.device.uniqueID == next.device.uniqueID { try self.resetDeviceZoom() }
                self.publishDeviceControls()
                self.waitingForFirstFrame = true
                let isFront = self.input?.device.position == .front
                self.publish { $0.front = isFront }
            } catch {
                self.publish { $0.message = "카메라를 전환하지 못했어요. 다시 시도해 주세요." }
            }
        }
    }

    func capture(viewportSize: CGSize, orientation: AVCaptureVideoOrientation) {
        guard viewportSize.width.isFinite, viewportSize.height.isFinite,
              viewportSize.width > 0, viewportSize.height > 0 else { return }
        queue.async {
            guard self.active, self.session.isRunning, !self.session.isInterrupted,
                  !self.waitingForFirstFrame, self.captureID == nil else { return }
            let landscape = orientation == .landscapeLeft || orientation == .landscapeRight
            guard (viewportSize.width > viewportSize.height) == landscape,
                  let connection = self.output.connection(with: .video),
                  connection.isVideoOrientationSupported else {
                self.publish { $0.message = "화면 회전이 끝난 뒤 다시 촬영해 주세요." }
                return
            }
            // Freeze orientation for this capture. Preview can rotate independently
            // while saving; no later layout change can alter the pending photo.
            let changingOrientation = connection.videoOrientation != orientation
            connection.videoOrientation = orientation
            self.rotationFramesToDiscard = changingOrientation ? 2 : 0
            self.pendingOrientation = orientation
            let id = UUID()
            self.captureID = id
            self.pendingFrame = true
            self.pendingViewport = viewportSize
            self.publish { $0.busy = true; $0.status = "촬영 중" }
            self.queue.asyncAfter(deadline: .now() + 3) {
                if self.captureID == id && self.pendingFrame {
                    self.finish(id: id, error: "영상을 받지 못했어요. 다시 촬영해 주세요.")
                }
            }
        }
    }

    private func cancelPendingFrame() {
        if pendingFrame, let id = captureID { finish(id: id, error: nil) }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard active else { return }
        if waitingForFirstFrame {
            waitingForFirstFrame = false
            publish { $0.ready = true; if !$0.busy { $0.status = "준비 완료" } }
        }
        guard pendingFrame, let id = captureID,
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        // Discard in-flight frames when switching buffer rotation, then check
        // physical dimensions before cropping the JPEG to the preview ratio.
        if rotationFramesToDiscard > 0 { rotationFramesToDiscard -= 1; return }
        let landscape = pendingOrientation == .landscapeLeft || pendingOrientation == .landscapeRight
        guard (CVPixelBufferGetWidth(buffer) > CVPixelBufferGetHeight(buffer)) == landscape else { return }
        pendingFrame = false
        let ciImage = CIImage(cvPixelBuffer: buffer)
        let crop = CaptureGeometry.cropRect(source: ciImage.extent, viewport: pendingViewport)
        guard let cgImage = context.createCGImage(ciImage, from: crop),
              let data = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.92) else {
            finish(id: id, error: "사진을 만들지 못했어요. 다시 촬영해 주세요.")
            return
        }
        let capturedAt = Date()
        publish { $0.status = "사진 저장 중" }
        // Capture the frame before asking permission, preserving the button-press moment.
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] authorization in
            guard let self else { return }
            guard authorization == .authorized || authorization == .limited else {
                self.queue.async {
                    self.finish(id: id, error: "사진을 저장하지 못했어요. 설정 → Quiet Camera → 사진에서 사진 추가를 허용한 뒤 다시 촬영해 주세요.")
                }
                return
            }
            var savedIdentifier: String?
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = "QuietCamera-\(UUID().uuidString).jpg"
                request.addResource(with: .photo, data: data, options: options)
                savedIdentifier = request.placeholderForCreatedAsset?.localIdentifier
            }, completionHandler: { success, _ in
                self.queue.async {
                    if success {
                        self.publish {
                            $0.thumbnail = UIImage(data: data)
                            if let savedIdentifier {
                                PhotoGalleryStore.shared.addSavedPhoto(id: savedIdentifier, capturedAt: capturedAt)
                            } else {
                                $0.message = "사진은 저장했지만 촬영 목록에 추가하지 못했어요. 사진 앱에서 확인해 주세요."
                            }
                        }
                        self.finish(id: id, error: nil, saved: true)
                    } else {
                        self.finish(id: id, error: "사진을 저장하지 못했어요. 저장 공간과 사진 접근 권한을 확인해 주세요.")
                    }
                }
            })
        }
    }

    private func finish(id: UUID, error: String?, saved: Bool = false) {
        guard captureID == id else { return }
        captureID = nil
        pendingFrame = false
        publish {
            $0.busy = false
            $0.status = saved ? "사진에 저장했어요" : ($0.ready ? "준비 완료" : "카메라 준비 중")
            if let error { $0.message = error }
        }
    }
}

private enum CameraError: LocalizedError {
    case unavailable
    var errorDescription: String? { "이 기기에서 카메라를 열지 못했어요. 앱을 다시 열어 주세요." }
}
