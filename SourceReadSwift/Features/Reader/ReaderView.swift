import AVFoundation
import MediaPlayer
import PhotosUI
import SwiftUI
import UIKit

struct ContinuousAppendedSection: Equatable, Identifiable {
    var id: Int { chapterIndex }
    let chapterIndex: Int
    let title: String
    let paragraphs: [String]
}

struct ReaderView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    let bookID: String
    let content: ChapterContent
    let chapterIndex: Int
    let totalChapters: Int?
    var chapters: [BookChapter] = []
    /// Optional EPUB3/NCX entries. Multiple entries may target different
    /// fragments inside one normalized chapter.
    var navigationEntries: [LocalTextNavigationEntry] = []
    /// Explicit initial position used for fragment navigation. Stored reading
    /// progress remains the fallback for ordinary chapter resumes.
    var initialParagraphIndex: Int? = nil
    var statusMessage: String?
    var extraToolbarActions: () -> AnyView = { AnyView(EmptyView()) }
    var onRequestSourceSwitch: (() -> Void)?
    /// Opens the owning book detail screen from the reader's overflow menu.
    /// When omitted, the reader simply closes so the caller's previous screen
    /// remains the fallback detail context.
    var onRequestBookDetail: (() -> Void)?
    var onSelectChapter: ((BookChapter) -> Void)?
    var onSelectChapterWithPosition: ((BookChapter, Int?) -> Void)? = nil
    var onSelectNavigationEntry: ((LocalTextNavigationEntry) -> Void)?
    var onRefreshChapter: (() -> Void)?
    var onCacheNextChapters: (() -> Void)?
    /// Called after speech reaches the end of the current chapter. The owning
    /// screen can swap in the next chapter without coupling the speech engine
    /// to navigation or networking.
    var onSpeechFinished: (() -> Void)? = nil
    /// Used by the chapter owner to continue speech after an automatic
    /// chapter handoff. It is intentionally one-shot and consumed on appear.
    var autoplaySpeechOnAppear: Bool = false
    var onSpeechAutoplayConsumed: (() -> Void)? = nil
    var autoplayAutoScrollOnAppear: Bool = false
    var onAutoScrollAutoplayConsumed: (() -> Void)? = nil
    var onAutoScrollFinished: (() -> Void)? = nil
    /// Keeps the reader controls visible when navigation originated in the
    /// chapter list. A fresh chapter view otherwise starts with the chrome
    /// hidden and can be mistaken for the root tab UI.
    var initialOverlayVisible: Bool = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var chromeState = ReaderChromeStateMachine()
    @State private var tabChromeOwner = UUID()
    @State private var showChapterList = false
    @State private var showBookmarks = false
    @State private var showBookDetailSheet = false
    @State private var showPayActionConfirmation = false
    @State private var payActionResultMessage = ""
    @State private var showPayActionResult = false
    @State private var isPerformingPayAction = false
    @State private var quoteCardBookmark: ReaderBookmark? = nil
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var backgroundWallpaperRevision = UUID()
    @State private var settingsTab = 0

    private var showOverlay: Bool { chromeState.isOverlayVisible }
    private var showSettings: Bool { chromeState.isSettingsVisible }
    @State private var tocTab = 0
    @State private var tocQuery = ""
    @State private var debouncedTocQuery = ""
    @State private var selectedIllustrationURL: URL? = nil
    @State private var imageHeaderCache: [String: String] = [:]
    @State private var tocReversed = false
    @State private var autoScrollEnabled = false
    @State private var autoScrollAnchorTarget = 0
    @State private var autoScrollAwaitingFirstTick = false
    /// Scroll mode targets paragraphs; paged/cover modes target pages.
    /// Keep these indices separate so a mode switch never interprets a page
    /// number as a paragraph (or vice versa).
    @State private var scrollParagraphTarget = 0
    @State private var pagedPageIndex = 0
    @State private var autoScrollTask: Task<Void, Never>?
    @State private var sleepTimerTask: Task<Void, Never>?
    @State private var positionPersistTask: Task<Void, Never>?
    @State private var pageLayoutTask: Task<Void, Never>?
    @State private var paragraphJumpRequest: ParagraphJumpRequest?
    @State private var pagedBlocksCache: [ReaderPageBlock] = []
    @State private var pagedBlocksCacheKey = ""
    /// Page-to-paragraph mapping is immutable between layout-cache revisions.
    /// Keep it in state instead of rebuilding an array with `compactMap` every
    /// time SwiftUI reevaluates the reader body or a speech callback arrives.
    @State private var positionMappingCache = ReaderPositionMapping(paragraphCount: 0)
    /// The reader may live in a split view or Stage Manager window. Keep the
    /// actual container size instead of using UIScreen.main, which describes
    /// the physical display and can be stale for the current scene.
    @State private var viewportSize: CGSize = .zero
    @State private var sessionStartedAt = Date()
    @State private var previousIdleTimerDisabled = false
    @State private var visibleParagraphIndex = 0
    @State private var readerContentFingerprint = ""
    @State private var appendedSections: [ContinuousAppendedSection] = []
    @State private var isAppendingNextChapter = false
    @State private var speechPausedForScene = false
    @State private var autoScrollPausedForScene = false
    @State private var coverDragTranslation: CGFloat = 0
    @State private var coverIsAnimating = false
    @State private var scrollJumpGeneration = 0
    @State private var chapterSliderTarget: Double? = nil
    @State private var pageStepDirection: Int = 0
    @State private var pageStepGeneration: Int = 0
    @State private var brightnessBeforeReader: CGFloat? = nil
    @StateObject private var playbackCoordinator = ReaderPlaybackCoordinator()
    @StateObject private var speechController = ReaderSpeechController()
    @AppStorage("reader.fontFamily") private var fontFamilyRawValue: String = ReaderFontFamily.system.rawValue
    @AppStorage("reader.fontSize") private var fontSize: Double = ReaderTypographyDefaults.fontSize
    @AppStorage("reader.lineSpacing") private var lineSpacing: Double = ReaderTypographyDefaults.lineSpacing
    @AppStorage("reader.pagePadding") private var pagePadding: Double = ReaderTypographyDefaults.pagePadding
    @AppStorage("reader.letterSpacing") private var letterSpacing: Double = ReaderTypographyDefaults.letterSpacing
    @AppStorage("reader.paragraphSpacing") private var paragraphSpacing: Double = ReaderTypographyDefaults.paragraphSpacing
    @AppStorage("reader.paragraphIndent") private var paragraphIndent: Double = ReaderTypographyDefaults.paragraphIndent
    @AppStorage("reader.titleSpacing") private var titleSpacing: Double = ReaderTypographyDefaults.titleSpacing
    @AppStorage("reader.footerHeight") private var footerHeight: Double = ReaderTypographyDefaults.footerHeight
    @AppStorage("reader.ttsRate") private var ttsRate: Double = 0.52
    @AppStorage("reader.ttsEngine") private var ttsEngineRawValue: String = TTSEngineKind.local.rawValue
    @AppStorage("reader.httpTTSVoiceID") private var httpTTSVoiceID: Int = HttpTTSVoice.defaultVoiceID
    @AppStorage("reader.autoScrollDelay") private var autoScrollDelay: Double = 2.0
    @AppStorage("reader.sleepTimerMinutes") private var sleepTimerMinutes: Int = 0
    @AppStorage("reader.background") private var backgroundRawValue: String = ReaderBackground.paper.rawValue
    @State private var isPerBookOverride: Bool = false
    @AppStorage("reader.mode") private var readerModeRawValue: String = ReaderMode.scroll.rawValue
    @AppStorage("reader.tapZones") private var tapZonesRawValue: String = ReaderTapAction.defaultRawValue
    @AppStorage("reader.keepScreenAwake") private var keepScreenAwake = true
    /// -1 follows the system; 0.05...1 overrides while the reader is open.
    @AppStorage("reader.brightness") private var readerBrightness: Double = -1
    @AppStorage("reader.preloadChapterCount") private var preloadChapterCount = ReaderPreloadPolicy.defaultCount
    @AppStorage("reader.textSelectionEnabled") private var textSelectionEnabled = false
    @AppStorage("reading.dailyGoalMinutes") private var dailyGoalMinutes: Int = 30
    @AppStorage("reading.lastGoalCelebratedDate") private var lastGoalCelebratedDate: String = ""
    @State private var showGoalCelebrationToast = false
    @State private var streakDaysCount = 1

    private var fontFamily: ReaderFontFamily {
        ReaderFontFamily(rawValue: fontFamilyRawValue) ?? .system
    }

    private var background: ReaderBackground {
        ReaderBackground(rawValue: backgroundRawValue) ?? .paper
    }

    private var readerMode: ReaderMode {
        ReaderMode(rawValue: readerModeRawValue) ?? .scroll
    }

    private var tapZoneActions: [ReaderTapAction] {
        ReaderTapAction.decode(rawValue: tapZonesRawValue)
    }

    private var bookmarks: [ReaderBookmark] {
        appState.bookshelfStore.book(id: bookID)?.bookmarks ?? []
    }

    private var sortedBookmarks: [ReaderBookmark] {
        bookmarks.sorted { lhs, rhs in
            if lhs.chapterIndex != rhs.chapterIndex {
                return lhs.chapterIndex < rhs.chapterIndex
            }
            if lhs.paragraphIndex != rhs.paragraphIndex {
                return (lhs.paragraphIndex ?? -1) < (rhs.paragraphIndex ?? -1)
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private var currentChapterBookmarkCount: Int {
        bookmarks.filter { $0.chapterIndex == chapterIndex }.count
    }

    private var isCurrentChapterBookmarked: Bool {
        appState.bookshelfStore.isBookmarked(
            bookID: bookID,
            chapterIndex: chapterIndex,
            paragraphIndex: currentBookmarkParagraphIndex
        )
    }

    private var currentBookmarkParagraphIndex: Int {
        currentParagraphIndexForPersistence()
    }

    private var currentDisplayChapterIndex: Int {
        if readerMode == .scroll && !appendedSections.isEmpty {
            return resolvedReadingPosition(forFlatIndex: visibleParagraphIndex).chapterIndex
        }
        return chapterIndex
    }

    private var currentDisplayChapterTitle: String {
        if readerMode == .scroll && !appendedSections.isEmpty {
            return resolvedReadingPosition(forFlatIndex: visibleParagraphIndex).chapterTitle
        }
        return content.title
    }

    private var progressTitle: String {
        var parts: [String] = []
        let displayIndex = currentDisplayChapterIndex
        if let totalChapters, totalChapters > 0 {
            let percentage = Int((Double(displayIndex + 1) / Double(totalChapters) * 100).rounded())
            parts.append("第 \(displayIndex + 1) / \(totalChapters) 章")
            parts.append("\(percentage)%")
        } else {
            parts.append("第 \(displayIndex + 1) 章")
        }
        if readerMode != .scroll {
            let pageCount = max(pagedBlocks.count, 1)
            let page = min(max(pagedPageIndex + 1, 1), pageCount)
            parts.append("页 \(page)/\(pageCount)")
        }
        return parts.joined(separator: " · ")
    }

    private var sleepTimerBadgeText: String? {
        if sleepTimerMinutes == -1 { return "播完当章" }
        if sleepTimerMinutes > 0 { return "\(sleepTimerMinutes)分" }
        return nil
    }

    private var maximumReaderTarget: Int {
        switch readerMode {
        case .scroll:
            return positionMapping.maximumParagraphIndex
        case .pageTurn, .cover, .pageCurl:
            return positionMapping.maximumPageIndex
        }
    }

    private var filteredChapters: [BookChapter] {
        let query = debouncedTocQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var result = chapters.filter { chapter in
            query.isEmpty
                || chapter.title.lowercased().contains(query)
                || "\(chapter.index + 1)".contains(query)
        }
        if tocReversed {
            result.reverse()
        }
        return result
    }

    private var filteredNavigationEntries: [LocalTextNavigationEntry] {
        let query = debouncedTocQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var result = navigationEntries.filter { entry in
            query.isEmpty
                || entry.title.lowercased().contains(query)
                || entry.chapterIndex.map { String($0 + 1).contains(query) } == true
        }
        if tocReversed { result.reverse() }
        return result
    }

    private var pagedBlocks: [ReaderPageBlock] {
        // Keep the last page model while a settings change is being committed.
        // SwiftUI may evaluate `body` several times before `.onChange` runs;
        // rebuilding a long chapter in each pass was a major source of jank.
        if !pagedBlocksCache.isEmpty {
            return pagedBlocksCache
        }
        // A valid empty cache is still a cache (empty chapters are legal).
        if pagedBlocksCacheKey == readerPageCacheKey { return pagedBlocksCache }
        // Before `onAppear` seeds the cache, render a cheap placeholder rather
        // than laying out every paragraph once per SwiftUI body evaluation.
        return [ReaderPageBlock(id: 0, includesTitle: true, paragraphs: [])]
    }

    private var effectiveViewportSize: CGSize {
        guard viewportSize.width > 1, viewportSize.height > 1 else {
            return ReaderPerformancePolicy.defaultViewportSize
        }
        return viewportSize
    }

    /// Text column used by illustrations in both the SwiftUI paged surface and
    /// the TextKit scroll surface. Derived from the measured container instead
    /// of UIScreen so split view / Stage Manager keep the same geometry.
    private var illustrationColumnWidth: CGFloat {
        max(effectiveViewportSize.width - CGFloat(pagePadding * 2), 200)
    }

    private var readerPageCacheKey: String {
        // Pagination depends on the viewport. Include the actual container
        // bounds so rotation, split-view and Stage Manager resize invalidate
        // the model instead of showing pages calculated for the old width.
        let viewport = effectiveViewportSize
        return [
            readerLayoutKey,
            ReaderPerformancePolicy.viewportCacheKey(viewport),
            content.title,
            String(content.paragraphs.count),
            String(content.paragraphs.first?.hashValue ?? 0),
            String(content.paragraphs.last?.hashValue ?? 0)
        ].joined(separator: "|")
    }

    private var readerLayoutKey: String {
        [
            readerModeRawValue,
            fontFamilyRawValue,
            String(format: "%.1f", fontSize),
            String(format: "%.1f", lineSpacing),
            String(format: "%.1f", pagePadding),
            String(format: "%.1f", letterSpacing),
            String(format: "%.1f", paragraphSpacing),
            String(format: "%.1f", paragraphIndent),
            String(format: "%.1f", titleSpacing),
            String(format: "%.1f", footerHeight)
        ].joined(separator: "|")
    }

    private var positionMapping: ReaderPositionMapping {
        if positionMappingCache.paragraphCount == content.paragraphs.count {
            // A typography gesture may temporarily make the cache key stale;
            // the old mapping is still valid until the debounced page rebuild
            // commits and avoids compactMap work on every slider frame.
            return positionMappingCache
        }
        // A first render may not have a page model yet. Keep a safe fallback
        // for synchronous mode switches during that one transition.
        return ReaderPositionMapping(
            paragraphCount: content.paragraphs.count,
            pageFirstParagraphs: ReaderPositionMapping.pageStarts(
                from: pagedBlocks.map(\.firstParagraphIndex)
            )
        )
    }

    var body: some View {
        ZStack {
            readerBackdrop

            readerContent
            // UIKit owns the long-form scroll layout. Avoid invalidating the
            // whole reader tree for each appearance/highlight update; paged
            // modes still reset when their layout model changes.
            // Keep the identity tied to the committed page cache, not the
            // live slider values. Re-keying the entire paged tree for every
            // typography gesture discards SwiftUI's page views at 120 Hz and
            // defeats the debounce above; the cache key changes once after
            // the gesture settles.
            .id(readerMode == .scroll ? "native-scroll-reader" : (pagedBlocksCacheKey.isEmpty ? "reader-page-placeholder" : pagedBlocksCacheKey))
            .contentShape(Rectangle())
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { value in
                        handleReaderTap(at: value.location)
                    }
            )

            if showSettings && settingsTab == 2 {
                tapZoneOverlay
                    .allowsHitTesting(false)
                }

            if !showOverlay && !speechController.isSpeaking && !autoScrollEnabled {
                readerFooter
                    .transition(.opacity)
                    .zIndex(1)
            }

            if showOverlay {
                readerOverlay
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.98, anchor: .center)),
                            removal: .opacity
                        )
                    )
            }

            if let statusMessage {
                readerStatusBanner(message: statusMessage)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Cloud TTS failures fall back to the system voice. Keep the
            // reason on screen (instead of a transient toast) so a silent
            // keychain/network failure never looks like the app ignored the
            // user's engine selection.
            if let speechErrorMessage = speechController.lastErrorMessage {
                readerSpeechErrorBanner(message: speechErrorMessage)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(4)
            }

            if showSettings {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        closeSettingsPanel()
                    }
                    .transition(.opacity)

                settingsPanel
                    .zIndex(2)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if showGoalCelebrationToast {
                VStack {
                    HStack(spacing: 8) {
                        Text("🎉")
                            .font(.system(size: 16))
                        Text("今日阅读目标达成！已连续阅读 \(streakDaysCount) 天")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.85))
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                    .padding(.top, 50)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    Spacer()
                }
                .zIndex(10)
            }

            if !showOverlay && speechController.isSpeaking {
                VStack {
                    Spacer()
                    floatingSpeechCapsule
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .zIndex(5)
            } else if !showOverlay && autoScrollEnabled {
                VStack {
                    Spacer()
                    floatingAutoScrollCapsule
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .zIndex(5)
            }
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .preference(key: ReaderViewportSizePreferenceKey.self, value: proxy.size)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(!showOverlay)
        .preferredColorScheme(background == .dark ? .dark : .light)
        .highRefreshRateSurface()
        .confirmationDialog("购买本章", isPresented: $showPayActionConfirmation, titleVisibility: .visible) {
            Button("继续购买") {
                Task { await performPayAction() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(content.title)
        }
        .alert("购买提示", isPresented: $showPayActionResult) {
            Button("好", role: .cancel) {}
        } message: {
            Text(payActionResultMessage)
        }
        .sheet(isPresented: $showChapterList) {
            chapterListSheet
        }
        .sheet(isPresented: $showBookmarks) {
            bookmarkSheet
        }
        .sheet(item: $quoteCardBookmark) { bookmark in
            let shelfBook = appState.bookshelfStore.book(id: bookID)
            QuoteCardView(
                quote: bookmark.snippet.isEmpty ? bookmark.chapterTitle : bookmark.snippet,
                bookTitle: shelfBook?.title ?? content.title,
                author: shelfBook?.author ?? "",
                chapterTitle: bookmark.chapterTitle
            )
        }
        .sheet(item: Binding(
            get: { selectedIllustrationURL.map { IdentifiableReaderURL(url: $0) } },
            set: { selectedIllustrationURL = $0?.url }
        )) { item in
            IllustrationZoomViewer(url: item.url, headers: imageRequestHeaders)
        }
        .sheet(isPresented: $showBookDetailSheet) {
            NavigationStack {
                if let shelfBook = appState.bookshelfStore.book(id: bookID) {
                    BookDetailView(book: shelfBook.asSearchBook)
                } else {
                    BookDetailView(book: SearchBook(
                        name: content.title,
                        author: nil,
                        coverUrl: nil,
                        bookUrl: content.chapter.bookUrl,
                        sourceName: "当前书源",
                        sourceUrl: content.chapter.url,
                        intro: nil
                    ))
                }
            }
        }
        .onAppear {
            if let ov = ReaderOverrideStore.shared.override(for: bookID) {
                isPerBookOverride = true
                if let mode = ov.readerMode { readerModeRawValue = mode.rawValue }
                if let font = ov.fontFamily { fontFamilyRawValue = font.rawValue }
                if let size = ov.fontSize { fontSize = size }
                if let spacing = ov.lineSpacing { lineSpacing = spacing }
                if let bg = ov.background { backgroundRawValue = bg.rawValue }
            }
            appState.acquireTabChromeHidden(owner: tabChromeOwner)
            chromeState.setInitialOverlayVisible(initialOverlayVisible)
            sessionStartedAt = Date()
            rebuildPagedBlocksCache()
            readerContentFingerprint = makeContentFingerprint(content)
            let initial = initialAutoScrollTarget()
            scrollParagraphTarget = initial.paragraph
            pagedPageIndex = initial.page
            UIDevice.current.isBatteryMonitoringEnabled = true
            previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
            brightnessBeforeReader = UIScreen.main.brightness
            applyReaderBrightness()
            applyIdleTimerPreference()
            scheduleSleepTimer()
            appState.bookshelfStore.markReaderOpened(bookID: bookID)
            persistReadingPosition(paragraphIndexOverride: initial.paragraph)
            if autoplaySpeechOnAppear {
                onSpeechAutoplayConsumed?()
                DispatchQueue.main.async {
                    beginSpeechPlayback()
                }
            }
            if autoplayAutoScrollOnAppear {
                onAutoScrollAutoplayConsumed?()
                DispatchQueue.main.async {
                    startAutoScroll()
                }
            }
        }
        .task(id: imageHeaderCacheKey) {
            refreshImageRequestHeaders()
        }
        .onDisappear {
            positionPersistTask?.cancel()
            pageLayoutTask?.cancel()
            persistReadingPosition(paragraphIndexOverride: currentParagraphIndexForPersistence())
            stopAutoScroll()
            sleepTimerTask?.cancel()
            sleepTimerTask = nil
            stopSpeechPlayback()
            pageLayoutTask = nil
            restoreIdleTimerPreference()
            UIDevice.current.isBatteryMonitoringEnabled = false
            if let brightnessBeforeReader {
                UIScreen.main.brightness = brightnessBeforeReader
            }
            appState.releaseTabChromeHidden(owner: tabChromeOwner)
            appState.bookshelfStore.recordReadingSession(
                bookID: bookID,
                duration: Date().timeIntervalSince(sessionStartedAt)
            )
        }
        .onChange(of: keepScreenAwake) { _ in
            applyIdleTimerPreference()
        }
        .onChange(of: sleepTimerMinutes) { _ in
            scheduleSleepTimer()
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active {
                if autoScrollEnabled {
                    autoScrollPausedForScene = true
                    stopAutoScroll(clearScenePause: false)
                }
                // Speech continues playing in background / screen lock
            } else {
                if autoScrollPausedForScene {
                    autoScrollPausedForScene = false
                    startAutoScroll()
                }
                if speechPausedForScene && speechController.isPaused {
                    speechController.resume()
                    playbackCoordinator.resumeSpeech()
                    speechPausedForScene = false
                }
            }
        }
        .onChange(of: scrollParagraphTarget) { _ in
            // Persisting the whole bookshelf serializes JSON to disk. Debounce
            // target changes so paging/auto-scroll stays on the rendering path.
            scheduleReadingPositionPersistence(paragraphIndex: currentParagraphIndexForPersistence())
        }
        .onChange(of: pagedPageIndex) { _ in
            scheduleReadingPositionPersistence(paragraphIndex: currentParagraphIndexForPersistence())
        }
        .onChange(of: content) { updatedContent in
            // Chapter handoff normally recreates the reader, but keeping a
            // revision here also handles cache refreshes that replace text in
            // place (including edits to a middle paragraph).
            readerContentFingerprint = makeContentFingerprint(updatedContent)
            // Never carry a previous chapter's playback, page or sheet state
            // into freshly loaded content. This also covers source switching
            // when the owner reuses the same reader identity.
            stopAutoScroll()
            stopSpeechPlayback()
            pageLayoutTask?.cancel()
            pageLayoutTask = nil
            pagedBlocksCache.removeAll()
            pagedBlocksCacheKey = ""
            positionMappingCache = ReaderPositionMapping(paragraphCount: updatedContent.paragraphs.count)
            scrollParagraphTarget = 0
            pagedPageIndex = 0
            visibleParagraphIndex = 0
            paragraphJumpRequest = nil
            closeSettingsPanel()
            showChapterList = false
            showBookmarks = false
            chromeState.setInitialOverlayVisible(initialOverlayVisible)
            DispatchQueue.main.async {
                rebuildPagedBlocksCache()
            }
        }
        .onChange(of: readerModeRawValue) { _ in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            // A mode switch changes the page model itself. Rebuild now so the
            // first paged frame has a valid mapping; slider/rotation changes
            // use the debounced path below.
            pageLayoutTask?.cancel()
            pageLayoutTask = nil
            rebuildPagedBlocksCache()
            let paragraph = positionMapping.clampParagraph(visibleParagraphIndex)
            stopAutoScroll()
            stopSpeechPlayback()
            scrollParagraphTarget = paragraph
            scrollJumpGeneration &+= 1
            paragraphJumpRequest = nil
            pagedPageIndex = ReaderPagedNavigationPolicy.clampedPageIndex(
                positionMapping.page(containingParagraph: paragraph),
                pageCount: pagedBlocksCache.count
            )
            persistReadingPosition(paragraphIndexOverride: paragraph)
            if isPerBookOverride {
                let ov = BookReaderOverride(
                    readerMode: ReaderMode(rawValue: readerModeRawValue),
                    fontFamily: ReaderFontFamily(rawValue: fontFamilyRawValue),
                    fontSize: fontSize,
                    lineSpacing: lineSpacing,
                    background: ReaderBackground(rawValue: backgroundRawValue)
                )
                ReaderOverrideStore.shared.setOverride(ov, for: bookID)
            }
        }
        .onChange(of: initialParagraphIndex) { target in
            guard let target, content.paragraphs.indices.contains(target) else { return }
            guard target != visibleParagraphIndex else { return }
            jumpToParagraph(target)
        }
        .onChange(of: readerPageCacheKey) { _ in
            schedulePagedBlocksCacheRebuild()
        }
        .onChange(of: readerBrightness) { _ in
            applyReaderBrightness()
        }
        // Overlay/settings transitions are driven at their mutation sites.
        // Keeping animation scoped there prevents a toolbar toggle from
        // implicitly animating the native text surface and page layout.
        .onPreferenceChange(ReaderViewportSizePreferenceKey.self) { size in
            guard size.width > 1, size.height > 1, size != viewportSize else { return }
            viewportSize = size
        }
    }

    private var readerBackdrop: some View {
        ZStack {
            if background == .custom, let image = ReaderCustomWallpaperStore.loadWallpaper() {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .id(backgroundWallpaperRevision)
                Color.black.opacity(colorScheme == .dark ? 0.60 : 0.28)
            } else {
                background.color(isNight: colorScheme == .dark)
                LinearGradient(
                    colors: [
                        Color.white.opacity(background == .dark ? 0.02 : 0.16),
                        Color.clear,
                        Color.black.opacity(background == .dark ? 0.28 : 0.05)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                RadialGradient(
                    colors: [
                        AppTheme.accent.opacity(background == .dark ? 0.16 : 0.08),
                        Color.clear
                    ],
                    center: .topTrailing,
                    startRadius: 20,
                    endRadius: 360
                )
                .blendMode(background == .dark ? .screen : .multiply)
            }
        }
        .ignoresSafeArea()
    }

    private var chromeForeground: Color {
        background == .dark ? .white.opacity(0.94) : .primary
    }

    private var chromeSecondaryForeground: Color {
        background == .dark ? .white.opacity(0.62) : .secondary
    }

    private var readerThemeTextColor: Color {
        background.textColor(isNight: colorScheme == .dark)
    }

    private var readerThemeBackground: Color {
        background.color(isNight: colorScheme == .dark)
    }

    @ViewBuilder
    private var readerContent: some View {
        switch readerMode {
        case .scroll:
            scrollReaderContent
        case .pageTurn, .cover, .pageCurl:
            pagedReaderContent
        }
    }

    private var scrollModeParagraphs: [String] {
        guard !appendedSections.isEmpty else { return content.paragraphs }
        var result = content.paragraphs
        for section in appendedSections {
            result.append("——— \(section.title) ———")
            result.append(contentsOf: section.paragraphs)
        }
        return result
    }

    private var scrollContentFingerprint: String {
        let baseCount = content.paragraphs.count
        let appendedCount = appendedSections.count
        let lastChapter = appendedSections.last?.chapterIndex ?? chapterIndex
        let lastParagraphsCount = appendedSections.last?.paragraphs.count ?? baseCount
        return "\(chapterIndex)|\(baseCount)|\(appendedCount)|\(lastChapter)|\(lastParagraphsCount)"
    }

    private func resolvedReadingPosition(forFlatIndex index: Int) -> (chapterIndex: Int, chapterTitle: String, paragraphIndex: Int) {
        if index < content.paragraphs.count {
            return (chapterIndex, content.title, max(index, 0))
        }
        var offset = content.paragraphs.count
        for section in appendedSections {
            if index == offset {
                return (section.chapterIndex, section.title, 0)
            }
            offset += 1
            let count = section.paragraphs.count
            if index < offset + count {
                return (section.chapterIndex, section.title, index - offset)
            }
            offset += count
        }
        if let last = appendedSections.last {
            return (last.chapterIndex, last.title, max(last.paragraphs.count - 1, 0))
        }
        return (chapterIndex, content.title, max(content.paragraphs.count - 1, 0))
    }

    private var activeScrollTarget: Int? {
        if speechController.isSpeaking, speechController.currentParagraphIndex >= 0 {
            return speechController.currentParagraphIndex
        }
        if let jump = paragraphJumpRequest {
            return jump.index
        }
        return nil
    }

    private var currentBookSource: BookSource? {
        let sourceURL = appState.bookshelfStore.book(id: bookID)?.sourceURL
            ?? (bookID.contains("|") ? String(bookID.split(separator: "|")[0]) : nil)
        guard let sourceURL else { return nil }
        return appState.sourceStore.source(for: sourceURL)
    }

    /// Legado's pay button is visible only for `hasLogin && isVip && !isPay`.
    /// `isPay` is optional because older caches do not carry it; `nil` means
    /// unknown and keeps the button visible, while an explicit `true` hides it.
    private var canShowPayAction: Bool {
        guard let payAction = content.payAction, !payAction.isEmpty else { return false }
        guard content.chapter.isVip, content.chapter.isPay != true, let source = currentBookSource else { return false }
        return source.loginUrl?.nilIfEmpty != nil || source.loginCheckJs?.nilIfEmpty != nil
    }

    /// Legado `ReadBookActivity.payAction()`：确认后执行书源的购买规则。
    /// 引擎负责 JS、cookie 与持久状态；视图只处理三种结果。
    private func performPayAction() async {
        guard let payAction = content.payAction?.trimmingCharacters(in: .whitespacesAndNewlines),
              !payAction.isEmpty else { return }
        guard let source = currentBookSource else {
            payActionResultMessage = "找不到书源，无法执行购买操作"
            showPayActionResult = true
            return
        }
        guard !isPerformingPayAction else { return }
        isPerformingPayAction = true
        let result = await appState.engine.performPayAction(
            source: source,
            chapter: content.chapter,
            payAction: payAction
        )
        isPerformingPayAction = false
        switch result {
        case .success(.openURL(let url)):
            let opened = await UIApplication.shared.open(url)
            if !opened {
                payActionResultMessage = "无法打开购买页面"
                showPayActionResult = true
            }
        case .success(.purchased):
            // Legado: BookHelp.delContent(book, chapter) before loadChapterList.
            // Invalidate first so a failed refresh cannot serve the old VIP
            // placeholder from cache.
            appState.chapterContentCacheStore.invalidate(
                sourceURL: source.bookSourceUrl,
                chapter: content.chapter
            )
            payActionResultMessage = "购买成功，正在刷新本章"
            showPayActionResult = true
            onRefreshChapter?()
        case .success(.failed(let message)):
            payActionResultMessage = message
            showPayActionResult = true
        case .failure(let error):
            payActionResultMessage = error.displayMessage
            showPayActionResult = true
        }
    }

    /// Header JSON is decoded once per source revision instead of on every
    /// SwiftUI body pass (a page with several illustrations used to re-parse
    /// it once per image).
    private var imageRequestHeaders: [String: String] {
        imageHeaderCache
    }

    private var imageHeaderCacheKey: String {
        "\(bookID)|\(currentBookSource?.bookSourceUrl ?? "")"
    }

    private func refreshImageRequestHeaders() {
        guard let source = currentBookSource else {
            imageHeaderCache = [:]
            return
        }
        imageHeaderCache = SourceRequestBuilder().imageRequestHeaders(for: source)
    }

    private var currentImageStyle: ReaderImageStyle {
        content.readerImageStyle
    }

    private var scrollReaderContent: some View {
        NativeReaderTextView(
            title: content.title,
            paragraphs: scrollModeParagraphs,
            contentFingerprint: scrollContentFingerprint,
            isAppendedUpdate: !appendedSections.isEmpty,
            fontFamily: fontFamily,
            fontSize: fontSize,
            lineSpacing: lineSpacing,
            pagePadding: pagePadding,
            letterSpacing: letterSpacing,
            paragraphSpacing: paragraphSpacing,
            paragraphIndent: paragraphIndent,
            titleSpacing: titleSpacing,
            footerHeight: footerHeight,
            textColor: background.uiTextColor(isNight: colorScheme == .dark),
            highlightColor: AppTheme.accentUIColor.withAlphaComponent(background == .dark ? 0.22 : 0.12),
            currentParagraphIndex: speechController.currentParagraphIndex,
            scrollTarget: activeScrollTarget,
            scrollRequestKey: nativeScrollRequestKey,
            animatedScrollDuration: autoScrollEnabled ? max(ReaderAutomationPolicy.clampedDelay(autoScrollDelay) * 0.9, 0.25) : (speechController.isSpeaking ? 0.35 : 0),
            textSelectionEnabled: textSelectionEnabled,
            showChapterEndBadge: false,
            imageStyle: currentImageStyle,
            imageHeaders: imageRequestHeaders,
            imageColumnWidth: illustrationColumnWidth,
            onVisibleParagraph: { index in
                if paragraphJumpRequest != nil {
                    paragraphJumpRequest = nil
                }
                updateVisibleParagraphInScroll(index)
            },
            onNearBottom: {
                appendNextChapterIfPossible()
            },
            onReachTop: nil,
            onReachBottom: {
                appendNextChapterIfPossible()
            },
            pageStepDirection: pageStepDirection,
            pageStepGeneration: pageStepGeneration,
            onPageStepBoundary: { direction in
                // The text surface already sits on its first/last line, so a
                // further page tap hands over to the neighbouring chapter.
                if direction < 0 {
                    guard canSelectRelativeChapter(offset: -1) else { return }
                    selectRelativeChapter(offset: -1, startAtEnd: true)
                } else {
                    guard canSelectRelativeChapter(offset: 1) else { return }
                    selectRelativeChapter(offset: 1)
                }
            }
        )
        .ignoresSafeArea(.container, edges: .bottom)
        .onAppear {
            if scrollParagraphTarget > 0 {
                scrollJumpGeneration &+= 1
                DispatchQueue.main.async {
                    paragraphJumpRequest = ParagraphJumpRequest(index: scrollParagraphTarget)
                }
            }
        }
        .onChange(of: chapterIndex) { _ in
            appendedSections.removeAll()
            isAppendingNextChapter = false
        }
        .onChange(of: readerModeRawValue) { _ in
            appendedSections.removeAll()
            isAppendingNextChapter = false
        }
        .onChange(of: speechController.currentParagraphIndex) { target in
            guard target >= 0 else { return }
            scheduleReadingPositionPersistence(paragraphIndex: target)
        }
    }

    private func appendNextChapterIfPossible() {
        guard readerMode == .scroll, !isAppendingNextChapter else { return }
        guard appendedSections.count < 50 else { return }

        let nextIndex = (appendedSections.last?.chapterIndex ?? chapterIndex) + 1
        let maxCount = totalChapters ?? chapters.count
        guard nextIndex < maxCount else { return }
        // `onNearBottom` and `onReachBottom` can both fire in one runloop, and
        // the cached branch appends synchronously. Without an identity check
        // the same chapter was appended several times and the reader showed
        // duplicated text.
        guard appendedSections.last?.chapterIndex != nextIndex else { return }

        onCacheNextChapters?()

        // 1. Check local text chapters
        if let book = appState.bookshelfStore.book(id: bookID),
           let localChapters = book.localChapters,
           localChapters.indices.contains(nextIndex) {
            let nextLocal = localChapters[nextIndex]
            isAppendingNextChapter = true
            appendedSections.append(ContinuousAppendedSection(
                chapterIndex: nextIndex,
                title: nextLocal.title,
                paragraphs: nextLocal.paragraphs
            ))
            isAppendingNextChapter = false
            return
        }

        // 2. Check online book chapters
        guard let nextChapter = chapters.first(where: { $0.index == nextIndex }) else { return }
        let sourceURL = appState.bookshelfStore.book(id: bookID)?.sourceURL
            ?? (bookID.contains("|") ? String(bookID.split(separator: "|")[0]) : nil)
        guard let sourceURL, let source = appState.sourceStore.source(for: sourceURL) else { return }
        let purifyRules = appState.purifyRuleStore.enabledPatterns

        if let cached = appState.chapterContentCacheStore.content(
            sourceURL: source.bookSourceUrl,
            chapter: nextChapter,
            purifyRules: purifyRules
        ) {
            isAppendingNextChapter = true
            appendedSections.append(ContinuousAppendedSection(
                chapterIndex: nextIndex,
                title: nextChapter.title,
                paragraphs: cached.paragraphs
            ))
            isAppendingNextChapter = false
            // Pre-load the chapter after this one in background so it's ready ahead of time!
            let followingIndex = nextIndex + 1
            if followingIndex < maxCount,
               let followingChapter = chapters.first(where: { $0.index == followingIndex }),
               !appState.chapterContentCacheStore.isCached(sourceURL: source.bookSourceUrl, chapter: followingChapter, purifyRules: purifyRules) {
                Task {
                    let engine = appState.engine
                    let result = await AsyncTimeout.run(seconds: 8) {
                        await engine.getContent(source: source, chapter: followingChapter)
                    }
                    if case .success(let loaded) = result {
                        await MainActor.run {
                            appState.chapterContentCacheStore.save(loaded, sourceURL: source.bookSourceUrl, purifyRules: purifyRules)
                        }
                    }
                }
            }
            return
        }

        // 3. Not in cache: fetch in background Task
        isAppendingNextChapter = true
        let originChapterIndex = chapterIndex
        Task {
            let engine = appState.engine
            let result = await AsyncTimeout.run(seconds: 12) {
                await engine.getContent(source: source, chapter: nextChapter)
            }
            await MainActor.run {
                self.isAppendingNextChapter = false
                // The chapter can change while a slow source is still
                // answering.  Appending that stale chapter into the new one
                // showed the wrong text after the handoff.
                guard self.readerMode == .scroll,
                      self.chapterIndex == originChapterIndex,
                      self.appendedSections.count < 50,
                      self.appendedSections.last?.chapterIndex != nextIndex else { return }
                if case .success(let loaded) = result {
                    self.appState.chapterContentCacheStore.save(loaded, sourceURL: source.bookSourceUrl, purifyRules: purifyRules)
                    self.appendedSections.append(ContinuousAppendedSection(
                        chapterIndex: nextIndex,
                        title: nextChapter.title,
                        paragraphs: loaded.paragraphs
                    ))
                }
            }
        }
    }

    private func updateVisibleParagraphInScroll(_ index: Int) {
        guard visibleParagraphIndex != index else { return }
        visibleParagraphIndex = index
        let resolved = resolvedReadingPosition(forFlatIndex: index)
        scheduleReadingPositionPersistence(paragraphIndex: resolved.paragraphIndex)
    }

    private var nativeScrollRequestKey: String {
        [
            String(chapterIndex),
            String(scrollJumpGeneration),
            String(pagedPageIndex),
            paragraphJumpRequest?.id.uuidString ?? "none",
            String(speechController.currentParagraphIndex)
        ].joined(separator: "|")
    }

    @ViewBuilder
    private var pagedReaderContent: some View {
        switch readerMode {
        case .cover:
            coverPagedReaderContent
        case .pageCurl:
            pageCurlReaderContent
        default:
            horizontalPagedReaderContent
        }
    }

    private var pageCurlReaderContent: some View {
        PageCurlReaderView(
            pages: pagedBlocks,
            contentRevision: pagedBlocksCacheKey,
            currentPageIndex: $pagedPageIndex,
            onPageChanged: { target in
                updatePagedVisibleParagraph(pageIndex: target)
            },
            pageBuilder: { page in
                readerPage(for: page)
            }
        )
        .onChange(of: speechController.currentParagraphIndex) { target in
            guard target >= 0 else { return }
            pagedPageIndex = pageIndex(containingParagraph: target)
        }
    }

    private var horizontalPagedReaderContent: some View {
        TabView(selection: $pagedPageIndex) {
            ForEach(pagedBlocks) { page in
                readerPage(for: page)
                .tag(page.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .onChange(of: pagedPageIndex) { target in
            updatePagedVisibleParagraph(pageIndex: target)
        }
        .onChange(of: speechController.currentParagraphIndex) { target in
            guard target >= 0 else { return }
            pagedPageIndex = pageIndex(containingParagraph: target)
        }
    }

    private var coverPagedReaderContent: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let safeIndex = min(max(pagedPageIndex, 0), max(pagedBlocks.count - 1, 0))
            let drag = coverDragTranslation

            ZStack {
                if pagedBlocks.indices.contains(safeIndex) {
                    readerPage(for: pagedBlocks[safeIndex])
                        .id("cover-page-\(pagedBlocks[safeIndex].id)")
                        .offset(x: drag * 0.22)
                        .zIndex(1)
                }

                if drag < 0, pagedBlocks.indices.contains(safeIndex + 1) {
                    readerPage(for: pagedBlocks[safeIndex + 1])
                        .id("cover-page-\(pagedBlocks[safeIndex + 1].id)")
                        .offset(x: width + drag)
                        .shadow(color: .black.opacity(0.25), radius: 10, x: -6, y: 0)
                        .allowsHitTesting(false)
                        .zIndex(2)
                }

                if drag > 0, safeIndex > 0 {
                    readerPage(for: pagedBlocks[safeIndex - 1])
                        .id("cover-page-\(pagedBlocks[safeIndex - 1].id)")
                        .offset(x: -width + drag)
                        .shadow(color: .black.opacity(0.25), radius: 10, x: 6, y: 0)
                        .allowsHitTesting(false)
                        .zIndex(2)
                }
            }
            .clipped()
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 8, coordinateSpace: .local)
                    .onChanged { value in
                        guard !coverIsAnimating else { return }
                        let horizontal = value.translation.width
                        let vertical = value.translation.height
                        if abs(horizontal) > abs(vertical) * 1.15 {
                            coverDragTranslation = horizontal
                        } else {
                            coverDragTranslation = 0
                        }
                    }
                    .onEnded { value in
                        let decision = ReaderCoverSwipePolicy.decision(
                            translation: value.translation,
                            predictedEndTranslation: value.predictedEndTranslation,
                            containerWidth: width,
                            pageIndex: safeIndex,
                            pageCount: pagedBlocks.count
                        )
                        finishCoverGesture(decision, width: width)
                    }
            )
            .onChange(of: pagedPageIndex) { target in
                updatePagedVisibleParagraph(pageIndex: target)
            }
            .onChange(of: speechController.currentParagraphIndex) { target in
                guard target >= 0, !coverIsAnimating, coverDragTranslation == 0 else { return }
                pagedPageIndex = pageIndex(containingParagraph: target)
            }
        }
    }

    private func finishCoverGesture(_ decision: ReaderCoverSwipeDecision, width: CGFloat) {
        guard !coverIsAnimating else { return }
        let target: Int?
        switch decision {
        case .next:
            target = min(pagedPageIndex + 1, max(pagedBlocks.count - 1, 0))
        case .previous:
            target = max(pagedPageIndex - 1, 0)
        case .cancel:
            target = nil
        }
        guard let target, target != pagedPageIndex else {
            withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.86)) {
                coverDragTranslation = 0
            }
            return
        }

        coverIsAnimating = true
        let exitOffset = target > pagedPageIndex ? -width : width
        withAnimation(.interactiveSpring(response: 0.30, dampingFraction: 0.86)) {
            coverDragTranslation = exitOffset
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 340_000_000)
            guard coverIsAnimating else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                pagedPageIndex = target
                coverDragTranslation = 0
                coverIsAnimating = false
            }
            updatePagedVisibleParagraph(pageIndex: target)
        }
    }

    private func readerPage(for page: ReaderPageBlock) -> some View {
        pageSurface {
            VStack(alignment: .leading, spacing: 0) {
                if page.includesTitle {
                    Text(content.title)
                        .font(fontFamily.swiftUIFont(size: CGFloat(fontSize + 8), weight: .bold))
                        .foregroundStyle(readerThemeTextColor)
                        .padding(.bottom, CGFloat(titleSpacing))
                        .readerSelectableText(textSelectionEnabled)
                }

                ForEach(page.paragraphs) { entry in
                    paragraphText(entry)
                        .padding(
                            .top,
                            (page.paragraphs.first.map { $0.id == entry.id } ?? true)
                                ? 0
                                : (entry.isContinuation ? 0 : CGFloat(paragraphSpacing))
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
        }
    }

    private func makeContentFingerprint(_ value: ChapterContent) -> String {
        var hasher = Hasher()
        hasher.combine(value.chapter.id)
        hasher.combine(value.title)
        hasher.combine(value.nextContentUrl ?? "")
        hasher.combine(value.paragraphs.count)
        for paragraph in value.paragraphs {
            hasher.combine(paragraph)
        }
        return String(hasher.finalize())
    }

    private func pageSurface<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, CGFloat(pagePadding))
            .padding(.top, ReaderPageLayoutEngine.minimumTopInset(pagePadding: CGFloat(pagePadding)))
            .padding(.bottom, CGFloat(pagePadding) + CGFloat(footerHeight))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                if readerMode == .cover {
                    Rectangle()
                        .fill(readerThemeBackground)
                        .shadow(color: .black.opacity(background == .dark ? 0.45 : 0.22), radius: 14, x: -6, y: 0)
                } else {
                    readerThemeBackground
                }
            }
    }

    @ViewBuilder
    private func paragraphText(_ entry: ReaderPageEntry) -> some View {
        if let url = ReaderImageSizingPolicy.imageURL(in: entry.text) {
            illustrationCard(url: url)
        } else {
            standardParagraphText(entry.text, index: entry.index)
        }
    }

    private func standardParagraphText(_ paragraph: String, index: Int) -> some View {
        Text(paragraph)
            .font(fontFamily.swiftUIFont(size: CGFloat(fontSize), weight: .regular))
            .foregroundStyle(readerThemeTextColor)
            .kerning(letterSpacing)
            .lineSpacing(lineSpacing)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, speechController.currentParagraphIndex == index ? 6 : 0)
            .background {
                if speechController.currentParagraphIndex == index {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppTheme.accent.opacity(background == .dark ? 0.22 : 0.12))
                }
            }
            .readerSelectableText(textSelectionEnabled)
    }

    private func illustrationCard(url: URL) -> some View {
        Button {
            selectedIllustrationURL = url
            HapticFeedback.light()
        } label: {
            ReaderIllustrationView(
                url: url,
                style: currentImageStyle,
                headers: imageRequestHeaders,
                textColor: readerThemeTextColor,
                columnWidth: illustrationColumnWidth,
                maximumHeight: ReaderImageSizingPolicy.maximumHeight(
                    for: currentImageStyle,
                    viewportHeight: effectiveViewportSize.height,
                    pagePadding: pagePadding,
                    footerHeight: footerHeight
                )
            )
        }
        .buttonStyle(.plain)
    }

    /// The reader already reserves `footerHeight` below the last line in every
    /// mode, but the band stayed empty, so a full-screen page showed no clock,
    /// battery or progress once the chrome auto-hid.  This fills that reserved
    /// band and never intercepts taps.
    private var readerFooter: some View {
        TimelineView(.everyMinute) { context in
            VStack {
                Spacer(minLength: 0)
                HStack(spacing: 12) {
                    Text(context.date, format: .dateTime.hour().minute())
                        .frame(width: 54, alignment: .leading)

                    Spacer(minLength: 4)

                    Text(progressTitle)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .frame(maxWidth: .infinity)

                    Spacer(minLength: 4)

                    HStack(spacing: 3) {
                        Image(systemName: batterySymbolName)
                        Text(batteryPercentageText)
                    }
                    .frame(width: 58, alignment: .trailing)
                }
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(readerThemeTextColor.opacity(0.45))
                .padding(.horizontal, max(CGFloat(pagePadding), 18))
                .padding(.bottom, 6)
                .frame(height: max(CGFloat(footerHeight), 24), alignment: .bottom)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var batteryPercentageText: String {
        let level = UIDevice.current.batteryLevel
        guard level >= 0 else { return "--" }
        return "\(Int((level * 100).rounded()))%"
    }

    private var batterySymbolName: String {
        let device = UIDevice.current
        if device.batteryState == .charging || device.batteryState == .full {
            return "battery.100.bolt"
        }
        let level = device.batteryLevel
        guard level >= 0 else { return "battery.100" }
        if level < 0.15 { return "battery.0" }
        if level < 0.4 { return "battery.25" }
        if level < 0.65 { return "battery.50" }
        if level < 0.9 { return "battery.75" }
        return "battery.100"
    }

    private var readerOverlay: some View {
        VStack {
            HStack {
                chromeIconButton(systemName: "chevron.left") {
                    dismiss()
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(currentDisplayChapterTitle)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(chromeForeground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .layoutPriority(1)
                    Text(progressTitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(chromeSecondaryForeground)
                        .lineLimit(1)
                }

                Spacer()

                extraToolbarActions()

                chromeIconButton(systemName: isCurrentChapterBookmarked ? "bookmark.fill" : "bookmark") {
                    toggleCurrentBookmark(openList: false)
                }

                Menu {
                    if let onRefreshChapter {
                        Button {
                            closeReaderChrome()
                            onRefreshChapter()
                        } label: {
                            Label("刷新本章", systemImage: "arrow.clockwise")
                        }
                    }

                    if canShowPayAction {
                        Button {
                            closeReaderChrome()
                            showPayActionConfirmation = true
                        } label: {
                            Label("购买本章", systemImage: "cart")
                        }
                        .disabled(isPerformingPayAction)
                    }

                    if let onCacheNextChapters {
                        Button {
                            closeReaderChrome()
                            onCacheNextChapters()
                        } label: {
                            Label("缓存后续章节", systemImage: "square.and.arrow.down")
                        }
                    }

                    Button {
                        closeReaderChrome()
                        showBookDetailSheet = true
                        onRequestBookDetail?()
                    } label: {
                        Label("书籍详情", systemImage: "info.circle")
                    }

                    Button {
                        closeReaderChrome()
                        onRequestSourceSwitch?()
                    } label: {
                        Label("换源", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(onRequestSourceSwitch == nil)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(.thinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("书籍详情和换源")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.top, 4)

            Spacer()

            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    navChapterButton(icon: "chevron.left", title: "上一章") {
                        selectRelativeChapter(offset: -1)
                    }
                    .disabled(!canSelectRelativeChapter(offset: -1))

                    Slider(
                        value: Binding(
                            get: { chapterSliderTarget ?? Double(chapterIndex) },
                            set: { chapterSliderTarget = $0 }
                        ),
                        in: 0...Double(max((totalChapters ?? chapters.count) - 1, 0)),
                        step: 1,
                        onEditingChanged: { editing in
                            guard !editing, let target = chapterSliderTarget else { return }
                            chapterSliderTarget = nil
                            let index = Int(target.rounded())
                            guard index != chapterIndex else { return }
                            selectChapter(index: index)
                        }
                    )
                        .tint(AppTheme.accent)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity)
                        .background(.thinMaterial, in: Capsule())
                        .accessibilityLabel("章节进度")

                    navChapterButton(icon: "chevron.right", title: "下一章") {
                        selectRelativeChapter(offset: 1)
                    }
                    .disabled(!canSelectRelativeChapter(offset: 1))
                }

                HStack(spacing: 8) {
                    toolButton(icon: "list.bullet", title: "目录") {
                        tocTab = 0
                        showChapterList = true
                        closeSettingsPanel()
                    }

                    toolButton(icon: speechController.isPaused ? "play.fill" : (speechController.isSpeaking ? "pause.fill" : "speaker.wave.2"), title: speechController.isPaused ? "继续" : (speechController.isSpeaking ? "暂停" : "朗读")) {
                        toggleSpeech()
                        closeSettingsPanel()
                    }
                    // Keep the stop slot even while idle. Inserting and
                    // removing it shifted every button after it on each TTS
                    // toggle.
                    toolButton(icon: "stop.fill", title: "停止") {
                        stopSpeechPlayback()
                        closeSettingsPanel()
                    }
                    .opacity(speechController.isSpeaking ? 1 : 0.35)
                    .disabled(!speechController.isSpeaking)
                    toolButton(icon: autoScrollEnabled ? "pause.fill" : "play.fill", title: autoScrollEnabled ? "暂停" : "自动") {
                        toggleAutoScroll()
                        closeSettingsPanel()
                    }
                    toolButton(icon: "gearshape", title: "设置") {
                        toggleSettingsPanel()
                    }
                    .overlay(alignment: .topTrailing) {
                        if let badge = sleepTimerBadgeText {
                            Text(badge)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(AppTheme.accent)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(AppTheme.accent.opacity(0.14), in: Capsule())
                                .offset(x: 2, y: -2)
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 18)
            .glassPanel(cornerRadius: 26, material: .ultraThinMaterial, strokeOpacity: background == .dark ? 0.09 : 0.12, shadowOpacity: background == .dark ? 0.42 : 0.14)
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
        .foregroundStyle(chromeForeground)
    }

    private func navChapterButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                Text(title)
                    .font(.system(size: 10, weight: .medium))
            }
            .frame(width: 54, height: 48)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func toolButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                Text(title)
                    .font(.system(size: 10, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func chromeIconButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(.thinMaterial, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private var settingsHint: String {
        switch settingsTab {
        case 0: return readerModeHint
        case 1: return "右侧可直接输入数值，精调字号、间距和边距。"
        default: return "这里保留不重复的阅读辅助：自动滚动间隔、朗读速度、睡眠定时与点击区域。"
        }
    }

    private var readerModeHint: String {
        switch readerMode {
        case .scroll:
            return "上下连续滑动，章节末尾自动衔接下一章；页内没有横向翻页手势。"
        case .pageTurn:
            return "左右平移翻页，每页固定不滚动，适合习惯整页阅读。"
        case .cover:
            return "拖动时下一页从右侧覆盖当前页，松手按位移和速度决定是否翻页。"
        case .pageCurl:
            return "系统原生纸张卷曲动画，可拖到一半再松手回弹或完成。"
        }
    }

    private var settingsPanel: some View {
        GeometryReader { proxy in
            let bottomPadding = max(proxy.safeAreaInsets.bottom, 14)
            let maxHeight = ReaderSettingsLayoutPolicy.maxPanelHeight(
                viewportHeight: proxy.size.height,
                bottomInset: proxy.safeAreaInsets.bottom
            )

            VStack {
                Spacer(minLength: 0)

                VStack(spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("阅读设置")
                                .font(.headline.weight(.semibold))
                            Text(settingsTab == 0 ? "外观和翻页感" : (settingsTab == 1 ? "字号与排版细节" : "阅读辅助与行为"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            withAnimation(.easeOut(duration: 0.18)) {
                                closeSettingsPanel()
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 44, height: 44)
                                .background(Color.secondary.opacity(0.12), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("关闭阅读设置")
                    }
                    .padding(.top, 10)
                    .padding(.horizontal)
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 12)
                            .onEnded { value in
                                guard value.translation.height > 70,
                                      abs(value.translation.height) > abs(value.translation.width) else { return }
                                closeSettingsPanel()
                            }
                    )

                    Picker("设置", selection: $settingsTab) {
                        Text("外观").tag(0)
                        Text("排版").tag(1)
                        Text("高级").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    Text(settingsHint)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)

                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 14) {
                            switch settingsTab {
                            case 0:
                                appearanceSettings
                            case 1:
                                layoutSettings
                            default:
                                advancedSettings
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 22)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: maxHeight)
                .glassPanel(cornerRadius: 28, material: .regularMaterial, strokeOpacity: colorScheme == .dark ? 0.08 : 0.12, shadowOpacity: colorScheme == .dark ? 0.35 : 0.18)
                .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .padding(.horizontal, 12)
                .padding(.bottom, bottomPadding)
                .zIndex(3)
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private func closeSettingsPanel() {
        guard showSettings else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            chromeState.closeSettings()
        }
    }

    private var appearanceSettings: some View {
        Group {
            appearancePreview

            VStack(alignment: .leading, spacing: 6) {
                Text("翻页模式")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(readerModeHint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Picker("翻页模式", selection: $readerModeRawValue) {
                ForEach(ReaderMode.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .padding(.bottom, 8)

            Toggle("仅对本书生效独立配置", isOn: Binding(
                get: { isPerBookOverride },
                set: { enabled in
                    isPerBookOverride = enabled
                    if enabled {
                        let ov = BookReaderOverride(
                            readerMode: ReaderMode(rawValue: readerModeRawValue),
                            fontFamily: ReaderFontFamily(rawValue: fontFamilyRawValue),
                            fontSize: fontSize,
                            lineSpacing: lineSpacing,
                            background: ReaderBackground(rawValue: backgroundRawValue)
                        )
                        ReaderOverrideStore.shared.setOverride(ov, for: bookID)
                    } else {
                        ReaderOverrideStore.shared.clearOverride(for: bookID)
                    }
                }
            ))
            .font(.subheadline.weight(.semibold))
            .padding(.vertical, 4)

            Text("背景颜色")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(ReaderBackground.allCases) { item in
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            backgroundRawValue = item.rawValue
                        } label: {
                            VStack(spacing: 4) {
                                Circle()
                                    .fill(item.color(isNight: colorScheme == .dark))
                                    .frame(width: 40, height: 40)
                                    .overlay {
                                        Circle()
                                            .stroke(background == item ? AppTheme.accent : Color.secondary.opacity(0.25), lineWidth: background == item ? 3 : 1)
                                    }
                                Text(item.title)
                                    .font(.caption2)
                                    .foregroundStyle(background == item ? AppTheme.accent : .secondary)
                            }
                        }
                        .accessibilityLabel(item.title)
                    }
                }
                .padding(.horizontal, 2)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("阅读亮度")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(readerBrightness < 0 ? "跟随系统" : "\(Int(readerBrightness * 100))%")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.accent)
                    Button("跟随系统") {
                        readerBrightness = -1
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(readerBrightness < 0 ? .secondary : AppTheme.accent)
                    .disabled(readerBrightness < 0)
                }
                Slider(
                    value: Binding(
                        get: { readerBrightness < 0 ? Double(UIScreen.main.brightness) : readerBrightness },
                        set: { readerBrightness = $0 }
                    ),
                    in: 0.05...1.0
                )
                .tint(AppTheme.accent)
                Text("只影响阅读页，退出阅读器会恢复系统亮度。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if background == .custom {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    HStack(spacing: 8) {
                        Image(systemName: "photo.badge.plus")
                        Text(ReaderCustomWallpaperStore.hasCustomWallpaper ? "更换自定义壁纸" : "从相册选择壁纸")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(AppTheme.accent)
                }
                .onChange(of: selectedPhotoItem) { item in
                    guard let item else { return }
                    Task {
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let image = UIImage(data: data) {
                            ReaderCustomWallpaperStore.saveWallpaper(image)
                            backgroundWallpaperRevision = UUID()
                        }
                    }
                }
            }
        }
    }

    private var appearancePreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("阅读预览")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(readerThemeTextColor.opacity(0.64))
                Spacer()
                Text("\(fontFamily.title) · \(Int(fontSize))pt · 缩进\(Int(paragraphIndent))pt")
                    .font(.caption2)
                    .foregroundStyle(readerThemeTextColor.opacity(0.55))
            }

            Text("　　夜色沉下来以后，文字应该安静、清楚、耐看。调整外观与排版时，这里会立刻跟随字体、字号、行距、段首缩进和背景变化。")
                .font(fontFamily.swiftUIFont(size: min(CGFloat(fontSize), 24), weight: .regular))
                .foregroundStyle(readerThemeTextColor)
                .lineSpacing(lineSpacing)
                .lineLimit(4)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(readerThemeBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(background == .dark ? 0.12 : 0.06), lineWidth: 0.8)
        }
    }

    private func readerStatusBanner(message: String) -> some View {
        VStack {
            HStack(spacing: 8) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                Text(message)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .foregroundStyle(readerThemeTextColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(background == .dark ? 0.08 : 0.35), lineWidth: 0.8)
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)

            Spacer()
        }
        .allowsHitTesting(false)
    }

    private func readerSpeechErrorBanner(message: String) -> some View {
        VStack {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "waveform.badge.exclamationmark")
                    .font(.system(size: 15, weight: .semibold))
                Text(message)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button {
                    speechController.lastErrorMessage = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭语音错误提示")
            }
            .foregroundStyle(readerThemeTextColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.orange.opacity(0.45), lineWidth: 0.8)
            }
            .padding(.horizontal, 18)
            .padding(.top, statusMessage == nil ? 12 : 58)

            Spacer()
        }
        .animation(.easeInOut(duration: 0.2), value: message)
        .accessibilityIdentifier("reader.speechErrorBanner")
    }

    private var layoutSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            appearancePreview

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("字体")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    NavigationLink {
                        CustomFontManagementView()
                    } label: {
                        HStack(spacing: 4) {
                            Text("字体管理 / 导入")
                            Image(systemName: "chevron.right")
                        }
                        .font(.caption)
                        .foregroundStyle(AppTheme.accent)
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ReaderFontFamily.allCases) { item in
                            Button {
                                fontFamilyRawValue = item.rawValue
                                HapticFeedback.light()
                            } label: {
                                Text(item.title)
                                    .font(item.swiftUIFont(size: 14))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        fontFamilyRawValue == item.rawValue
                                            ? AppTheme.accent
                                            : Color(UIColor.tertiarySystemGroupedBackground)
                                    )
                                    .foregroundColor(
                                        fontFamilyRawValue == item.rawValue ? .white : .primary
                                    )
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Text("💡 排版说明：每项均标明具体作用与推荐值。右侧可点数字直接输入，滑块用于快速滑动粗调。已采用主流小说标准排版规范。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(UIColor.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            // 1. 段落差（段间距）- 放在最前面之一，用户反馈最高频查找项
            readerValueSlider("段落差（段间距）", value: $paragraphSpacing, range: 0...28, step: 1, unit: "pt", help: "调整上下两段文字之间的垂直留白。调到 0pt 为最紧凑贴近（推荐 4~8pt）")

            // 2. 正文字号
            readerValueSlider("正文字号", value: $fontSize, range: 12...34, step: 1, unit: "pt", help: "整体放大或缩小小说正文文字大小（主流阅读推荐 18~20pt）")

            // 3. 行距（行高间距）
            readerValueSlider("行距（行高间距）", value: $lineSpacing, range: 0...18, step: 1, unit: "pt", help: "同一段落内上下每一行文字之间的垂直间隙与呼吸感（推荐 8~10pt）")

            // 4. 段首缩进
            readerValueSlider("段首缩进", value: $paragraphIndent, range: 0...50, step: 2, unit: "pt", help: "每个段落第一行开头的缩进空格。38pt 刚好为标准空两个汉字")

            // 5. 字间距（字距）
            readerValueSlider("字间距（字距）", value: $letterSpacing, range: 0...4, step: 0.2, unit: "pt", help: "同一行中每个汉字左右之间的紧凑度（推荐 0~0.5pt）")

            // 6. 屏幕边距（左右留白）
            readerValueSlider("屏幕边距（左右留白）", value: $pagePadding, range: 10...40, step: 1, unit: "pt", help: "正文文字距离手机屏幕左右两侧边缘的距离，防止文字贴边（推荐 18~22pt）")

            // 7. 章节标题间距
            readerValueSlider("章节标题间距", value: $titleSpacing, range: 0...36, step: 2, unit: "pt", help: "大章节标题（如“第一章”）与正文第一行之间的垂直留白高度（推荐 18~24pt）")

            // 8. 底部安全留白
            readerValueSlider("底部安全留白", value: $footerHeight, range: 40...180, step: 8, unit: "pt", help: "屏幕最底部向上预留的安全空隙，防止手势遮挡最后一行正文（推荐 80~100pt）")
        }
    }

    private var advancedSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("高级里只放阅读辅助，不再重复前面的翻页和字号入口。朗读速度只管语速，自动滚动在主阅读菜单。")
                .font(.caption)
                .foregroundStyle(.secondary)

            readerValueSlider(
                "自动滚动间隔",
                value: $autoScrollDelay,
                range: ReaderAutomationPolicy.minDelay...12,
                step: 0.5,
                unit: "秒",
                help: "自动滚动每前进一段之间的等待时间。数值越小滚动越快；朗读与自动滚动互斥。"
            )

            readerValueSlider("朗读速度", value: $ttsRate, range: 0.35...0.65, step: 0.01, unit: "倍速", help: "调整语音朗读语速（0.35x ~ 0.65x），从当前可见段落开始朗读，不会跳回章节开头")

            Text("睡眠定时")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Picker("睡眠定时", selection: $sleepTimerMinutes) {
                Text("关闭").tag(0)
                Text("播完当章").tag(-1)
                Text("15 分钟").tag(15)
                Text("30 分钟").tag(30)
                Text("60 分钟").tag(60)
            }
            .pickerStyle(.segmented)

            Toggle("阅读时保持屏幕常亮", isOn: $keepScreenAwake)
                .font(.subheadline.weight(.semibold))

            Toggle("允许正文文字选择", isOn: $textSelectionEnabled)
                .font(.subheadline.weight(.semibold))

            settingStepper(title: "预加载章节", value: ReaderPreloadPolicy.title(for: preloadChapterCount)) {
                preloadChapterCount = ReaderPreloadPolicy.clamp(preloadChapterCount - 1)
            } increase: {
                preloadChapterCount = ReaderPreloadPolicy.clamp(preloadChapterCount + 1)
            }

            tapZoneSettings
        }
    }

    private func readerValueSlider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        unit: String,
        help: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)

                Text("\(ReaderValueNormalizer.formatted(value.wrappedValue, step: step)) \(unit)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AppTheme.accent.opacity(0.12), in: Capsule())

                Spacer()

                ReaderNumberInput(
                    title: title,
                    value: value,
                    range: range,
                    step: step,
                    unit: unit
                )
            }

            // 醒目的功能说明卡片，让用户清楚知道每一项调整的是什么，告别盲测
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.accent.opacity(0.85))
                    .padding(.top, 1)

                Text(help)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack(spacing: 12) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    value.wrappedValue = max(range.lowerBound, (value.wrappedValue - step))
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(value.wrappedValue <= range.lowerBound ? .secondary.opacity(0.3) : AppTheme.accent)
                }
                .disabled(value.wrappedValue <= range.lowerBound)
                .buttonStyle(.plain)

                Slider(value: value, in: range, step: step)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    value.wrappedValue = min(range.upperBound, (value.wrappedValue + step))
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(value.wrappedValue >= range.upperBound ? .secondary.opacity(0.3) : AppTheme.accent)
                }
                .disabled(value.wrappedValue >= range.upperBound)
                .buttonStyle(.plain)
            }

            HStack {
                Text("范围：\(ReaderValueNormalizer.formatted(range.lowerBound, step: step)) ~ \(ReaderValueNormalizer.formatted(range.upperBound, step: step)) \(unit)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
        }
        .padding(12)
        .background(Color(UIColor.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.8)
        }
        .padding(.vertical, 2)
    }

    private var tapZoneSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("九宫格点击区域")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                ForEach(0..<9, id: \.self) { index in
                    Menu {
                        ForEach(ReaderTapAction.allCases) { action in
                            Button(action.title) {
                                setTapZone(index: index, action: action)
                            }
                        }
                    } label: {
                        Text(tapZoneActions[index].shortTitle)
                            .font(.caption2.weight(.bold))
                            .frame(maxWidth: .infinity, minHeight: 30)
                            .background(tapZoneActions[index].color.opacity(0.16))
                            .foregroundStyle(tapZoneActions[index].color)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
            Button("恢复默认点击区域") {
                tapZonesRawValue = ReaderTapAction.defaultRawValue
            }
            .font(.caption.weight(.semibold))
        }
    }

    private var tapZoneOverlay: some View {
        VStack(spacing: 1) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 1) {
                    ForEach(0..<3, id: \.self) { column in
                        let index = row * 3 + column
                        Text(tapZoneActions[index].shortTitle)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(tapZoneActions[index].color)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(tapZoneActions[index].color.opacity(0.08))
                    }
                }
            }
        }
        .padding(CGFloat(pagePadding))
    }

    private func settingStepper(
        title: String,
        value: String,
        decrease: @escaping () -> Void,
        increase: @escaping () -> Void
    ) -> some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: decrease) {
                Image(systemName: "minus.circle.fill")
            }
            Text(value)
                .font(.headline)
                .frame(width: 44)
            Button(action: increase) {
                Image(systemName: "plus.circle.fill")
            }
        }
    }

    private var chapterListSheet: some View {
        NavigationStack {
            ZStack {
                readerBackdrop

                VStack(spacing: 0) {
                    customTocSegmentedPicker

                    if tocTab == 0 {
                        tocList
                    } else {
                        bookmarkList(includeAddButton: true)
                    }
                }
            }
            .navigationTitle(tocTab == 0 ? "目录" : "书签")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if tocTab == 0 {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(tocReversed ? "倒序" : "顺序") {
                            tocReversed.toggle()
                        }
                        .foregroundStyle(readerThemeTextColor)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        showChapterList = false
                    }
                    .foregroundStyle(readerThemeTextColor)
                }
            }
            .toolbarBackground(readerThemeBackground, for: .navigationBar)
            .toolbarColorScheme(background == .dark ? .dark : .light, for: .navigationBar)
        }
        .readerSheetPresentation(color: readerThemeBackground)
        .presentationDetents([.medium, .large])
        .tint(AppTheme.accent)
        .preferredColorScheme(background == .dark ? .dark : .light)
    }

    private var customTocSegmentedPicker: some View {
        HStack(spacing: 0) {
            tocTabButton(title: "目录", tag: 0)
            tocTabButton(title: "书签", tag: 1)
        }
        .padding(3)
        .background(readerThemeTextColor.opacity(background == .dark ? 0.16 : 0.08), in: Capsule())
        .overlay {
            Capsule()
                .stroke(readerThemeTextColor.opacity(0.12), lineWidth: 0.8)
        }
        .padding(.horizontal)
        .padding(.top, 10)
    }

    private func tocTabButton(title: String, tag: Int) -> some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                tocTab = tag
            }
        } label: {
            Text(title)
                .font(.subheadline.weight(tocTab == tag ? .semibold : .regular))
                .foregroundStyle(tocTab == tag ? .white : readerThemeTextColor.opacity(0.75))
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background {
                    if tocTab == tag {
                        Capsule()
                            .fill(AppTheme.accent)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private var tocList: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(readerThemeTextColor.opacity(0.6))

                TextField("筛选章节名或序号", text: $tocQuery)
                    .font(.system(size: 14))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .foregroundStyle(readerThemeTextColor)

                if !tocQuery.isEmpty {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        tocQuery = ""
                        debouncedTocQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(readerThemeTextColor.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(readerThemeTextColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(readerThemeTextColor.opacity(0.15), lineWidth: 0.8)
            }
            .padding(.horizontal)
            .padding(.top, 10)

            List {
                if chapters.isEmpty && navigationEntries.isEmpty {
                    Text("当前章节没有可切换目录")
                        .foregroundStyle(readerThemeTextColor.opacity(0.6))
                        .listRowBackground(Color.clear)
                } else if filteredChapters.isEmpty && filteredNavigationEntries.isEmpty {
                    Text("没有匹配章节")
                        .foregroundStyle(readerThemeTextColor.opacity(0.6))
                        .listRowBackground(Color.clear)
                } else {
                    if !filteredChapters.isEmpty {
                        Section {
                            ForEach(filteredChapters) { chapter in
                                Button {
                                    showChapterList = false
                                    presentOverlay()
                                    if let onSelectChapterWithPosition {
                                        onSelectChapterWithPosition(chapter, 0)
                                    } else {
                                        onSelectChapter?(chapter)
                                    }
                                } label: {
                                    chapterRow(chapter)
                                }
                                .disabled(!canJumpToChapter || chapter.index == chapterIndex)
                                .listRowBackground(Color.clear)
                                .listRowSeparatorTint(readerThemeTextColor.opacity(0.15))
                            }
                        } header: {
                            Text("章节 (\(filteredChapters.count))")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(readerThemeTextColor.opacity(0.65))
                        }
                    }
                    if !filteredNavigationEntries.isEmpty {
                        Section {
                            ForEach(Array(filteredNavigationEntries.enumerated()), id: \.element) { offset, entry in
                                Button {
                                    showChapterList = false
                                    presentOverlay()
                                    onSelectNavigationEntry?(entry)
                                } label: {
                                    navigationEntryRow(entry, ordinal: offset)
                                }
                                .disabled(onSelectNavigationEntry == nil || entry.chapterIndex == nil)
                                .listRowBackground(Color.clear)
                                .listRowSeparatorTint(readerThemeTextColor.opacity(0.15))
                            }
                        } header: {
                            Text("页面内目录")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(readerThemeTextColor.opacity(0.65))
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .scrollDismissesKeyboard(.interactively)
        }
        .task(id: tocQuery) {
            if tocQuery.isEmpty {
                debouncedTocQuery = ""
                return
            }
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            debouncedTocQuery = tocQuery
        }
    }

    private func chapterRow(_ chapter: BookChapter) -> some View {
        HStack(spacing: 12) {
            Text("\(chapter.index + 1)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(chapter.index == chapterIndex ? AppTheme.accent : readerThemeTextColor.opacity(0.55))
                .frame(width: 48, alignment: .leading)
            Text(chapter.title)
                .foregroundStyle(chapter.index == chapterIndex ? AppTheme.accent : readerThemeTextColor)
                .fontWeight(chapter.index == chapterIndex ? .semibold : .regular)
                .lineLimit(1)
            Spacer()
            if chapter.index == chapterIndex {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppTheme.accent)
            }
        }
    }

    private func navigationEntryRow(_ entry: LocalTextNavigationEntry, ordinal: Int) -> some View {
        HStack(spacing: 12) {
            Text("\(ordinal + 1)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(readerThemeTextColor.opacity(0.55))
                .frame(width: 48, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .foregroundStyle(readerThemeTextColor)
                    .lineLimit(1)
                if let chapterIndex = entry.chapterIndex {
                    Text("第 \(chapterIndex + 1) 章" + (entry.paragraphIndex.map { " · 第 \($0 + 1) 段" } ?? ""))
                        .font(.caption2)
                        .foregroundStyle(readerThemeTextColor.opacity(0.6))
                }
            }
            Spacer()
            Image(systemName: "arrow.down.right")
                .font(.caption)
                .foregroundStyle(readerThemeTextColor.opacity(0.4))
        }
    }

    private var bookmarkSheet: some View {
        NavigationStack {
            ZStack {
                readerBackdrop
                bookmarkList(includeAddButton: true)
                    .navigationTitle("书签")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("完成") {
                                showBookmarks = false
                            }
                            .foregroundStyle(readerThemeTextColor)
                        }
                    }
            }
            .toolbarBackground(readerThemeBackground, for: .navigationBar)
            .toolbarColorScheme(background == .dark ? .dark : .light, for: .navigationBar)
        }
        .readerSheetPresentation(color: readerThemeBackground)
        .presentationDetents([.medium, .large])
        .tint(AppTheme.accent)
        .preferredColorScheme(background == .dark ? .dark : .light)
    }

    private func bookmarkList(includeAddButton: Bool) -> some View {
        List {
            if includeAddButton {
                Button {
                    toggleCurrentBookmark(openList: false)
                } label: {
                    Label(
                        isCurrentChapterBookmarked ? "取消当前段落书签" : "加入当前段落书签",
                        systemImage: isCurrentChapterBookmarked ? "bookmark.slash" : "bookmark"
                    )
                    .foregroundStyle(AppTheme.accent)
                }
                .listRowBackground(Color.clear)
                .listRowSeparatorTint(readerThemeTextColor.opacity(0.15))
            }

            if bookmarks.isEmpty {
                Text("暂无书签")
                    .foregroundStyle(readerThemeTextColor.opacity(0.6))
                    .listRowBackground(Color.clear)
            } else {
                Section {
                    HStack {
                        Label("\(bookmarks.count) 个书签", systemImage: "bookmark")
                        Spacer()
                        Text("本章 \(currentChapterBookmarkCount)")
                            .foregroundStyle(readerThemeTextColor.opacity(0.6))
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(readerThemeTextColor.opacity(0.75))
                }
                .listRowBackground(Color.clear)
                Section {
                    ForEach(sortedBookmarks) { bookmark in
                        Button {
                            jumpToBookmark(bookmark)
                        } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(bookmark.chapterTitle)
                                        .font(.headline)
                                        .foregroundStyle(readerThemeTextColor)
                                    HStack(spacing: 6) {
                                        Text(bookmarkLocationText(bookmark))
                                        Text(bookmark.createdAt.formatted(date: .abbreviated, time: .shortened))
                                        if isCurrentBookmark(bookmark) {
                                            Text("当前")
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(AppTheme.accent.opacity(0.12))
                                                .foregroundStyle(AppTheme.accent)
                                                .clipShape(Capsule())
                                        }
                                    }
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(isCurrentBookmark(bookmark) ? AppTheme.accent : readerThemeTextColor.opacity(0.55))
                                    Text(bookmark.snippet)
                                        .font(.caption)
                                        .foregroundStyle(readerThemeTextColor.opacity(0.6))
                                        .lineLimit(2)
                                }
                                Spacer()
                                if bookmark.chapterIndex == chapterIndex {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(AppTheme.accent)
                                } else {
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(readerThemeTextColor.opacity(0.35))
                                }
                            }
                        }
                        .disabled(bookmark.chapterIndex != chapterIndex && !canJumpToChapter)
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(readerThemeTextColor.opacity(0.15))
                        .swipeActions(edge: .leading) {
                            Button {
                                quoteCardBookmark = bookmark
                            } label: {
                                Label("卡片", systemImage: "quote.bubble.fill")
                            }
                            .tint(AppTheme.accent)
                        }
                        .swipeActions(edge: .trailing) {
                            Button("删除", role: .destructive) {
                                appState.bookshelfStore.removeBookmark(bookID: bookID, bookmarkID: bookmark.id)
                            }
                        }
                        .contextMenu {
                            Button {
                                quoteCardBookmark = bookmark
                            } label: {
                                Label("生成金句卡片", systemImage: "quote.bubble")
                            }
                            Button("删除书签", role: .destructive) {
                                appState.bookshelfStore.removeBookmark(bookID: bookID, bookmarkID: bookmark.id)
                            }
                        }
                    }
                } header: {
                    Text("我的书签")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(readerThemeTextColor.opacity(0.65))
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
    }

    private func bookmarkLocationText(_ bookmark: ReaderBookmark) -> String {
        if let paragraphIndex = bookmark.paragraphIndex {
            return "第 \(bookmark.chapterIndex + 1) 章 · 第 \(paragraphIndex + 1) 段"
        }
        return "第 \(bookmark.chapterIndex + 1) 章"
    }

    private func isCurrentBookmark(_ bookmark: ReaderBookmark) -> Bool {
        bookmark.chapterIndex == chapterIndex
            && bookmark.paragraphIndex == currentBookmarkParagraphIndex
    }

    private func jumpToBookmark(_ bookmark: ReaderBookmark) {
        showBookmarks = false
        closeReaderChrome()
        if bookmark.chapterIndex == chapterIndex {
            jumpToParagraph(bookmark.paragraphIndex)
        } else {
            guard let target = chapters.first(where: { $0.index == bookmark.chapterIndex }) else { return }
            let paragraphIndex = bookmark.paragraphIndex
            if let paragraphIndex {
                appState.bookshelfStore.updateReadingProgress(
                    bookID: bookID,
                    chapterIndex: bookmark.chapterIndex,
                    chapterTitle: bookmark.chapterTitle,
                    totalChapters: totalChapters ?? 0,
                    paragraphIndex: paragraphIndex
                )
            }
            // Owners that expose the position-aware entry point can land on
            // the bookmarked paragraph directly; the plain callback always
            // started the chapter at its first paragraph.
            if let onSelectChapterWithPosition {
                onSelectChapterWithPosition(target, paragraphIndex ?? 0)
            } else {
                onSelectChapter?(target)
            }
        }
    }

    private func jumpToParagraph(_ paragraphIndex: Int?) {
        guard let paragraphIndex else { return }
        let safeIndex = min(max(paragraphIndex, 0), max(content.paragraphs.count - 1, 0))
        guard safeIndex != visibleParagraphIndex else { return }
        visibleParagraphIndex = safeIndex
        switch readerMode {
        case .scroll:
            scrollParagraphTarget = safeIndex
            scrollJumpGeneration &+= 1
            paragraphJumpRequest = ParagraphJumpRequest(index: safeIndex)
        case .pageTurn, .cover, .pageCurl:
            pagedPageIndex = pageIndex(containingParagraph: safeIndex)
        }
        persistReadingPosition(paragraphIndexOverride: safeIndex)
    }

    private var canJumpToChapter: Bool {
        onSelectChapter != nil || onSelectChapterWithPosition != nil
    }

    private func canSelectRelativeChapter(offset: Int) -> Bool {
        guard onSelectChapter != nil || onSelectChapterWithPosition != nil else { return false }
        return chapters.contains { $0.index == chapterIndex + offset }
    }

    private func selectRelativeChapter(offset: Int, startAtEnd: Bool = false) {
        guard let target = chapters.first(where: { $0.index == chapterIndex + offset }) else { return }
        closeReaderChrome()
        stopAutoScroll()
        stopSpeechPlayback()
        if let onSelectChapterWithPosition {
            onSelectChapterWithPosition(target, startAtEnd ? Int.max : 0)
        } else {
            onSelectChapter?(target)
        }
    }

    private func selectChapter(index: Int) {
        guard let target = chapters.first(where: { $0.index == index }) ?? (chapters.indices.contains(index) ? chapters[index] : nil) else { return }
        closeReaderChrome()
        stopAutoScroll()
        stopSpeechPlayback()
        if let onSelectChapterWithPosition {
            onSelectChapterWithPosition(target, 0)
        } else {
            onSelectChapter?(target)
        }
    }

    private func handleReaderTap(at location: CGPoint) {
        guard !showSettings else { return }
        let size = effectiveViewportSize
        let column = min(max(Int(location.x / max(size.width / 3, 1)), 0), 2)
        let row = min(max(Int(location.y / max(size.height / 3, 1)), 0), 2)
        let index = row * 3 + column
        let actions = tapZoneActions
        guard actions.indices.contains(index) else {
            toggleOverlay()
            return
        }
        runTapAction(actions[index])
    }

    private func runTapAction(_ action: ReaderTapAction) {
        if readerMode == .scroll {
            // Continuous mode used to drop every zone except "menu", so the
            // default left/right page zones did nothing at all.  A page turn
            // is now a viewport step on the TextKit surface; chapter zones and
            // menu keep the same meaning as the paged modes.
            switch action {
            case .previousPage:
                requestPageStep(direction: -1)
            case .nextPage:
                requestPageStep(direction: 1)
            case .previousChapter:
                selectRelativeChapter(offset: -1, startAtEnd: true)
            case .nextChapter:
                selectRelativeChapter(offset: 1)
            case .menu:
                toggleOverlay()
            case .disabled:
                break
            }
            return
        }
        switch action {
        case .previousPage:
            moveReaderTarget(to: currentReaderTarget - 1)
        case .nextPage:
            moveReaderTarget(to: currentReaderTarget + 1)
        case .previousChapter:
            selectRelativeChapter(offset: -1)
        case .nextChapter:
            selectRelativeChapter(offset: 1)
        case .menu:
            toggleOverlay()
        case .disabled:
            break
        }
    }

    private func requestPageStep(direction: Int) {
        pageStepDirection = direction
        pageStepGeneration &+= 1
    }

    private func moveReaderTarget(to rawTarget: Int) {
        let target = min(max(rawTarget, 0), maximumReaderTarget)
        if readerMode == .scroll {
            scrollParagraphTarget = target
            scrollJumpGeneration &+= 1
            paragraphJumpRequest = ParagraphJumpRequest(index: target)
        } else {
            pagedPageIndex = target
        }
        let resolvedParagraphIndex = positionMapping.paragraph(for: target, mode: readerMode)
        visibleParagraphIndex = resolvedParagraphIndex
        scheduleReadingPositionPersistence(paragraphIndex: resolvedParagraphIndex)
    }

    private var currentReaderTarget: Int {
        switch readerMode {
        case .scroll:
            return autoScrollEnabled ? autoScrollAnchorTarget : visibleParagraphIndex
        case .pageTurn, .cover, .pageCurl:
            return pagedPageIndex
        }
    }

    private func toggleOverlay() {
        withAnimation(.easeOut(duration: 0.2)) {
            if chromeState.isSettingsVisible {
                chromeState.closeSettings()
            } else {
                chromeState.toggleOverlay()
            }
        }
    }

    private func presentOverlay() {
        withAnimation(.easeOut(duration: 0.2)) {
            chromeState.setInitialOverlayVisible(true)
        }
    }

    private func toggleSettingsPanel() {
        withAnimation(.easeOut(duration: 0.2)) {
            if chromeState.isSettingsVisible {
                chromeState.closeSettings()
            } else {
                chromeState.openSettings()
            }
        }
    }

    private func closeReaderChrome() {
        withAnimation(.easeOut(duration: 0.2)) {
            chromeState.closeAll()
        }
    }

    private func setTapZone(index: Int, action: ReaderTapAction) {
        var actions = tapZoneActions
        guard actions.indices.contains(index) else { return }
        actions[index] = action
        if !actions.contains(.menu) {
            actions[4] = .menu
        }
        tapZonesRawValue = ReaderTapAction.encode(actions)
    }

    private func toggleCurrentBookmark(openList: Bool = true) {
        let paragraphIndex = currentBookmarkParagraphIndex
        let snippet = content.paragraphs.indices.contains(paragraphIndex)
            ? content.paragraphs[paragraphIndex]
            : content.title
        appState.bookshelfStore.toggleBookmark(
            bookID: bookID,
            chapterIndex: chapterIndex,
            chapterTitle: content.title,
            paragraphIndex: paragraphIndex,
            snippet: snippet
        )
        if openList {
            showBookmarks = true
        }
    }

    private var floatingSpeechCapsule: some View {
        HStack(spacing: 12) {
            Button {
                toggleSpeech()
            } label: {
                Image(systemName: speechController.isPaused ? "play.circle.fill" : "pause.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(AppTheme.accent)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: speechController.isPaused ? "speaker.slash" : "waveform")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppTheme.accent)
                    Text(speechController.isPaused ? "朗读已暂停" : "AI 语音朗读中")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary)
                }

                if speechController.currentParagraphIndex >= 0 && speechController.currentParagraphIndex < content.paragraphs.count {
                    Text(content.paragraphs[speechController.currentParagraphIndex])
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: 160, alignment: .leading)
                }
            }

            HStack(spacing: 8) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    speechController.skipPrevious()
                } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.primary.opacity(0.8))
                }
                .buttonStyle(.plain)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    speechController.skipNext()
                } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.primary.opacity(0.8))
                }
                .buttonStyle(.plain)

                Divider()
                    .frame(height: 14)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    stopSpeechPlayback()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 0.8))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.12), radius: 10, y: 5)
    }

    private var floatingAutoScrollCapsule: some View {
        HStack(spacing: 12) {
            Button {
                toggleAutoScroll()
            } label: {
                Image(systemName: autoScrollEnabled ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(AppTheme.accent)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppTheme.accent)
                    Text("自动滚屏中")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                Text(String(format: "%.1f 秒/屏", autoScrollDelay))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    autoScrollDelay = min(ReaderAutomationPolicy.maxDelay, autoScrollDelay + 0.5)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 12, weight: .bold))
                        .padding(4)
                        .background(Color.primary.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    autoScrollDelay = max(ReaderAutomationPolicy.minDelay, autoScrollDelay - 0.5)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .padding(4)
                        .background(Color.primary.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)

                Divider()
                    .frame(height: 14)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    toggleAutoScroll()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 0.8))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.12), radius: 10, y: 5)
    }

    private func toggleSpeech() {
        if speechController.isPaused {
            speechController.resume()
            playbackCoordinator.resumeSpeech()
            speechPausedForScene = false
        } else if speechController.isSpeaking {
            speechController.pause()
            playbackCoordinator.pauseSpeech()
        } else {
            beginSpeechPlayback()
        }
    }

    private func beginSpeechPlayback() {
        stopAutoScroll()
        let coordinator = playbackCoordinator
        let controller = speechController
        let progressStore = appState.bookshelfStore
        let currentBookID = bookID
        let currentChapterIndex = chapterIndex
        let currentChapterTitle = content.title
        let currentTotalChapters = totalChapters ?? 0
        let token = coordinator.beginSpeech()
        speechController.onFinished = { [onSpeechFinished] in
            Task { @MainActor in
                guard coordinator.accepts(token, for: .speech(generation: token)) else { return }
                // The speech controller clears its active index when the
                // queue drains, so persist the last completed paragraph before
                // handing the owner the next-chapter callback.
                let finishedParagraph = controller.lastFinishedParagraphIndex
                if finishedParagraph >= 0 {
                    progressStore.updateReadingProgress(
                        bookID: currentBookID,
                        chapterIndex: currentChapterIndex,
                        chapterTitle: currentChapterTitle,
                        totalChapters: currentTotalChapters,
                        paragraphIndex: finishedParagraph
                    )
                }
                coordinator.stop()
                if sleepTimerMinutes == -1 {
                    sleepTimerMinutes = 0
                    appState.record(DiagnosticEvent(level: .info, stage: "reader.sleepTimer", sourceName: currentChapterTitle, message: "睡眠定时已生效：当前章节播放完毕已自动停止"))
                    return
                }
                if let onSpeechFinished {
                    onSpeechFinished()
                } else if canSelectRelativeChapter(offset: 1) {
                    selectRelativeChapter(offset: 1)
                }
            }
        }
        speechPausedForScene = false
        // Scroll-mode visibility is updated by the native TextKit surface and
        // is throttled for performance. This is the latest known visible
        // paragraph (or the first paragraph on the current page), so speech
        // never restarts from chapter zero after a user scrolls.
        let startParagraph = currentParagraphIndexForPersistence()
        speechController.speak(
            title: content.title,
            paragraphs: content.paragraphs,
            startParagraphIndex: startParagraph,
            includeTitle: false,
            rate: Float(ttsRate),
            engine: TTSEngineKind(rawValue: ttsEngineRawValue) ?? .local,
            httpVoiceID: httpTTSVoiceID
        )
    }

    /// One exit path for every manual/navigation/lifecycle stop. Keeping the
    /// AVSpeech controller and the generation coordinator in sync prevents a
    /// late completion callback from reviving a newer reader session.
    private func stopSpeechPlayback() {
        speechController.stop()
        playbackCoordinator.stop()
        speechPausedForScene = false
    }

    private func toggleAutoScroll() {
        if autoScrollEnabled {
            stopAutoScroll()
        } else {
            stopSpeechPlayback()
            startAutoScroll()
        }
    }

    private func startAutoScroll() {
        stopAutoScroll()
        let currentTarget = ReaderAutomationPolicy.startingAutoScrollTarget(
            mode: readerMode,
            visibleParagraphIndex: visibleParagraphIndex,
            pagedPageIndex: pagedPageIndex,
            maximumTarget: maximumReaderTarget
        )
        let currentParagraph = positionMapping.paragraph(for: currentTarget, mode: readerMode)
        autoScrollAnchorTarget = currentTarget
        autoScrollAwaitingFirstTick = true
        visibleParagraphIndex = currentParagraph
        autoScrollEnabled = true
        // Starting playback is not a navigation request. Leave TextKit at the
        // current pixel offset; only the next tick issues a paragraph jump.
        let delay = ReaderAutomationPolicy.clampedDelay(autoScrollDelay)
        let coordinator = playbackCoordinator
        let token = coordinator.beginAutoScroll()
        autoScrollTask = Task { [weak coordinator] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let coordinator,
                          coordinator.accepts(token, for: .autoScroll(generation: token)),
                          autoScrollEnabled else { return }
                    switch ReaderAutomationPolicy.decision(
                        currentTarget: currentReaderTarget,
                        maximumTarget: maximumReaderTarget,
                        canAdvanceChapter: canSelectRelativeChapter(offset: 1)
                    ) {
                    case .advance(let target):
                        autoScrollAnchorTarget = target
                        autoScrollAwaitingFirstTick = false
                        if readerMode == .scroll {
                            scrollParagraphTarget = target
                            visibleParagraphIndex = target
                            paragraphJumpRequest = ParagraphJumpRequest(index: target)
                        } else {
                            pagedPageIndex = target
                            visibleParagraphIndex = positionMapping.paragraph(for: target, mode: readerMode)
                        }
                    case .nextChapter:
                        stopAutoScroll()
                        onAutoScrollFinished?()
                        selectRelativeChapter(offset: 1)
                    case .stop:
                        stopAutoScroll()
                    }
                }
            }
        }
    }

    private func stopAutoScroll(clearScenePause: Bool = true) {
        if clearScenePause {
            autoScrollPausedForScene = false
        }
        autoScrollEnabled = false
        autoScrollAwaitingFirstTick = false
        autoScrollTask?.cancel()
        autoScrollTask = nil
        if case .autoScroll = playbackCoordinator.mode {
            playbackCoordinator.stop()
        }
    }

    private func scheduleSleepTimer() {
        sleepTimerTask?.cancel()
        sleepTimerTask = nil
        guard sleepTimerMinutes > 0 else { return }
        let duration = UInt64(sleepTimerMinutes) * 60 * 1_000_000_000
        sleepTimerTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: duration)
            guard !Task.isCancelled else { return }
            stopAutoScroll()
            stopSpeechPlayback()
            sleepTimerMinutes = 0
            appState.record(DiagnosticEvent(level: .info, stage: "reader.sleepTimer", sourceName: content.title, message: "睡眠定时已结束"))
            sleepTimerTask = nil
        }
    }

    private func applyReaderBrightness() {
        guard readerBrightness >= 0 else {
            // "Follow system" must actually release the override. The old
            // early return left the screen stuck at the last manual value
            // until the reader was dismissed.
            if let brightnessBeforeReader {
                UIScreen.main.brightness = brightnessBeforeReader
            }
            return
        }
        UIScreen.main.brightness = CGFloat(min(max(readerBrightness, 0.05), 1.0))
    }

    private func applyIdleTimerPreference() {
        UIApplication.shared.isIdleTimerDisabled = keepScreenAwake
    }

    private func restoreIdleTimerPreference() {
        UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled
    }

    /// Receives throttled visibility updates from the TextKit reader surface.
    /// Keep this state write narrow so scrolling does not invalidate the full
    /// SwiftUI reader hierarchy on every display callback.
    private func updateVisibleParagraph(_ index: Int) {
        guard readerMode == .scroll,
              !autoScrollEnabled,
              content.paragraphs.indices.contains(index),
              index != visibleParagraphIndex else { return }
        visibleParagraphIndex = index
        scheduleReadingPositionPersistence(paragraphIndex: index)
    }

    private func initialAutoScrollTarget() -> (paragraph: Int, page: Int) {
        let paragraphIndex: Int
        if let initialParagraphIndex {
            paragraphIndex = initialParagraphIndex
        } else {
            guard let stored = appState.bookshelfStore.book(id: bookID),
                  stored.currentChapterIndex == chapterIndex,
                  let storedParagraphIndex = stored.currentParagraphIndex else {
                return (0, 0)
            }
            paragraphIndex = storedParagraphIndex
        }
        let safeParagraph = positionMapping.clampParagraph(paragraphIndex)
        visibleParagraphIndex = safeParagraph
        return (safeParagraph, positionMapping.page(containingParagraph: safeParagraph))
    }

    private func persistReadingPosition(paragraphIndexOverride: Int? = nil) {
        let saveChapterIndex: Int
        let saveChapterTitle: String
        let paragraphIndex: Int
        if readerMode == .scroll && !appendedSections.isEmpty {
            let resolved = resolvedReadingPosition(forFlatIndex: visibleParagraphIndex)
            saveChapterIndex = resolved.chapterIndex
            saveChapterTitle = resolved.chapterTitle
            paragraphIndex = paragraphIndexOverride ?? resolved.paragraphIndex
        } else {
            saveChapterIndex = chapterIndex
            saveChapterTitle = content.title
            if let paragraphIndexOverride {
                paragraphIndex = min(max(paragraphIndexOverride, 0), max(content.paragraphs.count - 1, 0))
            } else {
                paragraphIndex = currentParagraphIndexForPersistence()
            }
        }
        appState.bookshelfStore.updateReadingProgress(
            bookID: bookID,
            chapterIndex: saveChapterIndex,
            chapterTitle: saveChapterTitle,
            totalChapters: totalChapters ?? 0,
            paragraphIndex: paragraphIndex
        )
    }

    private func scheduleReadingPositionPersistence(paragraphIndex: Int) {
        positionPersistTask?.cancel()
        positionPersistTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: ReaderPerformancePolicy.positionPersistenceDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            persistReadingPosition(paragraphIndexOverride: paragraphIndex)
            checkDailyReadingGoal()
            positionPersistTask = nil
        }
    }

    private func checkDailyReadingGoal() {
        let todayKey = Date().formatted(date: .numeric, time: .omitted)
        guard lastGoalCelebratedDate != todayKey else { return }
        let goalSeconds = Double(dailyGoalMinutes) * 60.0
        guard goalSeconds > 0 else { return }
        let summary = ReadingStatsSummary(books: appState.bookshelfStore.books)
        let activeSeconds = Date().timeIntervalSince(sessionStartedAt)
        if (summary.todayReadingSeconds + activeSeconds) >= goalSeconds {
            lastGoalCelebratedDate = todayKey
            streakDaysCount = max(1, summary.streakDays)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                showGoalCelebrationToast = true
            }
            HapticFeedback.success()
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                withAnimation(.easeOut(duration: 0.3)) {
                    showGoalCelebrationToast = false
                }
            }
        }
    }

    private func currentParagraphIndexForPersistence() -> Int {
        guard !content.paragraphs.isEmpty else { return 0 }
        switch readerMode {
        case .scroll:
            if !appendedSections.isEmpty {
                let resolved = resolvedReadingPosition(forFlatIndex: visibleParagraphIndex)
                return resolved.paragraphIndex
            }
            return min(max(visibleParagraphIndex, 0), content.paragraphs.count - 1)
        case .pageTurn, .cover, .pageCurl:
            return paragraphIndex(forPage: pagedPageIndex)
        }
    }

    private func updatePagedVisibleParagraph(pageIndex: Int) {
        guard readerMode != .scroll, !content.paragraphs.isEmpty else { return }
        let paragraphIndex = paragraphIndex(forPage: pageIndex)
        guard paragraphIndex != visibleParagraphIndex else { return }
        visibleParagraphIndex = paragraphIndex
        scheduleReadingPositionPersistence(paragraphIndex: paragraphIndex)
    }

    private func paragraphIndex(forPage pageIndex: Int) -> Int {
        positionMapping.paragraph(forPage: pageIndex)
    }

    private func pageIndex(containingParagraph paragraphIndex: Int) -> Int {
        positionMapping.page(containingParagraph: paragraphIndex)
    }

    private func rebuildPagedBlocksCache() {
        let cacheKey = readerPageCacheKey
        let blocks = buildReaderPageBlocks()
        pagedBlocksCache = blocks
        pagedBlocksCacheKey = cacheKey
        positionMappingCache = ReaderPositionMapping(
            paragraphCount: content.paragraphs.count,
            pageFirstParagraphs: ReaderPositionMapping.pageStarts(
                from: blocks.map(\.firstParagraphIndex)
            )
        )
        pagedPageIndex = min(max(pagedPageIndex, 0), positionMappingCache.maximumPageIndex)
        scrollParagraphTarget = positionMappingCache.clampParagraph(scrollParagraphTarget)
        visibleParagraphIndex = positionMappingCache.clampParagraph(visibleParagraphIndex)
    }

    private func schedulePagedBlocksCacheRebuild() {
        guard readerMode != .scroll else { return }
        pageLayoutTask?.cancel()
        let expectedKey = readerPageCacheKey
        pageLayoutTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: ReaderPerformancePolicy.pageLayoutDebounceNanoseconds)
            guard !Task.isCancelled, readerPageCacheKey == expectedKey else { return }
            rebuildPagedBlocksCache()
            pagedPageIndex = min(max(pagedPageIndex, 0), positionMapping.maximumPageIndex)
            scheduleReadingPositionPersistence(paragraphIndex: currentParagraphIndexForPersistence())
            pageLayoutTask = nil
        }
    }

    private func buildReaderPageBlocks() -> [ReaderPageBlock] {
        let signpost = PerformanceSignpost.begin("reader.layout")
        defer { PerformanceSignpost.end("reader.layout", id: signpost) }
        guard !content.paragraphs.isEmpty else {
            return [ReaderPageBlock(id: 0, includesTitle: true, paragraphs: [])]
        }

        let topPadding = ReaderPageLayoutEngine.minimumTopInset(pagePadding: CGFloat(pagePadding))
        let bottomPadding = CGFloat(pagePadding) + CGFloat(footerHeight)
        let typography = ReaderPageTypography(
            font: fontFamily.uiFont(ofSize: CGFloat(fontSize)),
            titleFont: fontFamily.uiFont(ofSize: CGFloat(fontSize + 8), weight: .bold),
            lineSpacing: CGFloat(lineSpacing),
            letterSpacing: CGFloat(letterSpacing),
            paragraphSpacing: CGFloat(paragraphSpacing),
            firstLineIndent: CGFloat(paragraphIndent),
            titleSpacing: CGFloat(titleSpacing),
            contentWidth: max(effectiveViewportSize.width - CGFloat(pagePadding * 2), 200),
            // A 4pt cushion covers the tiny leading difference between
            // TextKit's line fragments and SwiftUI's Text renderer. Without it
            // the last descender of a page can be clipped by `.clipped()`.
            contentHeight: max(effectiveViewportSize.height - topPadding - bottomPadding - 4, 240)
        )
        var titleTypography = typography
        titleTypography.lineSpacing = 0
        titleTypography.letterSpacing = 0

        var pages: [ReaderPageBlock] = []
        var currentEntries: [ReaderPageEntry] = []
        var currentHeight = ReaderPageLayoutEngine.measureHeight(
            content.title,
            typography: titleTypography,
            font: typography.titleFont
        ) + typography.titleSpacing
        var currentIncludesTitle = true

        func flush() {
            pages.append(
                ReaderPageBlock(
                    id: pages.count,
                    includesTitle: currentIncludesTitle,
                    paragraphs: currentEntries
                )
            )
            currentEntries = []
            currentHeight = 0
            currentIncludesTitle = false
        }

        for (index, paragraph) in content.paragraphs.enumerated() {
            let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            if ReaderImageSizingPolicy.imageURL(in: trimmed) != nil {
                // `ReaderIllustrationView` also draws the caption row and its
                // vertical padding. Reserving only the bitmap height let a
                // text-plus-image page overflow and clip the last line.
                let captionBudget = ReaderImageSizingPolicy.pagedCaptionHeight
                let imageHeight = min(
                    ReaderImageSizingPolicy.maximumHeight(
                        for: currentImageStyle,
                        viewportHeight: effectiveViewportSize.height,
                        pagePadding: pagePadding,
                        footerHeight: footerHeight
                    ),
                    max(typography.contentHeight - captionBudget, 1)
                )
                let cardHeight = imageHeight + captionBudget
                if currentImageStyle.reservesWholePage {
                    if currentIncludesTitle || !currentEntries.isEmpty {
                        flush()
                    }
                    currentEntries.append(ReaderPageEntry(index: index, text: paragraph))
                    currentHeight = cardHeight
                    flush()
                } else {
                    let spacing = currentEntries.isEmpty ? 0 : typography.paragraphSpacing
                    if !currentEntries.isEmpty && currentHeight + spacing + cardHeight > typography.contentHeight {
                        flush()
                    }
                    let spacingAfterFlush = currentEntries.isEmpty ? 0 : typography.paragraphSpacing
                    currentEntries.append(ReaderPageEntry(index: index, text: paragraph))
                    currentHeight += spacingAfterFlush + cardHeight
                    if currentHeight >= typography.contentHeight {
                        flush()
                    }
                }
                continue
            }

            // The stored page text includes the first-line indent so the paged
            // surface and TextKit measure exactly the same string.  Continuation
            // chunks start at a line boundary and therefore carry no indent.
            let display = ReaderPageLayoutEngine.displayText(
                paragraph,
                fontSize: CGFloat(fontSize),
                indent: typography.firstLineIndent
            )
            let wholeHeight = ReaderPageLayoutEngine.measureHeight(display, typography: typography)
            let spacing = currentEntries.isEmpty ? 0 : typography.paragraphSpacing

            if currentHeight + spacing + wholeHeight <= typography.contentHeight + 0.5 {
                currentEntries.append(ReaderPageEntry(index: index, text: display))
                currentHeight += spacing + wholeHeight
                continue
            }

            let remaining = typography.contentHeight - currentHeight - spacing
            if !currentEntries.isEmpty, remaining < typography.contentHeight * 0.28 {
                flush()
            } else if currentEntries.isEmpty, currentIncludesTitle,
                      remaining < typography.contentHeight * 0.28 {
                flush()
            }

            let available: CGFloat
            if currentEntries.isEmpty {
                available = max(typography.contentHeight - currentHeight, typography.contentHeight * 0.28)
            } else {
                available = max(
                    typography.contentHeight - currentHeight - typography.paragraphSpacing,
                    typography.contentHeight * 0.28
                )
            }
            let chunks = ReaderPageLayoutEngine.split(
                display,
                firstPageHeight: available,
                fullPageHeight: typography.contentHeight,
                typography: typography
            )
            for (chunkIndex, chunk) in chunks.enumerated() {
                let spacingBefore = currentEntries.isEmpty
                    ? 0
                    : (chunkIndex == 0 ? typography.paragraphSpacing : 0)
                if !currentEntries.isEmpty,
                   currentHeight + spacingBefore + chunk.height > typography.contentHeight + 0.5 {
                    flush()
                }
                let spacingAfterFlush = currentEntries.isEmpty
                    ? 0
                    : (chunkIndex == 0 ? typography.paragraphSpacing : 0)
                currentEntries.append(
                    ReaderPageEntry(index: index, text: chunk.text, chunkIndex: chunkIndex)
                )
                currentHeight += spacingAfterFlush + chunk.height
                if chunkIndex < chunks.count - 1 {
                    flush()
                }
            }
        }

        if currentIncludesTitle || !currentEntries.isEmpty {
            flush()
        }
        return pages
    }
}

private struct ReaderViewportSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let candidate = nextValue()
        if candidate.width > 1, candidate.height > 1 {
            value = candidate
        }
    }

}

private extension View {
    @ViewBuilder
    func readerSheetPresentation(color: Color = .clear) -> some View {
        if #available(iOS 16.4, *) {
            self.presentationBackground(color)
        } else {
            self
        }
    }
}

private struct ParagraphJumpRequest: Equatable {
    let id = UUID()
    let index: Int
}

struct ReaderPageEntry: Equatable, Identifiable {
    let index: Int
    let text: String
    /// Non-zero when a long paragraph was split across page boundaries.
    var chunkIndex: Int = 0
    var isContinuation: Bool { chunkIndex > 0 }
    var id: String { "\(index)-\(chunkIndex)" }
}

struct ReaderPageBlock: Identifiable, Equatable {
    let id: Int
    let includesTitle: Bool
    let paragraphs: [ReaderPageEntry]

    var firstParagraphIndex: Int? {
        paragraphs.first?.index
    }

    var lastParagraphIndex: Int? {
        paragraphs.last?.index
    }
}

private extension View {
    @ViewBuilder
    func readerSelectableText(_ enabled: Bool) -> some View {
        if enabled {
            textSelection(.enabled)
        } else {
            self
        }
    }
}

final class ReaderSpeechController: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var isSpeaking = false
    @Published var isPaused = false
    @Published var currentParagraphIndex = -1
    /// Last non-title paragraph whose utterance completed. The owner uses it
    /// to persist the final reading position before handing off chapters.
    @Published private(set) var lastFinishedParagraphIndex = -1

    private let synthesizer = AVSpeechSynthesizer()
    private var queue = ReaderSpeechQueue()
    private var rate: Float = 0.52
    private var activeUtterance: AVSpeechUtterance?
    private var currentTitle: String = ""
    private var remoteCommandsConfigured = false
    private let cloudCredentialsStore = CloudTTSCredentialsStore()
    private let cloudClient = CloudTTSClient()
    private let cloudPlayer = CloudTTSPlayer()
    private let httpClient = HttpTTSClient()
    private var httpVoice: HttpTTSVoice = HttpTTSVoice.defaultVoices.first
        ?? HttpTTSVoice(id: HttpTTSVoice.defaultVoiceID, name: "默认语音", url: "")
    private var cloudTask: Task<Void, Never>?
    private var cloudGeneration = 0
    private var engineKind: TTSEngineKind = .local
    private var activeSegment: (index: Int, text: String)?
    private var usesRemoteAudioPlayback: Bool {
        engineKind == .cloud || engineKind == .http
    }
    @Published var lastErrorMessage: String?
    var onFinished: (() -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
        cloudPlayer.onFinish = { [weak self] in
            Task { @MainActor in
                self?.handleCloudSegmentFinished()
            }
        }
        cloudPlayer.onError = { [weak self] error in
            Task { @MainActor in
                self?.handleCloudPlaybackError(error)
            }
        }
        setupAudioInterruptionObserver()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        teardownRemoteCommands()
    }

    func speak(
        title: String,
        paragraphs: [String],
        startParagraphIndex: Int = 0,
        includeTitle: Bool = true,
        rate: Float,
        engine: TTSEngineKind = .local,
        httpVoiceID: Int? = nil
    ) {
        stop(clearCompletion: false)
        if let httpVoiceID,
           let selected = HttpTTSVoice.defaultVoices.first(where: { $0.id == httpVoiceID }) {
            httpVoice = selected
        }
        var resolvedEngine = engine
        if resolvedEngine == .cloud && !cloudCredentialsStore.isConfigured {
            lastErrorMessage = "未配置讯飞云端语音凭据，已回退系统语音"
            resolvedEngine = .local
        }
        engineKind = resolvedEngine
        queue.reset(
            title: title,
            paragraphs: paragraphs,
            startParagraphIndex: startParagraphIndex,
            includeTitle: includeTitle
        )
        self.rate = rate
        self.currentTitle = title
        setupRemoteCommands()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true, options: [])
        isSpeaking = true
        isPaused = false
        lastFinishedParagraphIndex = -1
        speakNext()
    }

    func pause() {
        guard isSpeaking else { return }
        if usesRemoteAudioPlayback {
            cloudPlayer.pause()
            isPaused = true
            updateNowPlayingInfo()
            return
        }
        synthesizer.pauseSpeaking(at: .word)
        isPaused = true
        updateNowPlayingInfo()
    }

    func resume() {
        guard isSpeaking else { return }
        if usesRemoteAudioPlayback {
            cloudPlayer.resume()
            isPaused = false
            updateNowPlayingInfo()
            return
        }
        if synthesizer.isPaused {
            synthesizer.continueSpeaking()
        }
        isPaused = false
        updateNowPlayingInfo()
    }

    func stop() {
        stop(clearCompletion: true)
    }

    func skipNext() {
        guard isSpeaking else { return }
        if usesRemoteAudioPlayback {
            cancelCloudPlayback()
            activeSegment = nil
            speakNext()
            return
        }
        synthesizer.stopSpeaking(at: .immediate)
        activeUtterance = nil
        speakNext()
    }

    func skipPrevious() {
        guard isSpeaking else { return }
        if usesRemoteAudioPlayback {
            cancelCloudPlayback()
            activeSegment = nil
            guard let segment = queue.stepBack() else {
                speakNext()
                return
            }
            playSegment(segment)
            return
        }
        synthesizer.stopSpeaking(at: .immediate)
        activeUtterance = nil
        guard let segment = queue.stepBack() else {
            speakNext()
            return
        }
        playSegment(segment)
    }

    private func stop(clearCompletion: Bool) {
        cancelCloudPlayback()
        activeSegment = nil
        lastErrorMessage = nil
        synthesizer.stopSpeaking(at: .immediate)
        activeUtterance = nil
        if clearCompletion {
            onFinished = nil
        }
        isSpeaking = false
        isPaused = false
        currentParagraphIndex = -1
        lastFinishedParagraphIndex = -1
        queue.clear()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func speakNext() {
        guard let segment = queue.dequeue() else {
            let completion = onFinished
            onFinished = nil
            synthesizer.stopSpeaking(at: .immediate)
            cloudPlayer.stop()
            activeSegment = nil
            isSpeaking = false
            isPaused = false
            currentParagraphIndex = -1
            queue.clear()
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            completion?()
            return
        }
        playSegment(segment)
    }

    private func playSegment(_ segment: (index: Int, text: String)) {
        if segment.text.hasPrefix("[img]") && segment.text.hasSuffix("[/img]") {
            speakNext()
            return
        }
        currentParagraphIndex = segment.index
        activeSegment = segment
        if engineKind == .cloud {
            playCloudSegment(segment)
            return
        }
        if engineKind == .http {
            playHTTPVoiceSegment(segment)
            return
        }
        let utterance = AVSpeechUtterance(string: segment.text)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = rate
        activeUtterance = utterance
        synthesizer.speak(utterance)
        updateNowPlayingInfo()
    }

    private func cancelCloudPlayback() {
        cloudGeneration += 1
        cloudTask?.cancel()
        cloudTask = nil
        cloudPlayer.stop()
    }

    private func playCloudSegment(_ segment: (index: Int, text: String)) {
        guard let credentials = cloudCredentialsStore.load(), credentials.isConfigured else {
            lastErrorMessage = "未配置讯飞云端语音凭据，已回退系统语音"
            engineKind = .local
            playSegment(segment)
            return
        }
        cancelCloudPlayback()
        let generation = cloudGeneration
        updateNowPlayingInfo()
        cloudTask = Task { [weak self] in
            guard let self else { return }
            do {
                let audio = try await self.cloudClient.synthesize(text: segment.text, credentials: credentials)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard self.cloudGeneration == generation, self.isSpeaking else { return }
                    do {
                        try self.cloudPlayer.play(data: audio)
                        if self.isPaused {
                            self.cloudPlayer.pause()
                        }
                    } catch {
                        self.handleCloudFailure(error, generation: generation)
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.handleCloudFailure(error, generation: generation)
                }
            }
        }
    }

    private func playHTTPVoiceSegment(_ segment: (index: Int, text: String)) {
        cancelCloudPlayback()
        let generation = cloudGeneration
        updateNowPlayingInfo()
        let voice = httpVoice
        let speed = min(max(Int((rate * 10).rounded()), 0), 10)
        cloudTask = Task { [weak self] in
            guard let self else { return }
            do {
                let audio = try await self.httpClient.synthesize(
                    voice: voice,
                    text: segment.text,
                    speed: speed
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard self.cloudGeneration == generation, self.isSpeaking else { return }
                    do {
                        try self.cloudPlayer.play(data: audio)
                        if self.isPaused {
                            self.cloudPlayer.pause()
                        }
                    } catch {
                        self.handleCloudFailure(error, generation: generation)
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.handleCloudFailure(error, generation: generation)
                }
            }
        }
    }

    private func handleCloudSegmentFinished() {
        guard isSpeaking, usesRemoteAudioPlayback else { return }
        if let index = activeSegment?.index, index >= 0 {
            lastFinishedParagraphIndex = index
        }
        activeSegment = nil
        speakNext()
    }

    private func handleCloudPlaybackError(_ error: Error) {
        guard isSpeaking, usesRemoteAudioPlayback else { return }
        handleCloudFailure(error, generation: cloudGeneration)
    }

    private func handleCloudFailure(_ error: Error, generation: Int) {
        guard generation == cloudGeneration, isSpeaking else { return }
        cloudPlayer.stop()
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        lastErrorMessage = "云端语音不可用，已回退系统语音：\(message)"
        engineKind = .local
        if let segment = activeSegment {
            playSegment(segment)
        } else {
            speakNext()
        }
    }

    private func updateNowPlayingInfo() {
        var info = [String: Any]()
        info[MPMediaItemPropertyTitle] = currentTitle.isEmpty ? "正文朗读" : currentTitle
        info[MPMediaItemPropertyArtist] = "纸间语音朗读"
        info[MPMediaItemPropertyAlbumTitle] = "纸间 (SourceRead)"
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPaused ? 0.0 : (isSpeaking ? 1.0 : 0.0)
        let total = queue.totalSegments
        let current = queue.currentSegmentPosition
        if total > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = Double(total)
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = Double(max(current - 1, 0))
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func setupRemoteCommands() {
        guard !remoteCommandsConfigured else { return }
        remoteCommandsConfigured = true
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.resume()
            }
            return .success
        }

        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pause()
            }
            return .success
        }

        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.isPaused {
                    self.resume()
                } else if self.isSpeaking {
                    self.pause()
                }
            }
            return .success
        }

        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.skipNext()
            }
            return .success
        }

        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.skipPrevious()
            }
            return .success
        }
    }

    private func teardownRemoteCommands() {
        guard remoteCommandsConfigured else { return }
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        commandCenter.nextTrackCommand.removeTarget(nil)
        commandCenter.previousTrackCommand.removeTarget(nil)
        remoteCommandsConfigured = false
    }

    private func setupAudioInterruptionObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    @objc private func handleAudioInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            switch type {
            case .began:
                if self.isSpeaking && !self.isPaused {
                    self.pause()
                }
            case .ended:
                if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                    let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                    if options.contains(.shouldResume) && self.isSpeaking && self.isPaused {
                        self.resume()
                    }
                }
            @unknown default:
                break
            }
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self, self.isSpeaking, self.activeUtterance === utterance else { return }
            self.lastFinishedParagraphIndex = self.currentParagraphIndex
            self.activeUtterance = nil
            self.speakNext()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self, self.activeUtterance === utterance else { return }
            self.activeUtterance = nil
            self.isSpeaking = false
            self.isPaused = false
            self.currentParagraphIndex = -1
            self.queue.clear()
            self.onFinished = nil
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        }
    }
}

private struct IdentifiableReaderURL: Identifiable {
    var id: String { url.absoluteString }
    let url: URL
}

private struct IllustrationZoomViewer: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL
    let headers: [String: String]
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                CachedRemoteImage(url: url, headers: headers) {
                    ProgressView()
                        .tint(.white)
                }
                .scaledToFit()
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = max(lastScale * value, 1.0)
                        }
                        .onEnded { _ in
                            lastScale = scale
                            if scale <= 1.0 {
                                offset = .zero
                                lastOffset = .zero
                            }
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            if scale > 1.0 {
                                offset = CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                )
                            }
                        }
                        .onEnded { _ in
                            if scale > 1.0 {
                                lastOffset = offset
                            }
                        }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.spring()) {
                        if scale > 1.0 {
                            scale = 1.0
                            lastScale = 1.0
                            offset = .zero
                            lastOffset = .zero
                        } else {
                            scale = 2.5
                            lastScale = 2.5
                        }
                    }
                }
            }
            .navigationTitle("插图查看")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(.white)
                    }
                }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

struct ReaderIllustrationView: View {
    let url: URL
    let style: ReaderImageStyle
    let headers: [String: String]
    let textColor: Color
    var columnWidth: CGFloat = 320
    var maximumHeight: CGFloat = 520

    /// Natural pixel size reported by the decoded bitmap. Until it arrives the
    /// placeholder defines the footprint; afterwards the shared sizing policy
    /// keeps paged SwiftUI geometry identical to the TextKit scroll surface.
    @State private var naturalSize: CGSize = .zero

    private var displaySize: CGSize {
        guard naturalSize.width > 0, naturalSize.height > 0 else { return .zero }
        return ReaderImageSizingPolicy.size(
            for: naturalSize,
            style: style,
            containerWidth: columnWidth,
            maximumHeight: maximumHeight
        )
    }

    private var placeholderSize: CGSize {
        let width = style.stretchesToColumnWidth ? columnWidth : min(columnWidth, 260)
        let height = style.stretchesToColumnWidth
            ? min(width * 0.6, maximumHeight)
            : min(max(width * 0.62, 120), 200)
        return CGSize(width: max(width, 1), height: max(height, 1))
    }

    var body: some View {
        VStack(spacing: 8) {
            CachedRemoteImage(
                url: url,
                contentMode: .fit,
                headers: headers,
                onSizeChange: { size in
                    guard size.width > 0, size.height > 0 else { return }
                    if abs(size.width - naturalSize.width) > 0.5
                        || abs(size.height - naturalSize.height) > 0.5 {
                        naturalSize = size
                    }
                }
            ) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(textColor.opacity(0.06))
                    .frame(width: placeholderSize.width, height: placeholderSize.height)
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "photo")
                                .font(.title2)
                                .foregroundStyle(textColor.opacity(0.4))
                            Text("加载插图中...")
                                .font(.caption)
                                .foregroundStyle(textColor.opacity(0.4))
                        }
                    }
            }
            .frame(
                width: displaySize.width > 0 ? displaySize.width : nil,
                height: displaySize.height > 0 ? displaySize.height : nil
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(textColor.opacity(0.12), lineWidth: 0.8)
            }

            HStack(spacing: 4) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10))
                Text("点击查看插图大图")
                    .font(.system(size: 11))
            }
            .foregroundStyle(textColor.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}
