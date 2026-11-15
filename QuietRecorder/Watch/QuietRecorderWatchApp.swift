import SwiftUI

@main
@MainActor
struct QuietRecorderWatchApp: App {
    init() { _ = RecorderLink.shared }
    var body: some Scene {
        WindowGroup {
            WatchRecorderView().tint(Color(red: 1, green: 0.73, blue: 0.82))
        }
        .backgroundTask(.watchConnectivity) { await RecorderLink.shared.handleBackgroundWake() }
    }
}

struct WatchRecorderView: View {
    @StateObject private var store = RecorderStore.shared
    @StateObject private var link = RecorderLink.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var source: RecordingSource = .watch
    private let refresh = Timer.publish(every: 6, on: .main, in: .common).autoconnect()

    private var selectedIsRecording: Bool { source == .watch ? store.active != nil : link.phone?.activeID != nil }
    private var selectionLocked: Bool { store.active != nil || store.busy || link.pending || (link.freshPhoneStatus && link.phone?.activeID != nil) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    Picker("녹음 기기", selection: $source) {
                        ForEach(RecordingSource.allCases) { device in
                            Label(device.title, systemImage: device.symbol).tag(device)
                        }
                    }.pickerStyle(.navigationLink).disabled(selectionLocked)
                    Text(source == .watch ? "손목 주변 소리" : "아이폰 주변 소리")
                        .font(.caption).foregroundStyle(.secondary)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let duration = source == .watch ? store.elapsed :
                            (link.phone?.startedAt.map { context.date.timeIntervalSince($0) } ?? 0)
                        Text(source == .phone && !link.freshPhoneStatus ? "--:--" : RecordingTime.text(duration))
                            .font(.system(size: 34, weight: .light, design: .rounded)).monospacedDigit()
                    }
                    Button {
                        if source == .watch {
                            if store.active != nil { store.stop() }
                            else { Task { await store.start() } }
                        } else { link.send(selectedIsRecording ? .stop : .start) }
                    } label: {
                        Label(selectedIsRecording ? "종료 · 저장" : "녹음 시작", systemImage: selectedIsRecording ? "stop.fill" : "mic.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).foregroundStyle(.black)
                    .disabled(store.busy || link.pending || (source == .phone && (!link.freshPhoneStatus || (link.phone?.remoteEnabled != true && !selectedIsRecording))))
                    Text(source == .watch ? store.notice : link.notice)
                        .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    if source == .phone {
                        Button("상태 새로고침", systemImage: "arrow.clockwise") { link.send(.status) }
                            .disabled(link.pending)
                        if !link.freshPhoneStatus {
                            Text("현재 아이폰 녹음 상태를 확인해 주세요. 확인 전에는 기기를 바꿔도 아이폰 녹음이 종료되지 않아요.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    NavigationLink { WatchRecordingsView() } label: {
                        Label("워치 녹음 \(store.clips.count)개", systemImage: "list.bullet")
                    }
                }
            }
            .navigationTitle("조용한 녹음")
            .onAppear { link.foregroundRefresh() }
            .onReceive(link.$phone) { phone in
                if phone?.activeID != nil && store.active == nil { source = .phone }
            }
            .onChange(of: scenePhase) { _, phase in if phase == .active { link.foregroundRefresh() } }
            .onReceive(refresh) { _ in
                if scenePhase == .active && source == .phone && !link.pending { link.send(.status) }
            }
            .alert("확인해 주세요", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                Button("확인") { store.error = nil }
            } message: { Text(store.error ?? "") }
        }
    }
}

struct WatchRecordingsView: View {
    @ObservedObject private var store = RecorderStore.shared
    @ObservedObject private var link = RecorderLink.shared
    @State private var deletion: RecordingClip?
    var body: some View {
        List {
            Button("아이폰으로 다시 전송") { link.queueWatchFiles() }
            Text("연결되면 자동 전송해요. 전송 완료 후에도 워치 원본은 남아요.")
                .font(.caption2).foregroundStyle(.secondary)
            if store.clips.isEmpty { Text("워치에 저장된 녹음이 없어요") }
            ForEach(store.clips) { clip in
                VStack(alignment: .leading, spacing: 6) {
                    Text(clip.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.headline)
                    Text(RecordingTime.text(clip.duration)).monospacedDigit()
                    Label(clip.receivedOnPhone ? "아이폰 저장 확인됨" : "아이폰 저장 확인 대기",
                          systemImage: clip.receivedOnPhone ? "checkmark.circle" : "clock")
                        .font(.caption2).foregroundStyle(.secondary)
                    Button(store.playingID == clip.id ? "재생 중지" : "재생") { store.play(clip) }
                        .disabled(store.active != nil || store.busy)
                    Button("워치에서 삭제", role: .destructive) { deletion = clip }
                }
            }
        }
        .navigationTitle("워치 녹음")
        .alert("워치 녹음 삭제", isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } })) {
            Button("삭제", role: .destructive) { if let deletion { link.removeLocal(deletion) }; deletion = nil }
            Button("취소", role: .cancel) { deletion = nil }
        } message: {
            Text(deletion?.receivedOnPhone == true ? "워치 원본을 삭제할까요? 아이폰 사본은 남아요." : "아이폰 저장이 아직 확인되지 않았어요. 워치 원본을 삭제하면 녹음을 잃을 수 있어요.")
        }
    }
}
