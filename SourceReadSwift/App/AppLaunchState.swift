import SwiftUI

/// Coalesces window appearance and incoming-document requests into one library load.
@MainActor
final class AppLaunchState: ObservableObject {
    @Published private(set) var appState: AppState?
    private var pendingLoad: Task<AppState, Never>?
    private let loadLibrary: @MainActor () async -> AppState

    init(loadLibrary: @escaping @MainActor () async -> AppState = { await ReaderRegressionLaunch.loadAppState(stagedSources: true) }) {
        self.loadLibrary = loadLibrary
    }

    func load() async -> AppState {
        if let appState { return appState }
        let request = pendingLoad ?? Task { await loadLibrary() }
        pendingLoad = request
        let loaded = await request.value
        if appState == nil { appState = loaded }
        pendingLoad = nil
        return loaded
    }
}

struct AppLibraryLoadingView: View {
    var body: some View {
        ZStack {
            AppPagePaper(theme: AppVisualTheme.current).ignoresSafeArea()
            Text("纸间").font(.system(size: 32, weight: .semibold, design: .serif))
        }
        .accessibilityIdentifier("launch.loading")
    }
}
