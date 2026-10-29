import SwiftUI

@main
struct SourceReadSwiftApp: App {
    @StateObject private var appState = AppState()
    @AppStorage("settings.themeMode") private var themeModeRawValue = ThemeMode.system.rawValue
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var systemColorScheme

    init() {
        UIImpactFeedbackGenerator.initializeHapticsControl()
        UINotificationFeedbackGenerator.initializeNotificationHapticsControl()
    }

    /// 主题选择的颜色方案；「跟随系统」时才回落到系统值。
    private var resolvedAppColorScheme: ColorScheme {
        (ThemeMode(rawValue: themeModeRawValue) ?? .system).colorScheme ?? systemColorScheme
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(appState)
                .highRefreshRateSurface()
                .preferredColorScheme(resolvedAppColorScheme)
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
                    guard phase == .active else { return }
                    FrameRateCoordinator.apply()
                }
        }
    }
}
