import Combine
import Foundation
import CoreGraphics

/// Deterministic chrome state for the reader.  The previous implementation
/// kept `showOverlay` and `showSettings` as two independent booleans; a
/// delayed SwiftUI update could therefore leave the settings sheet visible
/// after the menu had been dismissed (or vice versa).  A single state makes
/// every exit path converge on one transition and is straightforward to test
/// without rendering UIKit.
enum ReaderChromeMode: Equatable {
    case hidden
    case overlay
    case settings
}

struct ReaderChromeStateMachine: Equatable {
    private(set) var mode: ReaderChromeMode = .hidden

    var isOverlayVisible: Bool { mode != .hidden }
    var isSettingsVisible: Bool { mode == .settings }

    mutating func setInitialOverlayVisible(_ visible: Bool) {
        mode = visible ? .overlay : .hidden
    }

    mutating func toggleOverlay() {
        mode = mode == .hidden ? .overlay : .hidden
    }

    mutating func openSettings() {
        mode = .settings
    }

    /// Closing settings intentionally returns to the reader menu.  This keeps
    /// the reader action bar available while ensuring the settings surface is
    /// never stranded above a hidden overlay.
    mutating func closeSettings() {
        if mode == .settings { mode = .overlay }
    }

    mutating func closeAll() {
        mode = .hidden
    }
}

/// Deterministic decisions for automatic reader advancement.
/// Kept independent from SwiftUI so chapter-boundary behavior is testable on CI.
enum ReaderAdvanceDecision: Equatable {
    case advance(to: Int)
    case nextChapter
    case stop
}

struct ReaderAutomationPolicy {
    /// Keep automation responsive without allowing a malformed persisted value
    /// to create a busy loop (or an animation that effectively never moves).
    static func clampedDelay(_ rawValue: Double) -> Double {
        guard rawValue.isFinite else { return 2.0 }
        return min(max(rawValue, 0.25), 30)
    }

    static func decision(
        currentTarget: Int,
        maximumTarget: Int,
        canAdvanceChapter: Bool
    ) -> ReaderAdvanceDecision {
        guard maximumTarget >= 0 else {
            return canAdvanceChapter ? .nextChapter : .stop
        }
        guard currentTarget < maximumTarget else {
            return canAdvanceChapter ? .nextChapter : .stop
        }
        return .advance(to: currentTarget + 1)
    }

    /// Snapshot the reader cursor before automation starts.
    /// The first auto-scroll tick should begin from what the user can see now,
    /// not from a stale automation target left behind by a prior session.
    static func startingAutoScrollTarget(
        mode: ReaderMode,
        visibleParagraphIndex: Int,
        pagedPageIndex: Int,
        maximumTarget: Int
    ) -> Int {
        let rawTarget: Int
        switch mode {
        case .scroll:
            rawTarget = visibleParagraphIndex
        case .pageTurn, .cover:
            rawTarget = pagedPageIndex
        }
        return min(max(rawTarget, 0), maximumTarget)
    }
}

enum ReaderPagedSwipeDecision: Equatable {
    case previous
    case next
}

enum ReaderPagedSwipePolicy {
    static func decision(
        horizontal: CGFloat,
        vertical: CGFloat,
        minimumDistance: CGFloat = 40,
        axisBias: CGFloat = 1.15
    ) -> ReaderPagedSwipeDecision? {
        guard abs(horizontal) >= minimumDistance else { return nil }
        guard abs(horizontal) > abs(vertical) * axisBias else { return nil }
        return horizontal < 0 ? .next : .previous
    }
}

struct ReaderCoverSwipeState: Equatable {
    var translation: CGFloat = 0
    var isHorizontal: Bool = false
}

/// The small, deterministic state machine shared by the reader's automation
/// controls.  Keeping the transitions outside SwiftUI prevents an old timer,
/// speech callback, or scene lifecycle event from reviving a newer session.
enum ReaderPlaybackMode: Equatable {
    case idle
    case autoScroll(generation: Int)
    case speech(generation: Int)
    case pausedSpeech(generation: Int)
}

struct ReaderPlaybackStateMachine: Equatable {
    private(set) var mode: ReaderPlaybackMode = .idle
    private(set) var generation: Int = 0

    mutating func beginAutoScroll() -> Int {
        generation &+= 1
        mode = .autoScroll(generation: generation)
        return generation
    }

    mutating func beginSpeech() -> Int {
        generation &+= 1
        mode = .speech(generation: generation)
        return generation
    }

    mutating func pauseSpeech() {
        if case .speech(let token) = mode {
            mode = .pausedSpeech(generation: token)
        }
    }

    mutating func resumeSpeech() {
        if case .pausedSpeech(let token) = mode {
            mode = .speech(generation: token)
        }
    }

    mutating func stop() {
        generation &+= 1
        mode = .idle
    }

    func accepts(_ token: Int, for expectedMode: ReaderPlaybackMode) -> Bool {
        guard token == generation else { return false }
        switch (mode, expectedMode) {
        case (.autoScroll(let active), .autoScroll):
            return active == token
        case (.speech(let active), .speech), (.pausedSpeech(let active), .pausedSpeech):
            return active == token
        default:
            return false
        }
    }
}

final class ReaderPlaybackCoordinator: ObservableObject {
    @Published private(set) var state = ReaderPlaybackStateMachine()

    var mode: ReaderPlaybackMode { state.mode }

    func beginAutoScroll() -> Int { state.beginAutoScroll() }
    func beginSpeech() -> Int { state.beginSpeech() }
    func pauseSpeech() { state.pauseSpeech() }
    func resumeSpeech() { state.resumeSpeech() }
    func stop() { state.stop() }

    func accepts(_ token: Int, for expectedMode: ReaderPlaybackMode) -> Bool {
        state.accepts(token, for: expectedMode)
    }
}

/// Deterministic segment queue used by the AVSpeech controller.
struct ReaderSpeechQueue: Equatable {
    private(set) var segments: [String] = []
    private(set) var paragraphIndexes: [Int] = []
    private(set) var nextIndex = 0

    var isFinished: Bool { nextIndex >= segments.count }

    mutating func reset(
        title: String,
        paragraphs: [String],
        startParagraphIndex: Int = 0,
        includeTitle: Bool = true
    ) {
        segments = []
        paragraphIndexes = []
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeStart = min(max(startParagraphIndex, 0), max(paragraphs.count - 1, 0))
        // The chapter title is useful only when playback starts at the actual
        // chapter beginning. Starting TTS from a visible page must never jump
        // back to the title or earlier paragraphs.
        if includeTitle, safeStart == 0, !trimmedTitle.isEmpty {
            segments.append(trimmedTitle)
            paragraphIndexes.append(-1)
        }
        for (index, paragraph) in paragraphs.enumerated() where index >= safeStart {
            let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            segments.append(trimmed)
            paragraphIndexes.append(index)
        }
        nextIndex = 0
    }

    mutating func dequeue() -> (index: Int, text: String)? {
        guard segments.indices.contains(nextIndex) else { return nil }
        let index = nextIndex
        nextIndex += 1
        return (paragraphIndexes[index], segments[index])
    }

    mutating func clear() {
        segments = []
        paragraphIndexes = []
        nextIndex = 0
    }
}
