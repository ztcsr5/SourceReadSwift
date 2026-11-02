import Foundation
import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var appState: AppState
    private let audioCoordinator = AudioBookPlaybackCoordinator.shared
    @State private var hasAudio = false
    @AppStorage("settings.accentHex") private var accentHex = "594FDB"
    @AppStorage("settings.secondaryAccentHex") private var secondaryAccentHex = "419BDC"
    @AppStorage("settings.visualTheme") private var visualTheme = AppVisualTheme.classic.rawValue
    @AppStorage("settings.appearanceRevision") private var appearanceRevision = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppMotion private var motion
    @Namespace private var tabSelection
    @State private var selectedTab = 0
    @State private var legacySearchRequest: UUID?
    @State private var showFullAudioPlayer = false
    @ObservedObject private var verificationCoordinator = VerificationCodeCoordinator.shared

    var body: some View {
        let _ = visualTheme
        let _ = appearanceRevision
        let _ = accentHex
        let _ = secondaryAccentHex
        return navigationContent
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !usesNativeTabs, !appState.isTabChromeHidden {
                VStack(spacing: 8) {
                    if hasAudio { miniAudioPlayerBar }
                    customTabBar
                }
            }
        }
        .animation(motion.animation(.navigation), value: appState.isTabChromeHidden)
        .font(.system(.body, design: AppVisualTheme.current.fontDesign))
        .tint(AppTheme.accent)
        .onReceive(audioCoordinator.$currentBook.map { $0 != nil }.removeDuplicates()) { hasAudio = $0 }
        .onChange(of: selectedTab) { _ in dismissKeyboard() }
        .sheet(isPresented: $showFullAudioPlayer) { AudioBookPlayerView() }
        .sheet(item: verificationRequestBinding) { request in
            VerificationCodeSheet(request: request,
                onSubmit: { verificationCoordinator.submit(id: request.id, code: $0) },
                onCancel: { verificationCoordinator.cancel(id: request.id) })
        }
    }

    private var usesNativeTabs: Bool {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) { return true }
        #endif
        return false
    }

    @ViewBuilder private var navigationContent: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            TabView(selection: $selectedTab) {
                nativeTabRoot(BookshelfView()).tabItem { Label("主页", systemImage: "house") }.tag(0)
                nativeTabRoot(DiscoverView(viewModel: appState.discoverViewModel)).tabItem { Label(AppNavigationLabels.findBooks, systemImage: AppNavigationLabels.findBooksSymbol) }.tag(1)
                nativeTabRoot(SettingsView()).tabItem { Label("设置", systemImage: "gearshape") }.tag(2)
            }
            .tabBarMinimizeBehavior(.onScrollDown)
        } else {
            legacyNavigationContent
        }
        #else
        legacyNavigationContent
        #endif
    }

    private func nativeTabRoot<Content: View>(_ content: Content) -> some View {
        content
            .modifier(RootTabChromeVisibilityModifier())
            .safeAreaInset(edge: .bottom, spacing: 0) {
                // An empty native accessory still reserves a glass container on
                // some iOS26 releases. Keep the TabView identity stable instead
                // of conditionally attaching/removing its accessory modifier.
                if hasAudio, !appState.isTabChromeHidden {
                    miniAudioPlayerBar
                }
            }
    }

    private var legacyNavigationContent: some View {
        Group {
            switch selectedTab {
            case 0: BookshelfView()
            case 1: DiscoverView(viewModel: appState.discoverViewModel, searchRequestID: legacySearchRequest)
            default: SettingsView()
            }
        }
    }

    /// Unit tests drive VerificationCodeCoordinator directly.  Presenting the
    /// real sheet in the test host focuses a TextField, and the simulator
    /// keyboard can block the main actor long enough to starve the test's
    /// timeout assertions.  Keep the coordinator contract intact and suppress
    /// only the UI presentation under XCTest.
    private var verificationRequestBinding: Binding<VerificationCodeRequest?> {
        Binding(
            get: {
                isRunningUnitTests ? nil : verificationCoordinator.request
            },
            set: { verificationCoordinator.request = $0 }
        )
    }

    private var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    private var miniAudioPlayerBar: some View {
        RootMiniAudioPlayerBar(showFullAudioPlayer: $showFullAudioPlayer)
    }

    private var customTabBar: some View {
        LegacyTabBar(selection: $selectedTab) {
            legacySearchRequest = UUID()
            selectedTab = 1
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

private struct RootTabPressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .opacity(configuration.isPressed ? 0.78 : 1.0)
            .animation(.interactiveSpring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct RootTabChromeVisibilityModifier: ViewModifier {
    @EnvironmentObject private var appState: AppState

    func body(content: Content) -> some View {
        content.toolbar(appState.isTabChromeHidden ? .hidden : .visible, for: .tabBar)
    }
}

struct HideRootTabBarModifier: ViewModifier {
    @EnvironmentObject private var appState: AppState
    @State private var token = UUID()

    func body(content: Content) -> some View {
        content
            .toolbar(.hidden, for: .tabBar)
            .onAppear {
                appState.acquireTabChromeHidden(owner: token)
            }
            .onDisappear {
                appState.releaseTabChromeHidden(owner: token)
            }
    }
}

extension View {
    func hideRootTabBar() -> some View {
        modifier(HideRootTabBarModifier())
    }
}

private struct RootMiniAudioPlayerBar: View {
    @ObservedObject private var audioCoordinator = AudioBookPlaybackCoordinator.shared
    @Binding var showFullAudioPlayer: Bool
    var body: some View {
        Button {
            showFullAudioPlayer = true
        } label: {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    AsyncBookCover(urlString: audioCoordinator.currentBook?.coverUrl, width: 38, height: 48)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(audioCoordinator.currentBook?.name ?? "有声书播放中")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(audioCoordinator.currentChapter?.title ?? "正在缓冲音频...")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        audioCoordinator.togglePlayPause()
                    } label: {
                        Image(systemName: audioCoordinator.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(AppTheme.accent)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)

                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        audioCoordinator.stop()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.top, 7)
                .padding(.bottom, 5)

                // Track Progress Line
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.15))
                        Capsule()
                            .fill(AppTheme.accent)
                            .frame(width: max(0, min(geo.size.width * CGFloat(audioCoordinator.progress), geo.size.width)))
                    }
                }
                .frame(height: 2.5)
                .padding(.horizontal, 14)
                .padding(.bottom, 4)
            }
            .glassPanel(cornerRadius: 18, material: .ultraThinMaterial, strokeOpacity: 0.10, shadowOpacity: 0.14)
            .padding(.horizontal, 12)
        }
        .buttonStyle(.plain)
    }

}
