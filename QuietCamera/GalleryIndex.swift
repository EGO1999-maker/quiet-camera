import Foundation

/// Append order is capture order, even when the device clock changes.
/// Keep inaccessible IDs: limited permission must never erase the capture history.
struct GalleryRecord: Codable, Identifiable, Equatable {
    let id: String
    let capturedAt: Date
}

struct GalleryIndex: Codable {
    private(set) var records: [GalleryRecord] = []

    mutating func append(id: String, capturedAt: Date) {
        guard !records.contains(where: { $0.id == id }) else { return }
        records.append(GalleryRecord(id: id, capturedAt: capturedAt))
    }

    mutating func remove(id: String) {
        records.removeAll { $0.id == id }
    }

    static func read(from url: URL) throws -> GalleryIndex {
        guard FileManager.default.fileExists(atPath: url.path) else { return GalleryIndex() }
        return try JSONDecoder().decode(GalleryIndex.self, from: Data(contentsOf: url))
    }

    func write(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
}
