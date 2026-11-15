import Foundation

@main
struct GalleryIndexTests {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("gallery.json")
        var index = try GalleryIndex.read(from: url)
        assert(index.records.isEmpty)
        index.append(id: "first", capturedAt: Date(timeIntervalSince1970: 200))
        // Clock rollback must not reorder actual captures.
        index.append(id: "second", capturedAt: Date(timeIntervalSince1970: 100))
        index.append(id: "third", capturedAt: Date(timeIntervalSince1970: 100))
        index.append(id: "second", capturedAt: Date())
        try index.write(to: url)
        var reopened = try GalleryIndex.read(from: url)
        assert(reopened.records.map(\.id) == ["first", "second", "third"])
        reopened.remove(id: "second")
        reopened.remove(id: "absent")
        try reopened.write(to: url)
        let afterDeletion = try GalleryIndex.read(from: url)
        assert(afterDeletion.records.map(\.id) == ["first", "third"])
        try Data("corrupt".utf8).write(to: url)
        do {
            _ = try GalleryIndex.read(from: url)
            fatalError("Corrupt history must not silently become an empty index")
        } catch { }
        let ordered = ["first", "second", "third", "fourth"]
        assert(GallerySelection.retainedID("second", before: ordered, after: ordered) == "second")
        assert(GallerySelection.retainedID("second", before: ordered, after: ["first", "third", "fourth"]) == "third")
        assert(GallerySelection.retainedID("fourth", before: ordered, after: ["first", "third"]) == "third")
        assert(GallerySelection.retainedID("second", before: ordered, after: ["fourth"]) == "fourth")
        assert(GallerySelection.retainedID("first", before: ["first"], after: []) == nil)
        print("Gallery selection checks passed: keep current, middle/last deletion, limited access and empty list.")
        print("Gallery history checks passed: capture order, restart, duplicate prevention, exact deletion and corrupt data.")
    }
}
