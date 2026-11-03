import SwiftUI

@main
struct SourceReadSwiftApp: App {
    @StateObject private var appState = ReaderRegressionLaunch.makeAppState()
    @AppStorage("settings.themeMode") private var themeModeRawValue = ThemeMode.system.rawValue
    @Environment(\.scenePhase) private var scenePhase

    init() {
        UIImpactFeedbackGenerator.initializeHapticsControl()
        UINotificationFeedbackGenerator.initializeNotificationHapticsControl()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(appState)
                .highRefreshRateSurface()
                .modifier(AppColorSchemePreference(mode: ThemeMode(rawValue: themeModeRawValue) ?? .system))
                .onOpenURL { url in
                    appState.importSharedDocument(url)
                }
                .onAppear {
                    FrameRateCoordinator.apply()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIScene.didActivateNotification)) { notification in
                    FrameRateCoordinator.apply(to: notification.object as? UIScene)
                }
                .onChange(of: scenePhase) { phase in
                    if phase != .active { appState.finishReadingWritesInBackground() }
                    guard phase == .active else { return }
                    FrameRateCoordinator.apply()
                }
        }
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
