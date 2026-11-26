import SwiftUI

@main
struct SourceReadSwiftApp: App {
    @StateObject private var launchState = AppLaunchState()
    @AppStorage("settings.themeMode") private var themeModeRawValue = ThemeMode.system.rawValue
    @Environment(\.scenePhase) private var scenePhase

    init() {
        SourceDeviceIdentity.captureAtLaunch()
        UserDefaults.standard.set(false, forKey: AppRefreshRateKeeper.diagnosticDefaultsKey)
        AppVisualTheme.bootstrapSelection(in: .standard)
        UIImpactFeedbackGenerator.initializeHapticsControl()
        UINotificationFeedbackGenerator.initializeNotificationHapticsControl()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let appState = launchState.appState {
                    libraryContent(appState)
                } else {
                    AppLibraryLoadingView()
                }
            }
                .highRefreshRateSurface()
                .modifier(AppColorSchemePreference(mode: ThemeMode(rawValue: themeModeRawValue) ?? .system))
                .onOpenURL { url in
                    Task {
                        let appState = await launchState.load()
                        await appState.awaitSourcesReady()
                        guard !Task.isCancelled else { return }
                        appState.importSharedDocument(url)
                    }
                }
                .task { _ = await launchState.load() }
                .onAppear {
                    FrameRateCoordinator.apply()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIScene.didActivateNotification)) { notification in
                    FrameRateCoordinator.apply(to: notification.object as? UIScene)
                }
                .onChange(of: scenePhase) { phase in
                    if phase != .active, let appState = launchState.appState {
                        appState.finishReadingWritesInBackground()
                        if phase == .background, !isRunningUnitTests {
                            let lease = ReadingWriteBackgroundLease()
                            Task { @MainActor in
                                defer { lease.end() }
                                await appState.awaitSourcesReady()
                                guard !Task.isCancelled, UIApplication.shared.applicationState == .background else { return }
                                WebDAVAutoSyncCoordinator.shared.performAutoUploadIfNeeded(appState: appState)
                            }
                        }
                    }
                    guard phase == .active else { return }
                    FrameRateCoordinator.apply()
                }
        }
    }

    private func libraryContent(_ appState: AppState) -> some View {
        ReaderNavigationHost()
            .ignoresSafeArea()
            .environmentObject(appState)
            .task(id: scenePhase, priority: .utility) {
                guard scenePhase == .active, !isRunningUnitTests else { return }
                // Commit the returning frame before optional credential and network work.
                do { try await Task.sleep(nanoseconds: 400_000_000) } catch { return }
                await appState.awaitSourcesReady()
                guard !Task.isCancelled else { return }
                WebDAVAutoSyncCoordinator.shared.checkForNewerRemoteBackupIfNeeded()
            }
            .task(priority: .utility) {
                guard !isRunningUnitTests else { return }
                // Let the first shelf frame commit before starting source work.
                do { try await Task.sleep(nanoseconds: 1_200_000_000) } catch { return }
                await appState.awaitSourcesReady()
                guard !Task.isCancelled else { return }
                await appState.bookshelfChapterRefresh.refreshOnLaunch()
            }
    }

    private var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }
}

struct AppColorSchemePreference: ViewModifier {
    let mode: ThemeMode

    func body(content: Content) -> some View {
        // nil relinquishes the presentation override. Capturing the App's
        // environment and setting it back as a preference freezes system mode.
        content.preferredColorScheme(mode.colorScheme)
    }
}
