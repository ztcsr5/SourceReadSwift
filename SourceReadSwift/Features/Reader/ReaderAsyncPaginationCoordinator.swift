import Foundation
import SwiftUI

/// Determines whether a paged chapter rebuild can reuse synchronous cache lookup
/// or should offload TextKit pagination onto the cooperative thread pool.
enum ReaderPaginationSchedulingPolicy {
    static func shouldPaginateOffMainActor(
        hasExistingPages: Bool,
        activeChapterCharacterCount: Int,
        forceAsync: Bool
    ) -> Bool {
        if forceAsync || hasExistingPages {
            return true
        }
        return activeChapterCharacterCount > ReaderPerformancePolicy.inlinePaginationCharacterThreshold
    }

    static func characterCount(of paragraphs: [String], title: String) -> Int {
        paragraphs.reduce(title.count) { $0 + $1.count }
    }
}

/// Cuts cache-missing active chapters off MainActor and hands back pure Sendable page blocks.
enum ReaderOffMainActorPaginator {
    struct ChapterInput: Sendable {
        let chapterIndex: Int
        let title: String
        let paragraphs: [String]
        let contentSignature: String
    }

    struct ChapterOutput: Sendable {
        let chapterIndex: Int
        let contentSignature: String
        let blocks: [ReaderPageBlock]
    }

    static func paginateChapters(
        _ inputs: [ChapterInput],
        context: ReaderChapterPaginationContext
    ) async -> [ChapterOutput] {
        guard !inputs.isEmpty, !Task.isCancelled else { return [] }
        let worker: Task<[ChapterOutput], Never> = Task.detached(priority: .userInitiated) {
            var outputs: [ChapterOutput] = []
            outputs.reserveCapacity(inputs.count)
            for input in inputs {
                guard !Task.isCancelled else { return [] }
                let pages = ReaderChapterPaginator.paginate(
                    chapterIndex: input.chapterIndex,
                    title: input.title,
                    paragraphs: input.paragraphs,
                    context: context
                )
                guard !Task.isCancelled else { return [] }
                outputs.append(
                    ChapterOutput(
                        chapterIndex: input.chapterIndex,
                        contentSignature: input.contentSignature,
                        blocks: pages
                    )
                )
            }
            return outputs
        }
        // Detached work does not inherit cancellation when settings or the
        // active chapter change; stop the old TextKit stack as well as its UI.
        return await withTaskCancellationHandler(operation: {
            await worker.value
        }, onCancel: {
            worker.cancel()
        })
    }
}

/// Decouples overlay/settings drawer visibility from `ReaderView.body` so
/// toggling menus never invalidates the underlying reading surface.
@MainActor
final class ReaderChromeCoordinator: ObservableObject {
    @Published var state: ReaderChromeStateMachine
    @Published var settingsTab: Int = 0

    init(initialOverlayVisible: Bool = false) {
        var initial = ReaderChromeStateMachine()
        if initialOverlayVisible {
            initial.setInitialOverlayVisible(true)
        }
        self.state = initial
    }

    var isOverlayVisible: Bool { state.isOverlayVisible }
    var isSettingsVisible: Bool { state.isSettingsVisible }
}

/// Isolates the 1 Hz sleep timer countdown away from `ReaderView.body`.
@MainActor
final class ReaderSleepTimerCoordinator: ObservableObject {
    @Published var remainingSeconds: Int? = nil

    func badgeText(configuredMinutes: Int) -> String? {
        if configuredMinutes == -1 { return "播完当章" }
        if let rem = remainingSeconds, rem > 0 {
            let mins = rem / 60
            let secs = rem % 60
            return mins > 0 ? String(format: "%d:%02d", mins, secs) : "\(secs)秒"
        }
        if configuredMinutes > 0 { return "\(configuredMinutes)分" }
        return nil
    }
}

/// Plain reference container so `ReaderView` can hold coordinators in `@State`
/// without subscribing `ReaderView.body` to their high-frequency `objectWillChange`.
@MainActor
final class ReaderRuntimeCoordinators {
    let chrome = ReaderChromeCoordinator()
    let sleepTimer = ReaderSleepTimerCoordinator()
    let speech = ReaderSpeechController()
}
