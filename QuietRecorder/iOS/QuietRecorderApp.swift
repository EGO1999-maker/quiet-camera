import SwiftUI

@main
@MainActor
struct QuietRecorderApp: App {
    init() { _ = RecorderLink.shared }
    var body: some Scene {
        WindowGroup {
            PhoneRecorderView()
                .preferredColorScheme(.dark)
                .tint(Color(red: 1, green: 0.73, blue: 0.82))
        }
    }
}

struct PhoneRecorderView: View {
    @StateObject private var store = RecorderStore.shared
    @StateObject private var link = RecorderLink.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var deletion: RecordingClip?
    @State private var requestingPermission = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 18) {
                        Label("아이폰 내장 마이크", systemImage: "iphone")
                            .font(.headline).foregroundStyle(.secondary)
                        Text(RecordingTime.text(store.elapsed))
                            .font(.system(size: 48, weight: .light, design: .rounded)).monospacedDigit()
                        Button {
                            if store.active != nil { store.stop() }
                            else { Task { await store.start() } }
                        } label: {
                            Label(store.active == nil ? "녹음 시작" : "종료하고 저장",
                                  systemImage: store.active == nil ? "mic.fill" : "stop.fill")
                                .font(.title3.bold()).frame(maxWidth: .infinity).padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent).foregroundStyle(.black).disabled(store.busy)
                        Text(store.notice).font(.footnote).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).padding(.vertical)
                } footer: {
                    Text("시작·종료 효과음은 재생하지 않아요. 재생 버튼을 누르면 녹음된 소리가 나요.")
                }
                Section("애플워치") {
                    Toggle("워치 원격 녹음", isOn: Binding(get: { link.remoteEnabled }, set: { enabled in
                        if !enabled { link.remoteEnabled = false; return }
                        requestingPermission = true
                        Task {
                            let granted = await store.requestPermission()
                            link.remoteEnabled = granted; requestingPermission = false
                            if !granted { store.error = "설정에서 Quiet Recorder의 마이크 접근을 허용해 주세요" }
                        }
                    })).disabled(requestingPermission)
                    Label(link.notice, systemImage: "applewatch").font(.subheadline).foregroundStyle(.secondary)
                    Text("워치 앱에서 녹음할 기기를 선택하세요. ‘아이폰’은 아이폰 주변, ‘워치’는 손목 주변 소리를 녹음해요.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("아이폰 원격 시작이 실패하면 이 앱을 화면에 열고 다시 시도하세요. 시작한 녹음은 화면이 꺼져도 계속할 수 있어요. 통화 등으로 중단되면 다시 시작해야 해요.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("저장된 녹음 · \(store.clips.count)") {
                    if store.clips.isEmpty { Text("저장된 녹음이 없어요").foregroundStyle(.secondary) }
                    ForEach(store.clips) { clip in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label(clip.source.title, systemImage: clip.source.symbol).foregroundStyle(.pink)
                                Spacer()
                                Text(RecordingTime.text(clip.duration)).monospacedDigit()
                            }.font(.subheadline)
                            Text(clip.createdAt.formatted(date: .abbreviated, time: .standard)).font(.headline)
                            HStack(spacing: 22) {
                                Button { store.play(clip) } label: {
                                    Label(store.playingID == clip.id ? "재생 중지" : "재생",
                                          systemImage: store.playingID == clip.id ? "stop.circle" : "play.circle")
                                }.disabled(store.active != nil || store.busy)
                                ShareLink(item: store.url(for: clip)) { Label("공유", systemImage: "square.and.arrow.up") }
                                Spacer()
                                Button(role: .destructive) { deletion = clip } label: { Image(systemName: "trash") }
                                    .accessibilityLabel("녹음 삭제")
                            }.buttonStyle(.borderless)
                        }.padding(.vertical, 6)
                    }
                } footer: {
                    Text("최신순으로 표시해요. 삭제는 이 기기에 저장된 파일에만 적용돼요. 앱을 삭제하면 로컬 녹음도 지워지므로 필요한 파일은 공유로 내보내 주세요.")
                }
                Section {
                    Text("Quiet Recorder · 1.0.0").foregroundStyle(.secondary)
                }
            }
            .navigationTitle("조용한 녹음")
            .onAppear { link.foregroundRefresh() }
            .onChange(of: scenePhase) { phase in if phase == .active { link.foregroundRefresh() } }
            .alert("녹음 삭제", isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } })) {
                Button("삭제", role: .destructive) { if let deletion { link.removeLocal(deletion) }; deletion = nil }
                Button("취소", role: .cancel) { deletion = nil }
            } message: { Text("아이폰에 저장된 이 녹음을 삭제할까요? 복구할 수 없어요.") }
            .alert("확인해 주세요", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                Button("확인") { store.error = nil }
            } message: { Text(store.error ?? "") }
        }
    }
}
