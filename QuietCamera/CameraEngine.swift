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
            if !configured { try configure() }
            waitingForFirstFrame = true
            if !session.isRunning { session.startRunning() }
            publish { $0.status = "카메라 준비 중" }
        } catch {
            publish { $0.ready = false; $0.status = "카메라를 사용할 수 없어요"; $0.message = error.localizedDescription }
        }
    }

    private func makeInput(_ position: AVCaptureDevice.Position) throws -> AVCaptureDeviceInput {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
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
                self.waitingForFirstFrame = true
                let isFront = self.input?.device.position == .front
                self.publish { $0.front = isFront }
            } catch {
                self.publish { $0.message = "카메라를 전환하지 못했어요. 다시 시도해 주세요." }
            }
        }
    }

    func capture() {
        queue.async {
            guard self.active, self.session.isRunning, !self.session.isInterrupted,
                  !self.waitingForFirstFrame, self.captureID == nil else { return }
            let id = UUID()
            self.captureID = id
            self.pendingFrame = true
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
        pendingFrame = false
        let ciImage = CIImage(cvPixelBuffer: buffer)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent),
              let data = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.92) else {
            finish(id: id, error: "사진을 만들지 못했어요. 다시 촬영해 주세요.")
            return
        }
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
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = "QuietCamera-\(UUID().uuidString).jpg"
                request.addResource(with: .photo, data: data, options: options)
            }, completionHandler: { success, _ in
                self.queue.async {
                    if success {
                        self.publish { $0.thumbnail = UIImage(data: data) }
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
