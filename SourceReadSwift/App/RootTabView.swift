import Foundation
import SwiftUI
import UIKit

struct RootTabView: View {
    @EnvironmentObject private var appState: AppState
    private let audioCoordinator = AudioBookPlaybackCoordinator.shared
    @State private var hasAudio = false
    @AppStorage("settings.accentHex") private var accentHex = "594FDB"
    @AppStorage("settings.secondaryAccentHex") private var secondaryAccentHex = "419BDC"
    @AppStorage(AppVisualTheme.selectionKey) private var visualTheme = AppVisualTheme.initialSelection.rawValue
    @AppStorage("settings.appearanceRevision") private var appearanceRevision = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppMotion private var motion
    @Namespace private var tabSelection
    @State private var selectedTab = 0
    @State private var legacySearchRequest: UUID?
    @State private var shouldFocusRequestedSearch = true
    @State private var showFullAudioPlayer = false
    @State private var showsGlobalSearch = false
    @ObservedObject private var verificationCoordinator = VerificationCodeCoordinator.shared

    var body: some View {
        let _ = visualTheme
        let _ = appearanceRevision
        let _ = accentHex
        let _ = secondaryAccentHex
        return navigationContent
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppRefreshRateKeeperView())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !appState.isTabChromeHidden {
                VStack(spacing: 8) {
                    if hasAudio { miniAudioPlayerBar }
                    if !usesNativeTabs { customTabBar }
                }
                .animation(motion.animation(.navigation), value: appState.isTabChromeHidden)
            }
        }
        .font(.system(.body, design: AppVisualTheme.current.fontDesign))
        .tint(AppTheme.accent)
        .onReceive(audioCoordinator.$currentBook.map { $0 != nil }.removeDuplicates()) { hasAudio = $0 }
        .onChange(of: selectedTab) { _ in dismissKeyboard() }
        .sheet(isPresented: $showFullAudioPlayer) { AudioBookPlayerView() }
        .sheet(isPresented: $showsGlobalSearch) {
            GlobalSearchView(bookshelf: appState.bookshelfStore, sources: appState.sourceStore) { keyword in
                appState.discoverViewModel.keyword = keyword
                appState.discoverViewModel.startSearch()
                showsGlobalSearch = false
                shouldFocusRequestedSearch = false
                legacySearchRequest = UUID()
                selectedTab = 1
            }
        }
        .sheet(item: verificationRequestBinding) { request in
            VerificationCodeSheet(request: request,
                onSubmit: { verificationCoordinator.submit(id: request.id, code: $0) },
                onCancel: { verificationCoordinator.cancel(id: request.id) })
        }
    }

    /// iOS 26 起交还系统 TabView：只有系统栏带真正的 Liquid Glass、点击动效与滚动边缘效果。
    /// 26 以下继续用自绘栏，避免出现无玻璃的纯色条。
    private var usesNativeTabs: Bool {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) { return true }
        #endif
        return false
    }

    @ViewBuilder private var navigationContent: some View {
        if #available(iOS 26.0, *) {
            nativeTabContent
        } else {
            legacyNavigationContent
        }
    }

    /// 原生路径：三个常规 tab + 末尾的 .search 角色 tab。
    /// .search 角色由系统渲染成导航栏最右端的独立搜索按钮（Liquid Glass 自带玻璃与动效）。
    @available(iOS 18.0, *)
    private var nativeTabContent: some View {
        TabView(selection: $selectedTab) {
            Tab("主页", systemImage: "house", value: 0) {
                BookshelfView(onRequestGlobalSearch: { selectedTab = 3 })
            }
            Tab(AppNavigationLabels.findBooks,
                systemImage: AppNavigationLabels.findBooksSymbol, value: 1) {
                DiscoverView(viewModel: appState.discoverViewModel, searchRequestID: legacySearchRequest,
                             shouldFocusRequestedSearch: shouldFocusRequestedSearch)
            }
            Tab("设置", systemImage: "gearshape", value: 2) {
                SettingsView()
            }
            Tab("全网搜书", systemImage: "magnifyingglass", value: 3, role: .search) {
                GlobalSearchView(bookshelf: appState.bookshelfStore, sources: appState.sourceStore) { keyword in
                    appState.discoverViewModel.keyword = keyword
                    appState.discoverViewModel.startSearch()
                    shouldFocusRequestedSearch = false
                    legacySearchRequest = UUID()
                    selectedTab = 1
                }
            }
        }
    }

    private var legacyNavigationContent: some View {
        // Retain each navigation stack while the custom bar changes selection.
        TabView(selection: $selectedTab) {
            BookshelfView(onRequestGlobalSearch: { showsGlobalSearch = true })
                .modifier(RootTabChromeVisibilityModifier())
                .tabItem { Label("主页", systemImage: "house") }.tag(0)
            DiscoverView(viewModel: appState.discoverViewModel, searchRequestID: legacySearchRequest,
                         shouldFocusRequestedSearch: shouldFocusRequestedSearch)
                .modifier(RootTabChromeVisibilityModifier())
                .tabItem { Label(AppNavigationLabels.findBooks, systemImage: AppNavigationLabels.findBooksSymbol) }.tag(1)
            SettingsView()
                .modifier(RootTabChromeVisibilityModifier())
                .tabItem { Label("设置", systemImage: "gearshape") }.tag(2)
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
            showsGlobalSearch = true
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
    func body(content: Content) -> some View {
        // RootTabView owns the sole visible bar. Reader ownership controls that
        // inset, never the hidden UITabBar retained for navigation stacks.
        content.toolbar(.hidden, for: .tabBar)
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
