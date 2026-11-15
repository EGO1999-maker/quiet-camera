import Foundation
import WatchConnectivity
import Combine

@MainActor
final class RecorderLink: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = RecorderLink()
    @Published private(set) var reachable = false
    @Published private(set) var activated = false
    @Published private(set) var phone: PhoneStatus?
    @Published private(set) var confirmedAt: Date?
    @Published private(set) var pending = false
    @Published var notice = "연결 확인 중"
    @Published var remoteEnabled = UserDefaults.standard.bool(forKey: "allowWatchRecording") {
        didSet { UserDefaults.standard.set(remoteEnabled, forKey: "allowWatchRecording"); publishPhoneStatus() }
    }
    private var session: WCSession?
    private var requestID: UUID?
    private var handled: [UUID] = []
    private var newestCommand = Date.distantPast
    private let store = RecorderStore.shared
    private var wakeTasks: [CheckedContinuation<Void, Never>] = []
    private var pendingObservation: NSKeyValueObservation?

    private override init() {
        super.init()
        store.onChange = { [weak self] in self?.publishPhoneStatus() }
        store.onSaved = { [weak self] in self?.queueWatchFiles() }
        guard WCSession.isSupported() else { notice = "이 기기는 워치 연결을 지원하지 않아요"; return }
        session = WCSession.default
        session?.delegate = self
        pendingObservation = session?.observe(\.hasContentPending, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.finishWakeTasksIfReady() }
        }
        session?.activate()
    }

    var freshPhoneStatus: Bool {
        reachable && confirmedAt.map { Date().timeIntervalSince($0) < 15 } == true
    }

    func foregroundRefresh() {
        store.reload()
        updateReachability()
        #if os(watchOS)
        if !pending { send(.status) }
        queueWatchFiles()
        #else
        publishPhoneStatus()
        #endif
    }

    private func status() -> PhoneStatus {
        PhoneStatus(activeID: store.active?.id, startedAt: store.active?.createdAt,
                    remoteEnabled: remoteEnabled, notice: store.notice)
    }

    func publishPhoneStatus() {
        #if os(iOS)
        guard let session, session.activationState == .activated,
              let data = try? JSONEncoder().encode(status()) else { return }
        do { try session.updateApplicationContext(["status": data]) }
        catch { notice = "워치에 상태를 전달하지 못했어요" }
        #endif
    }

    private func updateReachability() {
        activated = session?.activationState == .activated
        reachable = activated && session?.isReachable == true
        if !reachable { confirmedAt = nil }
        #if os(iOS)
        if session?.isPaired != true { notice = "연결된 애플워치가 없어요" }
        else if session?.isWatchAppInstalled != true { notice = "워치용 앱을 먼저 설치해 주세요" }
        else { notice = reachable ? "워치와 연결됨" : "워치 앱을 열면 연결을 확인해요" }
        #else
        notice = reachable ? "아이폰에 연결됨" : "아이폰 연결을 확인해 주세요"
        #endif
    }

    func send(_ action: RecorderCommand.Action) {
        #if os(watchOS)
        guard !pending else { return }
        guard let session, session.activationState == .activated, session.isReachable else {
            confirmedAt = nil; notice = "아이폰이 연결되지 않았어요. 명령은 전송되지 않았어요"; return
        }
        if action != .status && !freshPhoneStatus {
            notice = "상태 새로고침 후 다시 눌러 주세요"; return
        }
        if action == .start && store.active != nil {
            notice = "워치 녹음을 먼저 종료해 주세요"; return
        }
        let command = RecorderCommand(action: action, expectedRecording: phone?.activeID)
        guard let data = try? JSONEncoder().encode(command) else { return }
        pending = true; requestID = command.id
        session.sendMessage(["command": data], replyHandler: { [weak self] reply in
            Task { @MainActor in
                guard let self, self.requestID == command.id else { return }
                self.pending = false; self.requestID = nil
                if let message = reply["error"] as? String { self.notice = message }
                if let data = reply["status"] as? Data { self.acceptStatus(data, confirmed: true) }
                if let message = reply["message"] as? String { self.notice = message }
            }
        }, errorHandler: { [weak self] _ in
            Task { @MainActor in
                guard let self, self.requestID == command.id else { return }
                self.pending = false; self.requestID = nil; self.confirmedAt = nil
                self.notice = action == .status ? "연결을 확인할 수 없어요" : "결과 미확인 · 상태를 새로고침해 주세요"
            }
        })
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard let self, self.requestID == command.id else { return }
            self.requestID = nil; self.pending = false; self.confirmedAt = nil
            self.notice = "응답 시간 초과 · 상태를 새로고침해 주세요"
        }
        #endif
    }

    private func acceptStatus(_ data: Data, confirmed: Bool) {
        guard let value = try? JSONDecoder().decode(PhoneStatus.self, from: data) else { return }
        guard phone.map({ value.updatedAt >= $0.updatedAt }) ?? true else { return }
        phone = value
        if confirmed { confirmedAt = Date() }
    }

    private func handle(_ command: RecorderCommand) async -> [String: Any] {
        #if os(iOS)
        var message: String?
        if command.action != .status {
            if !command.isFresh(at: Date()) {
                message = "요청 시간이 지났어요. 다시 눌러 주세요"
            } else if handled.contains(command.id) {
                // Duplicate delivery returns state; it must never create a second recording.
            } else if command.issuedAt < newestCommand {
                message = "이전 요청은 실행하지 않았어요"
            } else {
                newestCommand = command.issuedAt
                handled.append(command.id); handled = Array(handled.suffix(64))
                switch command.action {
                case .start:
                    if !remoteEnabled { message = "아이폰 앱에서 ‘워치 원격 녹음’을 허용해 주세요" }
                    else if store.active != nil || store.busy { message = "아이폰에서 이미 녹음 중이거나 준비 중이에요" }
                    else {
                        let success = await store.start(id: command.id, remotely: true, expiresAt: command.expiresAt)
                        message = success ? "아이폰 녹음을 시작했어요" : store.notice
                    }
                case .stop:
                    if command.mayStop(store.active?.id) { store.stop(); message = store.notice }
                    else { message = "녹음 상태가 바뀌었어요. 현재 상태를 확인해 주세요" }
                case .status: break
                }
            }
        }
        var reply: [String: Any] = [:]
        if let data = try? JSONEncoder().encode(status()) { reply["status"] = data }
        if let message { reply["message"] = message }
        return reply
        #else
        return ["error": "워치 녹음은 워치 화면에서 시작해 주세요"]
        #endif
    }

    func queueWatchFiles() {
        #if os(watchOS)
        guard let session, session.activationState == .activated, session.isCompanionAppInstalled else { return }
        let queued = Set(session.outstandingFileTransfers.compactMap { $0.file.metadata?["id"] as? String })
        for clip in store.clips where !clip.receivedOnPhone && !queued.contains(clip.id.uuidString) {
            guard let data = try? JSONEncoder().encode(clip) else { continue }
            session.transferFile(store.url(for: clip), metadata: ["id": clip.id.uuidString, "clip": data])
        }
        #endif
    }

    func removeLocal(_ clip: RecordingClip) {
        session?.outstandingFileTransfers.filter { $0.file.metadata?["id"] as? String == clip.id.uuidString }.forEach { $0.cancel() }
        store.delete(clip)
    }

    func handleBackgroundWake() async {
        guard session?.activationState != .activated || session?.hasContentPending == true else { return }
        await withCheckedContinuation { wakeTasks.append($0) }
    }
    private func finishWakeTasksIfReady() {
        guard session?.activationState == .activated, session?.hasContentPending != true else { return }
        let tasks = wakeTasks; wakeTasks.removeAll(); tasks.forEach { $0.resume() }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            self.updateReachability(); self.publishPhoneStatus(); self.queueWatchFiles()
            self.finishWakeTasksIfReady()
            #if os(watchOS)
            self.send(.status)
            #endif
        }
    }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.updateReachability() }
    }
    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor in self.updateReachability() }
    }
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.updateReachability(); self.publishPhoneStatus() }
    }
    #endif
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        guard let data = message["command"] as? Data,
              let command = try? JSONDecoder().decode(RecorderCommand.self, from: data) else {
            replyHandler(["error": "요청을 읽을 수 없어요"]); return
        }
        Task { @MainActor in replyHandler(await self.handle(command)) }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        guard let data = context["status"] as? Data else { return }
        Task { @MainActor in self.acceptStatus(data, confirmed: false); self.finishWakeTasksIfReady() }
    }
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let raw = userInfo["received"] as? String, let id = UUID(uuidString: raw) else { return }
        Task { @MainActor in self.store.acknowledge(id); self.finishWakeTasksIfReady() }
    }
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        #if os(iOS)
        guard let data = file.metadata?["clip"] as? Data,
              let clip = try? JSONDecoder().decode(RecordingClip.self, from: data), clip.source == .watch else { return }
        // WC removes its temporary file when this delegate returns. Copy before crossing queues.
        let staging = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Incoming", isDirectory: true)
        let saved = staging.appendingPathComponent(clip.id.uuidString + ".m4a")
        do {
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: saved.path) { try FileManager.default.removeItem(at: saved) }
            try FileManager.default.copyItem(at: file.fileURL, to: saved)
            Task { @MainActor in
                do {
                    try self.store.importClip(clip, from: saved)
                    session.transferUserInfo(["received": clip.id.uuidString])
                    try? FileManager.default.removeItem(at: saved)
                    self.notice = "워치 녹음이 도착했어요"
                } catch { self.store.error = "워치 녹음을 가져오지 못했어요. 워치 원본은 유지돼요: \(error.localizedDescription)" }
            }
        } catch { Task { @MainActor in self.store.error = "워치 파일 수신 실패: \(error.localizedDescription)" } }
        #endif
    }
    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        Task { @MainActor in
            if error != nil { self.notice = "파일 전송 실패 · 녹음 목록에서 다시 전송할 수 있어요" }
            self.finishWakeTasksIfReady()
        }
    }
}
