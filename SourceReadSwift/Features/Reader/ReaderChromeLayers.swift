import SwiftUI

/// Isolated scroll chrome backdrop, header, footer, and status strip.
/// Observing `ReaderChromeCoordinator` and `ReaderSpeechController` here keeps
/// overlay/TTS toggles from invalidating `ReaderView.body` or scrolling surfaces.
struct ReaderScrollChromeLayer<Header: View, Footer: View, StatusBanner: View>: View {
    @ObservedObject var chrome: ReaderChromeCoordinator
    @ObservedObject var speechController: ReaderSpeechController
    let showSystemStatusBar: Bool
    let topSafeInset: CGFloat
    let statusBarBackground: Color
    let isScrollMode: Bool
    let showsFooterPreference: Bool
    let autoScrollEnabled: Bool
    let hasScrollStatus: Bool
    let navigationAnimation: Animation?
    let makeHeader: (_ showsLabels: Bool) -> Header
    let makeFooter: () -> Footer
    let makeStatusBanner: () -> StatusBanner

    var body: some View {
        ZStack {
            statusBarBackground
                .frame(height: topSafeInset)
                .frame(maxHeight: .infinity, alignment: .top)
                .opacity(chrome.isOverlayVisible || showSystemStatusBar ? 1 : 0)
                .animation(nil, value: chrome.isOverlayVisible)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .zIndex(1)

            if isScrollMode {
                makeHeader(!chrome.isOverlayVisible)
                    .zIndex(1)
            }

            if isScrollMode,
               !chrome.isOverlayVisible,
               !speechController.isSpeaking,
               !autoScrollEnabled,
               showsFooterPreference {
                makeFooter()
                    .ignoresSafeArea(.container, edges: .bottom)
                    .transition(.opacity)
                    .zIndex(1)
            }

            if !chrome.isOverlayVisible, isScrollMode, hasScrollStatus {
                makeStatusBanner()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(2)
            }
        }
        .animation(navigationAnimation, value: chrome.isOverlayVisible)
    }
}

/// Isolated interactive HUD overlays (tap zones, reader toolbar, selection finish,
/// TTS error banner, floating speech/scroll capsules, goal toast, and system bars).
struct ReaderInteractiveHUDLayer<
    TapZones: View,
    Overlay: View,
    SpeechErrorBanner: View,
    SpeechCapsule: View,
    AutoScrollCapsule: View
>: View {
    @ObservedObject var chrome: ReaderChromeCoordinator
    @ObservedObject var speechController: ReaderSpeechController
    @ObservedObject var sleepTimer: ReaderSleepTimerCoordinator
    @ObservedObject var goalCelebration: ReaderGoalCelebrationCoordinator
    @AppStorage("reader.sleepTimerMinutes") private var sleepTimerMinutes: Int = 0

    let navigationIsTransitioning: Bool
    let textSelectionEnabled: Bool
    let topSafeInset: CGFloat
    let autoScrollEnabled: Bool
    let showSystemStatusBar: Bool
    let navigationAnimation: Animation?
    let expansionAnimation: Animation?
    let onCompleteTextSelection: () -> Void
    let makeTapZoneOverlay: () -> TapZones
    let makeOverlay: (_ sleepBadgeText: String?) -> Overlay
    let makeSpeechErrorBanner: (_ message: String) -> SpeechErrorBanner
    let makeSpeechCapsule: (_ sleepBadgeText: String?) -> SpeechCapsule
    let makeAutoScrollCapsule: () -> AutoScrollCapsule

    var body: some View {
        let sleepBadge = sleepTimer.badgeText(configuredMinutes: sleepTimerMinutes)
        ZStack {
            // Keep preference-backed system bar modifiers anchored even when all chrome is hidden.
            Color.clear
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            if chrome.isSettingsVisible && chrome.settingsTab == 2 {
                makeTapZoneOverlay()
                    .allowsHitTesting(false)
            }

            if chrome.isOverlayVisible && !chrome.isSettingsVisible {
                makeOverlay(sleepBadge)
                    .opacity(navigationIsTransitioning ? 0 : 1)
                    .allowsHitTesting(!navigationIsTransitioning)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.98, anchor: .center)),
                            removal: .opacity
                        )
                    )
                    .zIndex(10)
            }

            if textSelectionEnabled && !chrome.isSettingsVisible {
                VStack {
                    HStack {
                        Spacer()
                        Button("完成选择", action: onCompleteTextSelection)
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.borderedProminent)
                    }
                    Spacer()
                }
                .padding(.top, topSafeInset + 8)
                .padding(.trailing, 16)
                .zIndex(11)
            }

            if let speechErrorMessage = speechController.lastErrorMessage {
                makeSpeechErrorBanner(speechErrorMessage)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(4)
            }

            if goalCelebration.isVisible {
                VStack {
                    HStack(spacing: 8) {
                        Text("🎉")
                            .font(.system(size: 16))
                        Text("今日阅读目标达成！已连续阅读 \(goalCelebration.streakDays) 天")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.85))
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                    .padding(.top, topSafeInset + 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    Spacer()
                }
                .zIndex(10)
            }

            if !chrome.isOverlayVisible && speechController.isSpeaking {
                VStack {
                    Spacer()
                    makeSpeechCapsule(sleepBadge)
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .zIndex(5)
            } else if !chrome.isOverlayVisible && autoScrollEnabled {
                VStack {
                    Spacer()
                    makeAutoScrollCapsule()
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .zIndex(5)
            }
        }
        .animation(navigationAnimation, value: chrome.isOverlayVisible)
        .animation(expansionAnimation, value: goalCelebration.isVisible)
        .statusBarHidden(!chrome.isOverlayVisible && !showSystemStatusBar)
        .persistentSystemOverlays(chrome.isOverlayVisible || showSystemStatusBar ? .automatic : .hidden)
    }
}

/// Isolated settings drawer layer so opening/closing settings or switching tabs
/// never re-evaluates `ReaderView.body` or reading content.
struct ReaderSettingsDrawerLayer<SettingsPanel: View>: View {
    @ObservedObject var chrome: ReaderChromeCoordinator
    @ObservedObject var speechController: ReaderSpeechController
    let reducesMotion: Bool
    let expansionAnimation: Animation?
    let viewportHeight: CGFloat
    let footerSafeInset: CGFloat
    let onDismiss: () -> Void
    let makeSettingsPanel: () -> SettingsPanel

    var body: some View {
        let _ = speechController.isSpeaking
        ZStack {
            if chrome.isSettingsVisible {
                Color.clear
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onDismiss)

                makeSettingsPanel()
                    .transition(
                        reducesMotion
                            ? .opacity
                            : .offset(
                                y: ReaderSettingsLayoutPolicy.maxPanelHeight(
                                    viewportHeight: viewportHeight,
                                    bottomInset: footerSafeInset
                                ) + footerSafeInset + 16
                            )
                    )
            }
        }
        .allowsHitTesting(chrome.isSettingsVisible)
        .animation(expansionAnimation, value: chrome.isSettingsVisible)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: chrome.settingsTab)
    }
}

/// Keeps native UIKit lifecycle bridges, edge-swipe pop locks, and hardware volume
/// key interception synchronized with `ReaderChromeCoordinator` without pulling
/// menu or TTS state back into `ReaderView.body`.
struct ReaderSystemBridgesLayer: View {
    @ObservedObject var chrome: ReaderChromeCoordinator
    @ObservedObject var speechController: ReaderSpeechController
    let nativeSession: ReaderNavigationSession?
    let readerUsesBookReturn: Bool
    let isScrollMode: Bool
    let showChapterList: Bool
    let temporaryCoverPresented: Bool
    let textSelectionEnabled: Bool
    let showBookmarks: Bool
    let showBookDetailSheet: Bool
    let showContentFilter: Bool
    let hasModalItemPresented: Bool
    let navigationIsTransitioning: Bool
    let activeScrollTarget: Int?
    let volumeKeyPageTurn: Bool
    let autoScrollEnabled: Bool
    let isReaderVisible: Bool
    let readerSessionEnded: Bool
    let onExit: () -> Void
    let onPark: () -> Void
    let onResume: () -> Void
    let onSelectChapter: (Int) -> Void
    let onRequestExit: () -> Void
    let onVolumePageTurn: (Int) -> Void

    private var allowsNativeBookReturn: Bool {
        readerUsesBookReturn && ReaderSystemReturnPolicy.isEnabled(
            isScroll: isScrollMode,
            menuVisible: chrome.isOverlayVisible,
            blocked: chrome.isSettingsVisible || showChapterList || temporaryCoverPresented,
            selectionEnabled: textSelectionEnabled
        )
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .background {
                if nativeSession == nil {
                    ReaderNavigationPopLock(allowSystemReturn: allowsNativeBookReturn)
                }
            }
            .background(
                ReaderNativeLifecycleBridge(
                    session: nativeSession,
                    allowsReturn: allowsNativeBookReturn,
                    onExit: onExit,
                    onPark: onPark,
                    onResume: onResume,
                    onSelectChapter: onSelectChapter,
                    renderedMenu: chrome.isOverlayVisible,
                    transitioning: navigationIsTransitioning,
                    scrollTarget: activeScrollTarget
                )
            )
            .background {
                #if targetEnvironment(simulator)
                if nativeSession == nil {
                    ReaderExitSwipeBridge(
                        enabled: allowsNativeBookReturn,
                        onExit: onRequestExit,
                        prefersSystemReturn: true
                    )
                }
                #endif
            }
            .background {
                if volumeKeyPageTurn {
                    ReaderVolumeKeyListener(
                        isActive: ReaderVolumeTurnPolicy.shouldIntercept(
                            isEnabled: volumeKeyPageTurn,
                            isSpeaking: speechController.isSpeaking || autoScrollEnabled,
                            isSheetPresented: chrome.isOverlayVisible
                                || chrome.isSettingsVisible
                                || showChapterList
                                || showBookmarks
                                || showBookDetailSheet
                                || showContentFilter
                                || hasModalItemPresented,
                            isActive: isReaderVisible && !readerSessionEnded
                        ),
                        onPageTurn: onVolumePageTurn
                    )
                }
            }
            .navigationBarBackButtonHidden(!allowsNativeBookReturn)
    }
}

/// Forwards active TTS paragraph and sentence range ticks only while speech
/// is active so idle reading never invalidates `ReaderView.body`.
struct ReaderSpeechFollowObserver: View {
    @ObservedObject var speechController: ReaderSpeechController
    let isScrollMode: Bool
    let onScrollParagraphChanged: (Int) -> Void
    let onPagedParagraphChanged: (Int) -> Void
    let onPagedRangeChanged: (NSRange?) -> Void
    let onSpeechHighlightTokenChanged: (String) -> Void

    private var highlightToken: String {
        guard speechController.isSpeaking || speechController.currentParagraphIndex >= 0 else {
            return ""
        }
        let range = speechController.currentSpeechRange
        let loc = range?.location ?? NSNotFound
        let len = range?.length ?? 0
        return "\(speechController.isSpeaking ? 1 : 0):\(speechController.currentParagraphIndex):\(loc):\(len)"
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .onChange(of: speechController.currentParagraphIndex) { target in
                if isScrollMode {
                    onScrollParagraphChanged(target)
                } else {
                    onPagedParagraphChanged(target)
                }
            }
            .onChange(of: speechController.currentSpeechRange) { range in
                if !isScrollMode {
                    onPagedRangeChanged(range)
                }
            }
            .onChange(of: highlightToken) { token in
                onSpeechHighlightTokenChanged(token)
            }
    }
}
