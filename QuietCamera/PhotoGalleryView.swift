import Photos
import SwiftUI
import UIKit

struct PhotoGalleryView: View {
    @ObservedObject var gallery: PhotoGalleryStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var path: [String] = []
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 3)

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if !gallery.canRead {
                    VStack(spacing: 18) {
                        Image(systemName: "photo.on.rectangle.angled").font(.largeTitle)
                        Text("촬영한 사진 보기").font(.title3.bold())
                        Text("사진을 보고 삭제하려면 사진 접근을 허용해 주세요. 선택한 사진만 허용해도 사용할 수 있어요.")
                            .multilineTextAlignment(.center).foregroundStyle(.secondary)
                        if gallery.authorization == .notDetermined {
                            Button("사진 접근 허용") { gallery.requestAccess() }.buttonStyle(.borderedProminent)
                        } else {
                            Button("아이폰 설정 열기") { openGallerySettings() }.buttonStyle(.borderedProminent)
                        }
                    }.padding(28)
                } else if gallery.loading && gallery.assets.isEmpty {
                    ProgressView("사진 불러오는 중")
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("촬영 순서 · 오래된 사진부터")
                                .font(.subheadline).foregroundStyle(.secondary)
                            if gallery.authorization == .limited {
                                Button("선택한 사진만 접근 중 · 설정에서 변경") { openGallerySettings() }
                                    .font(.caption)
                            }
                            if gallery.visibleRecords.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: "camera").font(.largeTitle)
                                    Text("표시할 촬영 사진이 없어요")
                                    Text("이 버전에서 찍은 사진부터 여기에 모여요.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity).padding(.vertical, 64)
                            }
                            LazyVGrid(columns: columns, spacing: 3) {
                                ForEach(gallery.visibleRecords) { record in
                                    if let asset = gallery.assets[record.id] {
                                        NavigationLink(value: record.id) {
                                            GeometryReader { geo in
                                                GalleryImage(asset: asset, fullSize: false)
                                                    .frame(width: geo.size.width, height: geo.size.height)
                                                    .clipped()
                                            }
                                            .aspectRatio(1, contentMode: .fit)
                                        }
                                        .accessibilityLabel("촬영 사진 \(record.capturedAt.formatted(date: .abbreviated, time: .standard))")
                                    }
                                }
                            }
                            if gallery.unavailableCount > 0 {
                                Text("목록 중 \(gallery.unavailableCount)장은 현재 접근할 수 없어요. 선택한 사진 권한에서 제외되었거나 사진 앱에서 삭제된 사진일 수 있어요.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(12)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
            .navigationTitle("촬영한 사진")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("완료") { dismiss() }.disabled(gallery.deleting) }
            }
            .background(GalleryEdgeDismiss(enabled: path.isEmpty && !gallery.deleting) { dismiss() })
            .navigationDestination(for: String.self) { id in
                GalleryDetailView(gallery: gallery, initialID: id, closeGallery: { dismiss() })
            }
            .onAppear { gallery.refresh() }
            .onChange(of: scenePhase) { if $0 == .active { gallery.refresh() } }
            .alert("확인해 주세요", isPresented: Binding(
                get: { gallery.message != nil }, set: { if !$0 { gallery.message = nil } })) {
                    Button("확인", role: .cancel) { gallery.message = nil }
                } message: { Text(gallery.message ?? "") }
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(gallery.deleting)
    }
}

private struct GalleryDetailView: View {
    @ObservedObject var gallery: PhotoGalleryStore
    let closeGallery: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selection: String
    @State private var previousIDs: [String]
    @State private var confirmDelete = false
    @State private var deletionID: String?

    init(gallery: PhotoGalleryStore, initialID: String, closeGallery: @escaping () -> Void) {
        self.gallery = gallery
        self.closeGallery = closeGallery
        _selection = State(initialValue: initialID)
        _previousIDs = State(initialValue: gallery.visibleRecords.map(\.id))
    }

    private var selectedRecord: GalleryRecord? { gallery.visibleRecords.first { $0.id == selection } }
    private var currentNumber: Int { (gallery.visibleRecords.firstIndex { $0.id == selection } ?? 0) + 1 }

    var body: some View {
        GalleryPager(records: gallery.visibleRecords, assets: gallery.assets,
                     selection: $selection, locked: gallery.deleting || confirmDelete)
        .frame(maxWidth: .infinity, maxHeight: .infinity).background(.black)
        .navigationTitle(selectedRecord?.capturedAt.formatted(date: .abbreviated, time: .shortened) ?? "촬영한 사진")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(gallery.deleting || confirmDelete)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(role: .destructive) {
                    deletionID = selection
                    confirmDelete = true
                } label: { Image(systemName: "trash") }
                .disabled(gallery.deleting || selectedRecord == nil)
                .accessibilityLabel("현재 사진 삭제")
                Button("완료") { closeGallery() }.disabled(gallery.deleting)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if gallery.deleting { ProgressView("삭제 처리 중").padding() }
            else {
                VStack(spacing: 4) {
                    Text("\(currentNumber) / \(gallery.visibleRecords.count)").monospacedDigit()
                    Text("좌우로 넘기기 · 두 손가락 확대 · 두 번 탭으로 복원")
                }.font(.caption).foregroundStyle(.secondary).padding(12)
            }
        }
        .onChange(of: gallery.visibleRecords.map(\.id)) { ids in
            // Keep the same photo across refreshes. After removal prefer the
            // next surviving capture, then the previous one.
            if let retained = GallerySelection.retainedID(selection, before: previousIDs, after: ids) {
                selection = retained
            } else { dismiss() }
            previousIDs = ids
        }
        .confirmationDialog("이 사진을 삭제할까요?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("사진 삭제", role: .destructive) {
                guard let id = deletionID else { return }
                gallery.delete(id: id) { _ in }
            }
            Button("취소", role: .cancel) { deletionID = nil }
        } message: {
            Text("아이폰 사진 보관함에서도 삭제됩니다. iCloud 사진을 사용하면 연결된 기기에도 반영됩니다.")
        }
    }
}

/// Each cell owns and cancels its PhotoKit request; no full-library image cache.
struct GalleryImage: View {
    let asset: PHAsset
    let fullSize: Bool
    var onZoomChanged: ((Bool) -> Void)? = nil
    @StateObject private var loader = GalleryImageLoader()

    var body: some View {
        ZStack {
            Color(white: 0.12)
            if let image = loader.image {
                if fullSize { ZoomablePhoto(image: image, onZoomChanged: onZoomChanged) }
                else { Image(uiImage: image).resizable().scaledToFill() }
            } else if loader.failed {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.icloud")
                    if fullSize {
                        Text("사진을 불러오지 못했어요").font(.caption)
                        Button("다시 시도") { loader.load(asset: asset, fullSize: fullSize) }
                    }
                }
            } else { ProgressView().tint(.white) }
        }
        .onAppear { loader.load(asset: asset, fullSize: fullSize) }
        .onChange(of: asset.localIdentifier) { _ in loader.load(asset: asset, fullSize: fullSize) }
        .onDisappear { loader.cancel() }
    }
}

private final class GalleryImageLoader: ObservableObject {
    @Published var image: UIImage?
    @Published var failed = false
    private var request: PHImageRequestID?
    private var token = UUID()

    func load(asset: PHAsset, fullSize: Bool) {
        cancel()
        image = nil; failed = false
        let current = token
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        let target = fullSize ? PHImageManagerMaximumSize : CGSize(width: 360, height: 360)
        request = PHImageManager.default().requestImage(for: asset, targetSize: target,
            contentMode: fullSize ? .aspectFit : .aspectFill, options: options) { [weak self] image, info in
                DispatchQueue.main.async {
                    guard let self, self.token == current else { return }
                    self.image = image
                    self.failed = image == nil
                }
            }
    }

    func cancel() {
        token = UUID()
        if let request { PHImageManager.default().cancelImageRequest(request) }
        request = nil
    }

    deinit { if let request { PHImageManager.default().cancelImageRequest(request) } }
}

private func openGallerySettings() {
    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
}
