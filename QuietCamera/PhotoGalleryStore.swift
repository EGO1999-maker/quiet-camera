import Combine
import Photos
import UIKit

/// UI and index mutations run on main. PhotoKit fetching runs off main.
final class PhotoGalleryStore: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    static let shared = PhotoGalleryStore()
    @Published private(set) var records: [GalleryRecord] = []
    @Published private(set) var assets: [String: PHAsset] = [:]
    @Published private(set) var authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published private(set) var loading = false
    @Published private(set) var deleting = false
    @Published var message: String?
    private var index = GalleryIndex()
    private var indexReadable = true
    private var generation = UUID()
    private let worker = DispatchQueue(label: "QuietCamera.gallery", qos: .userInitiated)
    private let indexURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("QuietCamera/gallery.json")

    var canRead: Bool { authorization == .authorized || authorization == .limited }
    var visibleRecords: [GalleryRecord] { records.filter { assets[$0.id] != nil } }
    var unavailableCount: Int { records.count - visibleRecords.count }

    private override init() {
        super.init()
        do { index = try GalleryIndex.read(from: indexURL); records = index.records }
        catch {
            indexReadable = false
            message = "촬영 목록을 읽지 못했어요. 사진 앱의 원본은 그대로 있어요."
        }
        PHPhotoLibrary.shared().register(self)
        refresh()
    }

    deinit { PHPhotoLibrary.shared().unregisterChangeObserver(self) }

    func addSavedPhoto(id: String, capturedAt: Date) {
        index.append(id: id, capturedAt: capturedAt)
        records = index.records
        persist()
        refresh()
    }

    private func persist() {
        guard indexReadable else {
            message = "기존 촬영 목록을 읽지 못해 새 목록을 저장하지 못했어요. 원본은 사진 앱에 저장돼요."
            return
        }
        do { try index.write(to: indexURL) }
        catch { message = "촬영 목록을 저장하지 못했어요. 저장 공간을 확인해 주세요. 원본은 사진 앱에 있어요." }
    }

    func requestAccess() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }
    }

    func refresh() {
        authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let token = UUID()
        generation = token
        guard canRead else { assets = [:]; loading = false; return }
        let ids = records.map(\.id)
        loading = true
        worker.async { [weak self] in
            let result = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
            var found: [String: PHAsset] = [:]
            result.enumerateObjects { asset, _, _ in found[asset.localIdentifier] = asset }
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                self.assets = found
                self.loading = false
            }
        }
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        DispatchQueue.main.async { [weak self] in self?.refresh() }
    }

    /// Capture the confirmed ID, never a mutable selection or an array index.
    func delete(id: String, completion: @escaping (Bool) -> Void) {
        guard !deleting else { return }
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard current == .authorized || current == .limited,
              records.contains(where: { $0.id == id }),
              let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else {
            message = "이 사진에 접근할 수 없어요. 사진 권한 또는 사진 앱의 원본을 확인해 주세요."
            refresh()
            completion(false)
            return
        }
        deleting = true
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.deleteAssets([asset] as NSArray)
        }) { [weak self] success, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.deleting = false
                if success {
                    self.index.remove(id: id)
                    self.records = self.index.records
                    self.assets.removeValue(forKey: id)
                    self.persist()
                } else {
                    self.message = "사진 삭제가 취소되었거나 완료되지 않았어요. 사진은 목록에서 지우지 않았어요."
                }
                self.refresh()
                completion(success)
            }
        }
    }
}
