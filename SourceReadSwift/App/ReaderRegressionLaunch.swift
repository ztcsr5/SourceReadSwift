import Foundation

/// Debug UI tests use real shelf/reader flows with an isolated local-book store.
@MainActor enum ReaderRegressionLaunch {
    static func makeAppState() -> AppState {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--floating-desk-regression") {
            return FloatingDeskRegressionLaunch.makeAppState()
        }
        if ProcessInfo.processInfo.arguments.contains("--reader-settings-regression") {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("reader-ui-" + UUID().uuidString)
            let shelf = BookshelfStore(persistence: BookshelfPersistence(rootURL: root),
                groupPersistence: BookshelfGroupPersistence(rootURL: root))
            shelf.addLocalTextBook(OnboardingClassicBook.makeWelcomeBook())
            return AppState(sourceStore: SourceStore(persistence: SourcePersistence(rootURL: root)), bookshelfStore: shelf)
        }
        #endif
        return AppState()
    }
}
