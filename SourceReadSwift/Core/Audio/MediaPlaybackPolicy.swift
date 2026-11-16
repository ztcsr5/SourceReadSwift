import Foundation

/// Shared conversion rules for saved audio/video progress. Directory indices can be sparse.
enum MediaPlaybackPolicy {
    enum Resume: Equatable {
        case waitForDuration, fromStart, seek(Double)
    }

    static func episodeOffset(for chapterIndex: Int, in chapters: [BookChapter]) -> Int {
        chapters.firstIndex { $0.index == chapterIndex } ?? min(max(chapterIndex, 0), max(chapters.count - 1, 0))
    }

    static func recordedSecond(_ time: Double) -> Int? {
        guard time.isFinite, time >= 0, time < Double(Int.max) else { return nil }
        return Int(time)
    }

    static func resume(at time: Double?, duration: Double) -> Resume {
        guard let time, recordedSecond(time) != nil, time > 0 else { return .fromStart }
        guard duration.isFinite, duration > 0 else { return .waitForDuration }
        return time < duration ? .seek(time) : .fromStart
    }
}

/// Serializes playback ownership on the main thread, including the NSObject speech delegate.
final class MediaPlaybackOwnership {
    static let shared = MediaPlaybackOwnership()

    private var owner: UUID?
    private var relinquish: (() -> Void)?

    func claim(_ route: UUID, relinquish: @escaping () -> Void) {
        precondition(Thread.isMainThread)
        guard owner != route else { return }
        let previous = self.relinquish
        owner = route
        self.relinquish = relinquish
        previous?()
    }

    func owns(_ route: UUID) -> Bool {
        precondition(Thread.isMainThread)
        return owner == route
    }

    @discardableResult
    func release(_ route: UUID) -> Bool {
        guard owns(route) else { return false }
        owner = nil
        relinquish = nil
        return true
    }
}
