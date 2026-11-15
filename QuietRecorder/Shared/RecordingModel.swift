import Foundation

enum RecordingSource: String, Codable, CaseIterable, Identifiable {
    case watch, phone
    var id: String { rawValue }
    var title: String { self == .watch ? "워치" : "아이폰" }
    var symbol: String { self == .watch ? "applewatch" : "iphone" }
    static var local: Self {
        #if os(watchOS)
        return .watch
        #else
        return .phone
        #endif
    }
}

struct RecordingClip: Codable, Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    let source: RecordingSource
    var duration: TimeInterval
    var receivedOnPhone: Bool = false
    var fileName: String { id.uuidString + ".m4a" }
}

struct PhoneStatus: Codable {
    var activeID: UUID?
    var startedAt: Date?
    var remoteEnabled: Bool
    var notice: String
    var updatedAt: Date = Date()
}

struct RecorderCommand: Codable {
    enum Action: String, Codable { case status, start, stop }
    let id: UUID
    let action: Action
    let expectedRecording: UUID?
    let issuedAt: Date
    let expiresAt: Date

    init(action: Action, expectedRecording: UUID? = nil, now: Date = Date()) {
        id = UUID(); self.action = action; self.expectedRecording = expectedRecording
        issuedAt = now; expiresAt = now.addingTimeInterval(8)
    }

    func isFresh(at now: Date) -> Bool {
        now <= expiresAt && now.timeIntervalSince(issuedAt) >= -5 &&
        expiresAt.timeIntervalSince(issuedAt) > 0 && expiresAt.timeIntervalSince(issuedAt) <= 10
    }

    func mayStop(_ activeID: UUID?) -> Bool {
        action == .stop && expectedRecording != nil && expectedRecording == activeID
    }
}

enum RecordingTime {
    static func text(_ seconds: TimeInterval) -> String {
        let n = seconds.isFinite ? max(0, Int(seconds)) : 0
        return n >= 3600 ? String(format: "%d:%02d:%02d", n / 3600, n / 60 % 60, n % 60)
                        : String(format: "%02d:%02d", n / 60, n % 60)
    }
}
