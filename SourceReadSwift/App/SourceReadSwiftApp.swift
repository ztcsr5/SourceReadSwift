import SwiftUI

@main
struct SourceReadSwiftApp: App {
    @StateObject private var appState = ReaderRegressionLaunch.makeAppState()
    @AppStorage("settings.themeMode") private var themeModeRawValue = ThemeMode.system.rawValue
    @Environment(\.scenePhase) private var scenePhase

    init() {
        UserDefaults.standard.set(false, forKey: AppRefreshRateKeeper.diagnosticDefaultsKey)
        AppVisualTheme.bootstrapSelection(in: .standard)
        UIImpactFeedbackGenerator.initializeHapticsControl()
        UINotificationFeedbackGenerator.initializeNotificationHapticsControl()
    }

    var body: some Scene {
        WindowGroup {
            ReaderNavigationHost()
                .ignoresSafeArea()
                .environmentObject(appState)
                .highRefreshRateSurface()
                .modifier(AppColorSchemePreference(mode: ThemeMode(rawValue: themeModeRawValue) ?? .system))
                .onOpenURL { url in
                    appState.importSharedDocument(url)
                }
                .onAppear {
                    FrameRateCoordinator.apply()
                    if !isRunningUnitTests {
                        WebDAVAutoSyncCoordinator.shared.checkForNewerRemoteBackupIfNeeded()
                    }
                }
                .task(priority: .utility) {
                    guard !isRunningUnitTests else { return }
                    // Let the first shelf frame commit before starting source work.
                    do { try await Task.sleep(nanoseconds: 1_200_000_000) } catch { return }
                    await appState.bookshelfChapterRefresh.refreshOnLaunch()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIScene.didActivateNotification)) { notification in
                    FrameRateCoordinator.apply(to: notification.object as? UIScene)
                }
                .onChange(of: scenePhase) { phase in
                    if phase != .active {
                        appState.finishReadingWritesInBackground()
                        if !isRunningUnitTests {
                            WebDAVAutoSyncCoordinator.shared.performAutoUploadIfNeeded(appState: appState)
                        }
                    }
                    guard phase == .active else { return }
                    FrameRateCoordinator.apply()
                    if !isRunningUnitTests {
                        WebDAVAutoSyncCoordinator.shared.checkForNewerRemoteBackupIfNeeded()
                    }
                }
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
