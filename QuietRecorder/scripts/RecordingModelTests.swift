import Foundation

@main struct Tests {
    static func main() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let start = RecorderCommand(action: .start, now: now)
        precondition(start.isFresh(at: now.addingTimeInterval(2)))
        precondition(!start.isFresh(at: now.addingTimeInterval(9)), "Delayed requests must not record later")
        precondition(!start.isFresh(at: now.addingTimeInterval(-20)))
        let first = UUID(), second = UUID()
        let stop = RecorderCommand(action: .stop, expectedRecording: first, now: now)
        precondition(stop.mayStop(first))
        precondition(!stop.mayStop(second), "Stale stop must not end a different recording")
        precondition(!stop.mayStop(nil))
        precondition(!RecorderCommand(action: .stop, now: now).mayStop(nil))
        let decoded = try JSONDecoder().decode(RecorderCommand.self, from: JSONEncoder().encode(stop))
        precondition(decoded.id == stop.id && decoded.mayStop(first))
        let clip = RecordingClip(id: first, createdAt: now, source: .watch, duration: 72.5)
        let decodedClip = try JSONDecoder().decode(RecordingClip.self, from: JSONEncoder().encode(clip))
        precondition(decodedClip == clip)
        precondition(clip.fileName == first.uuidString + ".m4a")
        precondition(RecordingTime.text(72.5) == "01:12")
        precondition(RecordingTime.text(3661) == "1:01:01")
        precondition(RecordingTime.text(-3) == "00:00")
        print("Recorder command expiry, session targeting, metadata and time tests passed")
    }
}
