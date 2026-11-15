import AVFoundation
import Combine
import Foundation

@MainActor
final class RecorderStore: NSObject, ObservableObject, AVAudioRecorderDelegate, AVAudioPlayerDelegate {
    static let shared = RecorderStore()
    @Published private(set) var clips: [RecordingClip] = []
    @Published private(set) var active: RecordingClip?
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var busy = false
    @Published private(set) var playingID: UUID?
    @Published var notice = "녹음할 준비가 됐어요"
    @Published var error: String?
    var onChange: (() -> Void)?
    var onSaved: (() -> Void)?
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var clock: AnyCancellable?
    private var interruption: AnyCancellable?
    private var reset: AnyCancellable?
    private var routeChange: AnyCancellable?
    let directory: URL

    private override init() {
        directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recordings", isDirectory: true)
        super.init()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            #if os(iOS)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: directory.path)
            #endif
            reload()
        } catch { self.error = "저장 폴더를 열 수 없어요: \(error.localizedDescription)" }
        clock = Timer.publish(every: 0.3, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            guard let self, let recorder = self.recorder, self.active != nil else { return }
            self.elapsed = recorder.currentTime
        }
        interruption = NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .receive(on: DispatchQueue.main).sink { [weak self] notification in
                guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
                self?.stop(reason: "통화 또는 다른 오디오 작업으로 녹음이 종료됐어요")
                self?.stopPlayback()
            }
        reset = NotificationCenter.default.publisher(for: AVAudioSession.mediaServicesWereResetNotification)
            .receive(on: DispatchQueue.main).sink { [weak self] _ in
                self?.stop(reason: "오디오 장치가 재설정됐어요. 저장된 파일을 확인해 주세요")
                self?.stopPlayback()
            }
        routeChange = NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            .receive(on: DispatchQueue.main).sink { [weak self] _ in
                guard let self, self.active != nil else { return }
                if !AVAudioSession.sharedInstance().currentRoute.inputs.contains(where: { $0.portType == .builtInMic }) {
                    self.stop(reason: "내장 마이크 연결이 변경되어 녹음을 종료했어요")
                }
            }
    }

    func url(for clip: RecordingClip) -> URL { directory.appendingPathComponent(clip.fileName) }
    private func metadataURL(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString + ".json") }
    private func persist(_ clip: RecordingClip) throws {
        try JSONEncoder().encode(clip).write(to: metadataURL(clip.id), options: .atomic)
    }

    func reload() {
        do {
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey])
            var found: [RecordingClip] = []
            for file in files where file.pathExtension == "m4a" {
                guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent), id != active?.id else { continue }
                if let data = try? Data(contentsOf: metadataURL(id)),
                   var clip = try? JSONDecoder().decode(RecordingClip.self, from: data), clip.id == id {
                    if clip.duration <= 0 {
                        guard let audio = try? AVAudioPlayer(contentsOf: file), audio.duration > 0 else { continue }
                        clip.duration = audio.duration
                        try persist(clip)
                    }
                    found.append(clip)
                } else if let audio = try? AVAudioPlayer(contentsOf: file), audio.duration > 0 {
                    // Recover a playable file if a previous run ended before writing its sidecar.
                    let date = (try? file.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
                    let clip = RecordingClip(id: id, createdAt: date, source: .local, duration: audio.duration)
                    try persist(clip); found.append(clip)
                }
            }
            clips = found.sorted { $0.createdAt > $1.createdAt }
        } catch { self.error = "녹음 목록을 읽지 못했어요: \(error.localizedDescription)" }
    }

    func requestPermission() async -> Bool {
        let application = AVAudioApplication.shared
        if application.recordPermission == .granted { return true }
        if application.recordPermission == .denied { return false }
        return await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
    }

    @discardableResult
    func start(id: UUID = UUID(), remotely: Bool = false, expiresAt: Date? = nil) async -> Bool {
        guard active == nil, !busy else { return false }
        busy = true
        defer { busy = false; onChange?() }
        error = nil
        let granted: Bool
        if remotely { granted = AVAudioApplication.shared.recordPermission == .granted }
        else { granted = await requestPermission() }
        guard granted else {
            notice = "이 기기에서 앱을 열고 마이크 접근을 허용해 주세요"
            error = notice; return false
        }
        guard expiresAt.map({ Date() <= $0 }) ?? true else {
            notice = "요청 시간이 지났어요. 워치에서 다시 눌러 주세요"; return false
        }
        stopPlayback()
        let clip = RecordingClip(id: id, createdAt: Date(), source: .local, duration: 0)
        do {
            let session = AVAudioSession.sharedInstance()
            #if os(watchOS)
            try session.setCategory(.playAndRecord, mode: .default)
            #else
            try session.setCategory(.record, mode: .default)
            #endif
            try session.setActive(true)
            #if os(iOS)
            if let mic = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
                try session.setPreferredInput(mic)
            }
            #endif
            guard session.currentRoute.inputs.contains(where: { $0.portType == .builtInMic }) else {
                throw NSError(domain: "QuietRecorder", code: 1, userInfo: [NSLocalizedDescriptionKey: "내장 마이크를 사용할 수 없어요"])
            }
            let space = try directory.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity ?? 0
            guard space > 10_000_000 else {
                throw NSError(domain: "QuietRecorder", code: 2, userInfo: [NSLocalizedDescriptionKey: "저장 공간이 부족해요"])
            }
            // Metadata is persisted before recording so interrupted files keep their source and date.
            try persist(clip)
            let audio = try AVAudioRecorder(url: url(for: clip), settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 96_000,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ])
            audio.delegate = self
            guard audio.prepareToRecord(), audio.record() else {
                throw NSError(domain: "QuietRecorder", code: 3, userInfo: [NSLocalizedDescriptionKey: "녹음을 시작할 수 없어요"])
            }
            recorder = audio; active = clip; elapsed = 0
            notice = "\(clip.source.title) 내장 마이크로 녹음 중"
            return true
        } catch {
            recorder = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            notice = remotely ? "아이폰 앱을 화면에 열고 다시 시도해 주세요" : "녹음을 시작하지 못했어요"
            self.error = "\(notice) · \(error.localizedDescription)"
            return false
        }
    }

    func stop(reason: String = "녹음을 저장했어요") {
        guard var clip = active, let audio = recorder else { return }
        clip.duration = max(elapsed, audio.currentTime)
        // Clear the delegate before stop so its callback cannot finalize twice.
        audio.delegate = nil; audio.stop(); recorder = nil; active = nil; elapsed = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        do {
            let saved = try AVAudioPlayer(contentsOf: url(for: clip))
            guard saved.duration > 0 else { throw CocoaError(.fileReadCorruptFile) }
            clip.duration = saved.duration
            try persist(clip)
            notice = reason; reload(); onSaved?()
        } catch {
            self.error = "저장 결과를 확인하지 못했어요. 원본 파일은 보관했어요: \(error.localizedDescription)"
            notice = "저장 확인 필요"; reload()
        }
        onChange?()
    }

    func importClip(_ clip: RecordingClip, from incoming: URL) throws {
        guard clip.source == .watch, clip.duration.isFinite, clip.duration > 0 else { throw CocoaError(.fileReadCorruptFile) }
        // An acknowledgement can be delayed: repeated delivery must not resurrect a deleted file.
        if (UserDefaults.standard.stringArray(forKey: "deletedWatchImports") ?? []).contains(clip.id.uuidString) { return }
        let target = url(for: clip)
        if !FileManager.default.fileExists(atPath: target.path) {
            let audio = try AVAudioPlayer(contentsOf: incoming)
            guard audio.duration > 0 else { throw CocoaError(.fileReadCorruptFile) }
            // Metadata first: a crash between the two writes will never label a Watch file as iPhone.
            var received = clip; received.receivedOnPhone = true; received.duration = audio.duration
            try persist(received)
            try FileManager.default.copyItem(at: incoming, to: target)
        } else {
            guard let data = try? Data(contentsOf: metadataURL(clip.id)),
                  let old = try? JSONDecoder().decode(RecordingClip.self, from: data), old.source == .watch else {
                throw CocoaError(.fileWriteFileExists)
            }
        }
        reload()
    }

    func acknowledge(_ id: UUID) {
        guard var clip = clips.first(where: { $0.id == id }), clip.source == .watch else { return }
        clip.receivedOnPhone = true
        do { try persist(clip); reload() } catch { self.error = error.localizedDescription }
    }

    func delete(_ clip: RecordingClip) {
        guard active?.id != clip.id else { return }
        if playingID == clip.id { stopPlayback() }
        do {
            #if os(iOS)
            if clip.source == .watch {
                var deleted = Set(UserDefaults.standard.stringArray(forKey: "deletedWatchImports") ?? [])
                deleted.insert(clip.id.uuidString)
                UserDefaults.standard.set(Array(deleted), forKey: "deletedWatchImports")
            }
            #endif
            try FileManager.default.removeItem(at: url(for: clip))
            try? FileManager.default.removeItem(at: metadataURL(clip.id))
            reload()
        } catch { self.error = "삭제하지 못했어요: \(error.localizedDescription)" }
    }

    func play(_ clip: RecordingClip) {
        guard active == nil, !busy else { return }
        if playingID == clip.id { stopPlayback(); return }
        stopPlayback()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            let audio = try AVAudioPlayer(contentsOf: url(for: clip))
            audio.delegate = self
            guard audio.play() else { throw CocoaError(.fileReadCorruptFile) }
            player = audio; playingID = clip.id
        } catch { self.error = "재생하지 못했어요: \(error.localizedDescription)"; stopPlayback() }
    }

    func stopPlayback() {
        let hadPlayer = player != nil
        player?.stop(); player = nil; playingID = nil
        if hadPlayer && active == nil { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            guard self.recorder === recorder else { return }
            self.stop(reason: flag ? "녹음을 저장했어요" : "녹음이 중단됐어요. 저장 파일을 확인해 주세요")
        }
    }
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in
            guard self.recorder === recorder else { return }
            self.stop(reason: "오디오 저장 오류로 녹음이 중단됐어요")
        }
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in if self.player === player { self.stopPlayback() } }
    }
}
