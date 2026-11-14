import AVFoundation
import MediaPlayer
import PhotosUI
import SwiftUI
import UIKit

struct ReaderView: View {
    @EnvironmentObject private var appState: AppState
    @AppMotion private var motion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.readerTemporaryCoverPresented) private var temporaryCoverPresented
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
    var onCacheNextChapters: ((Int) -> Void)?
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
    var onPreviewPosition: ((ReaderPreviewPosition) -> Void)? = nil
    var onRequestExit: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.readerOpeningManaged) private var readerOpeningManaged
    @Environment(\.readerUsesBookReturn) private var readerUsesBookReturn
    @Environment(\.nativeReaderSession) private var nativeSession
    @Environment(\.readerNavigationIsTransitioning) private var navigationIsTransitioning
    @State private var hasInitializedNativePresentation = false
    @State private var hasResolvedOpeningPreview = false
    @State private var runtimeCoordinators = ReaderRuntimeCoordinators()
    @State private var speechHighlightToken = ""
    @State private var asyncPaginationTask: Task<Void, Never>?
    @State private var asyncPaginationGeneration = 0
    @State private var nativeMoreMenuPresentation = ReaderMenuPresentation()
    @State private var readerSessionEnded = false
    @State private var showChapterList = false
    @State private var showBookmarks = false
    @State private var showBookDetailSheet = false
    @State private var showContentFilter = false
    @State private var inBookSearchQuery = ""
    @State private var inBookSearchHits: [ReaderInBookSearchHit] = []
    @State private var inBookSearchScannedCount = 0
    @State private var inBookSearchTask: Task<Void, Never>? = nil
    @State private var recapSeedForAI: AIChatRecapSeed? = nil
    @State private var bookmarkExportURL: IdentifiableURL? = nil
    @State private var bookmarkExportError: String? = nil
    @State private var tocScrollTask: Task<Void, Never>?
    @State private var tocUserHasScrolled = false
    @State private var tocScrollIntent = ReaderTocScrollIntent.currentChapter
    /// Per-source login surface.  Sources that gate chapters behind an account
    /// previously had no entry point inside the reader, so the only way to
    /// authenticate was the source manager's long-press menu.
    @State private var readerLoginSource: BookSource?
    @State private var showChapterWebPage = false
    @State private var showPayActionConfirmation = false
    @State private var payActionResultMessage = ""
    @State private var showPayActionResult = false
    @State private var isPerformingPayAction = false
    @State private var quoteCardBookmark: ReaderBookmark? = nil
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var wallpaperDraft: ReaderWallpaperDraft?
    @State private var wallpaperImportTask: Task<Void, Never>?
    @State private var wallpaperImportRevision = UUID()
    @State private var isPreparingWallpaper = false
    @State private var wallpaperMessage: String?
    @State private var confirmClearWallpaper = false
    @State private var backgroundWallpaperRevision = UUID()
    @AppStorage("reader.atelierEnabled") private var usesAtelier = true
    @AppStorage("reader.bindingRevision") private var bindingRevision = ""
    @AppStorage("reader.chapterDecoration") private var chapterDecorationRaw = ReaderChapterDecoration.none.rawValue
    @AppStorage("reader.chapterAlignment") private var chapterAlignmentRaw = ReaderChapterAlignment.leading.rawValue
    @AppStorage("reader.menuPaperOpacity") private var menuPaperOpacity = 0.97
    @AppStorage("reader.menuUsesWallpaper") private var menuUsesWallpaper = false
    @AppStorage("reader.menuSurfaceStyle") private var menuSurfaceStyle = "system"

    private var chromeCoordinator: ReaderChromeCoordinator { runtimeCoordinators.chrome }
    private var sleepTimerCoordinator: ReaderSleepTimerCoordinator { runtimeCoordinators.sleepTimer }
    private var goalCelebrationCoordinator: ReaderGoalCelebrationCoordinator { runtimeCoordinators.goalCelebration }
    private var speechController: ReaderSpeechController { runtimeCoordinators.speech }
    private var showOverlay: Bool { chromeCoordinator.state.isOverlayVisible }
    private var showSettings: Bool { chromeCoordinator.state.isSettingsVisible }
    private var settingsTab: Int { chromeCoordinator.settingsTab }
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
    @State private var tapPageTurnRequest: ReaderPageTurnRequest?
    @State private var autoScrollTask: Task<Void, Never>?
    @State private var sleepTimerTask: Task<Void, Never>?
    @State private var positionPersistScheduler = ReaderPositionPersistScheduler()
    @State private var pageLayoutTask: Task<Void, Never>?
    /// Chapters wait in this queue instead of all hitting the source at once.
    /// Nearest-first, one at a time: a distant prefetch can never finish ahead
    /// of the chapter the reader is about to cross into.
    @State private var prefetchState = ReaderPrefetchState()
    @State private var backgroundChapterPrecache = ReaderBackgroundChapterPrecache()
    @State private var paginationWarmupTask: Task<Void, Never>?
    @State private var paginationWarmupGeneration = 0
    // Prefetch bookkeeping lives in `prefetchState`; writing it in `@State`
    // invalidated the reader while a fling was in flight.
    @State private var paragraphJumpRequest: ParagraphJumpRequest?
    @State private var pagedBlocksCache: [ReaderPageBlock] = []
    @State private var pagedBlocksCacheKey = ""
    @State private var interactionGate = ReaderInteractionGate()
    @State private var pageTextCache = ReaderPageTextCache()
    /// A cache rebuild that arrived while the finger was still on a page.
    /// Dropping it left the visible slot on its placeholder until the next
    /// chapter was measured - the one-beat stall between pages.
    @State private var paginationRebuildPending = false
    @State private var tocFilterCache = ReaderTocFilterCache()
    @State private var pageIdentityTracker = ReaderVisiblePageTracker()
    /// 页面容器的真实几何（UIPageViewController 子控制器可能比根视图小一圈）。
    /// 分页引擎使用这一份，而不是盲目相信根视图的 viewport。
    @State private var pagedPageContainerMetrics: ReaderPageContainerMetrics?
    /// Page-to-paragraph mapping is immutable between layout-cache revisions.
    /// Keep it in state instead of rebuilding an array with `compactMap` every
    /// time SwiftUI reevaluates the reader body or a speech callback arrives.
    @State private var positionMappingCache = ReaderPositionMapping(paragraphCount: 0)
    /// The reader may live in a split view or Stage Manager window. Keep the
    /// actual container size instead of using UIScreen.main, which describes
    /// the physical display and can be stale for the current scene.
    @State private var viewportSize: CGSize = .zero
    @State private var measuredSafeInsets = ReaderSafeAreaResolver.Insets(top: 0, bottom: 0)
    @State private var foregroundReading = ForegroundReadingSession()
    @State private var isReaderVisible = false
    @State private var previousIdleTimerDisabled = false
    @State private var committedParagraphIndex = 0
    @State private var scrollPositionTracker = ReaderScrollPositionTracker()
    private var visibleParagraphIndex: Int {
        get { scrollPositionTracker.visibleIndex ?? committedParagraphIndex }
        nonmutating set {
            scrollPositionTracker.visibleIndex = nil
            if committedParagraphIndex != newValue { committedParagraphIndex = newValue }
        }
    }
    @State private var readerContentFingerprint = ""
    /// Fingerprint of the content this reader was seeded with. A parked
    /// reader keeps its live window after crossing chapters, so the owner
    /// re-presenting its launch snapshot must not be treated as new content;
    /// the launch chapter may already have been trimmed out of the window.
    @State private var seededContentFingerprint = ""
    @State private var windowSections: [ReaderChapterSection] = []
    @State private var windowCurrentChapterIndex = 0
    /// A TOC / bookmark / slider jump whose chapter is still downloading.
    @State private var pendingWindowJump: ReaderPendingChapterJump?
    @State private var chapterJumpTask: Task<Void, Never>?
    @State private var chapterJumpRequestID = UUID()
    @State private var readerPresentationLifecycle = ReaderPresentationLifecycle()
    @State private var windowLoadingIndices: Set<Int> = []
    /// Last failure per chapter. Placeholders and the scroll boundary banner
    /// read this map, so a source timeout is visible instead of looking like
    /// the book simply ended.
    @State private var windowFailures: [Int: String] = [:]
    @State private var windowRetryAttempts: [Int: Int] = [:]
    @State private var windowRetryTasks: [Int: Task<Void, Never>] = [:]
    @State private var windowGeneration = 0
    @State private var isWindowSeeded = false
    /// Pagination is immutable per chapter and typography. Rebuilding the whole
    /// five-chapter window every time a neighbour arrives used to re-measure
    /// every paragraph and made a prefetch look like a frozen reader. Keep
    /// chapter-local blocks and renumber them when assembling the window.
    @State private var chapterPageCache: [Int: ReaderChapterPageCacheEntry] = [:]
    @State private var chapterPageCacheSignature = ""
    /// The measured page container lands one frame after `onAppear`; until it
    /// stops moving, chapters outside the cursor's neighbours stay cheap
    /// placeholders instead of being measured twice (fallback viewport first,
    /// real container second). That double pass was the pause on
    /// "正在加载下一章" for chapters the local book already had in memory.
    @State private var chapterGeometrySettled = false
    @State private var geometrySettleTask: Task<Void, Never>?
    @State private var paginationWarmupRestartTask: Task<Void, Never>?
    @State private var paginationWarmupPending = false
    @State private var chapterPageCounts: [Int: Int] = [:]
    /// Increments whenever a window mutation moves the visible paragraph in
    /// the flat index space (a chapter was inserted or trimmed above the
    /// viewport). The native surface consumes the absolute anchor once per
    /// revision, which is immune to SwiftUI coalescing several mutations into
    /// one update.
    @State private var layoutAnchorRevision = 0
    @State private var layoutAnchorOldParagraph = 0
    @State private var lastWindowChangeWasAppend = false
    /// A playback handoff that is waiting for the next chapter to finish
    /// downloading. The window resumes the same reader surface when the
    /// section arrives instead of asking the owner to rebuild the chapter.
    @State private var pendingSpeechChapterIndex: Int?
    @State private var pendingAutoScrollChapterIndex: Int?
    /// Chapter the speech queue was started from. The controller reports a
    /// chapter-local paragraph index; keeping the chapter here lets every
    /// highlight/page/target map it back into the window's flat space.
    @State private var speechChapterIndex = 0
    @State private var speechPausedForScene = false
    @State private var autoScrollPausedForScene = false
    @State private var scrollJumpGeneration = 0
    @State private var chapterSliderTarget: Double? = nil
    /// 拖动章节进度条时的实时跳章任务。手指还在滑就不停重排，
    /// 停住 0.12s 才真正跳，避免一次拖动里塞进十几个章节加载。
    @State private var chapterSeekTask: Task<Void, Never>? = nil
    /// 首帧是否已经落到「上次读到的那一段」。
    @State private var didLandInitialPosition = false
    @State private var hasPreparedOpeningPosition = false
    private final class ReaderTapGestureTracker {
        var startedAt: Date?
    }
    @State private var tapGestureTracker = ReaderTapGestureTracker()
    /// 一次点击只处理一次。paged 模式里快照页容器与 SwiftUI 手势可能在同一帧
    /// 各报一次，用户看到的就是「点一下跳了两页」。
    @State private var tapCooldownUntil: Date = .distantPast
    @AppStorage("reader.customBackgroundIsDark") private var customBackgroundIsDark: Bool = false
    @State private var pageStepDirection: Int = 0
    @State private var pageStepGeneration: Int = 0
    @State private var brightnessBeforeReader: CGFloat? = nil
    @StateObject private var playbackCoordinator = ReaderPlaybackCoordinator()
    @AppStorage("reader.fontFamily") private var fontFamilyRawValue: String = ReaderFontFamily.system.rawValue
    @AppStorage("reader.customFontPostScriptName") private var customFontPostScriptName: String = ""
    @AppStorage("reader.fontSize") private var fontSize: Double = ReaderTypographyDefaults.fontSize
    @AppStorage("reader.lineSpacing") private var lineSpacing: Double = ReaderTypographyDefaults.lineSpacing
    @AppStorage("reader.pagePadding") private var pagePadding: Double = ReaderTypographyDefaults.pagePadding
    // 页脚三件套各自可关（对照香色闺阁 tr_showTime / tr_showBatView / tr_showBatLabel）。
    @AppStorage("reader.footerShowTime") private var footerShowTime = true
    @AppStorage("reader.footerShowBatteryIcon") private var footerShowBatteryIcon = true
    @AppStorage("reader.footerShowBatteryPercent") private var footerShowBatteryPercent = true
    @AppStorage("reader.showSystemStatusBar") private var showSystemStatusBar = false
    @AppStorage("reader.statusPosition") private var statusPosition = "bottom"
    @State private var showFontManagementSheet = false
    @AppStorage("reader.letterSpacing") private var letterSpacing: Double = ReaderTypographyDefaults.letterSpacing
    @AppStorage("reader.paragraphSpacing") private var paragraphSpacing: Double = ReaderTypographyDefaults.paragraphSpacing
    @AppStorage("reader.paragraphIndent") private var paragraphIndent: Double = ReaderTypographyDefaults.paragraphIndent
    @AppStorage("reader.chapterTitleSize") private var chapterTitleSize = 0.0
    @AppStorage("reader.chapterTitleBold") private var chapterTitleBold = true
    @AppStorage("reader.chapterTitleFamily") private var chapterTitleFamilyRaw = ""
    @AppStorage("reader.headerFontSize") private var headerFontSize = 12.0
    @AppStorage("reader.headerTopGap") private var headerTopGap = 2.0
    @AppStorage("reader.headerOpacity") private var headerOpacity = 0.82
    @AppStorage("reader.allowsDuplicateTopStatus") private var allowsDuplicateTopStatus = false
    @AppStorage("reader.titleSpacing") private var titleSpacing: Double = ReaderTypographyDefaults.titleSpacing
    /// One-shot migration for the 1.0.64 defaults (`paragraphSpacing = 0`,
    /// `titleSpacing = 8`). A value the reader already customised is kept.
    @AppStorage("reader.typographyMigrated.v65") private var typographyMigratedV65 = false
    /// Second pass for the spacing ratio: 1.0.65 shipped 12 / 10, which still
    /// left paragraphs closer than the line gap. Only the exact old defaults
    /// are rewritten; a manually tuned value is kept.
    @AppStorage("reader.typographyMigrated.v66") private var typographyMigratedV66 = false
    @AppStorage("reader.footerHeight") private var footerHeight: Double = ReaderTypographyDefaults.footerHeight
    /// 章节标题呈现方式。默认「页眉小标题」：每页顶部 12pt 章节名，正文从页眉下开始，
    /// 与栖阅 / 开元阅读的阅读页一致。
    @AppStorage("reader.chapterHeadingStyle") private var chapterHeadingStyleRaw = ReaderPageChromeLayout.header.rawValue
    /// 栖阅的「内容延伸至页眉页脚区域」：开启后正文跨过页眉页脚带，页眉页脚浮在正文上。
    @AppStorage("reader.contentExtendsIntoChrome") private var contentExtendsIntoChrome = false
    @AppStorage("reader.ttsRate") private var ttsRate: Double = 0.52
    @AppStorage("reader.ttsEngine") private var ttsEngineRawValue: String = TTSEngineKind.local.rawValue
    @AppStorage("reader.httpTTSVoiceID") private var httpTTSVoiceID: Int = HttpTTSVoice.defaultVoiceID
    @AppStorage("reader.autoScrollDelay") private var autoScrollDelay: Double = 2.0
    @AppStorage("reader.sleepTimerMinutes") private var sleepTimerMinutes: Int = 0
    @AppStorage("reader.volumeKeyPageTurn") private var volumeKeyPageTurn = false
    @AppStorage("reader.ambientSoundEnabled") private var ambientSoundEnabled = false
    @AppStorage("reader.ambientSoundPreset") private var ambientSoundPresetRaw = ReaderAmbientPreset.auto.rawValue
    @AppStorage("reader.ambientSoundVolume") private var ambientSoundVolume: Double = 0.35
    @AppStorage("reader.ambientTimerMinutes") private var ambientTimerMinutes: Int = 0
    @AppStorage("reader.background") private var backgroundRawValue: String = ReaderBackground.white.rawValue
    /// 壁纸填充方式：填充 / 适应 / 拉伸。对齐开元 BoxFit 与栖阅 UIImageView contentMode。
    @AppStorage("reader.customWallpaperFillMode") private var customWallpaperFillModeRaw = ReaderWallpaperFillMode.fill.rawValue
    @State private var isPerBookOverride: Bool = false
    @AppStorage("reader.mode") private var readerModeRawValue: String = ReaderMode.scroll.rawValue
    @State private var renderedReaderMode: ReaderMode?
    @AppStorage("reader.tapZones") private var tapZonesRawValue: String = ReaderTapAction.defaultRawValue
    @AppStorage("reader.keepScreenAwake") private var keepScreenAwake = true
    /// -1 follows the system; 0.05...1 overrides while the reader is open.
    @AppStorage("reader.brightness") private var readerBrightness: Double = -1
    @AppStorage("reader.preloadChapterCount") private var preloadChapterCount = ReaderPreloadPolicy.defaultCount
    @AppStorage("reader.textSelectionEnabled") private var textSelectionEnabled = false
    @AppStorage("reader.imageStyle") private var globalImageStyleRaw: String = ReaderImageStyle.default.rawValue
    @AppStorage("reader.traditionalChineseEnabled") private var traditionalChineseEnabled = false
    @AppStorage("reader.bionicReadingEnabled") private var bionicReadingEnabled = false
    @AppStorage("reader.fontWeight") private var fontWeightRawValue = ReaderBodyFontWeight.regular.rawValue
    @AppStorage("reader.textAlignment") private var textAlignmentRawValue = ReaderTextAlignment.smart.rawValue
    @AppStorage("reader.verticalPadding") private var verticalPadding: Double = 0.0
    @AppStorage("reader.smartLineCleanup") private var smartLineCleanup = false
    @AppStorage("reader.followSystemPaper") private var followSystemPaper = true
    @AppStorage("reader.inkOpacity") private var inkOpacity: Double = 1.0
    @AppStorage("reader.customInkHex") private var customInkHexRaw = ""
    @AppStorage("reading.dailyGoalMinutes") private var dailyGoalMinutes: Int = 30
    @AppStorage("reading.lastGoalCelebratedDate") private var lastGoalCelebratedDate: String = ""

    private var fontFamily: ReaderFontFamily {
        ReaderFontFamily(rawValue: fontFamilyRawValue) ?? .system
    }

    private var fontWeight: ReaderBodyFontWeight {
        ReaderBodyFontWeight(rawValue: fontWeightRawValue) ?? .regular
    }

    private var textAlignment: ReaderTextAlignment {
        ReaderTextAlignment(rawValue: textAlignmentRawValue) ?? .smart
    }

    private var parsedCustomInkHex: UInt32? {
        let trimmed = customInkHexRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return UInt32(trimmed.replacingOccurrences(of: "#", with: ""), radix: 16)
    }

    private var background: ReaderBackground {
        ReaderBackground(rawValue: backgroundRawValue) ?? .paper
    }

    private var readerMode: ReaderMode {
        ReaderMode(rawValue: readerModeRawValue) ?? .scroll
    }

    private var chapterHeadingStyle: ReaderPageChromeLayout {
        ReaderPageChromeLayout(rawValue: chapterHeadingStyleRaw) ?? .header
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
        bookmarks.filter { $0.chapterIndex == currentDisplayChapterIndex }.count
    }

    private var isCurrentChapterBookmarked: Bool {
        appState.bookshelfStore.isBookmarked(
            bookID: bookID,
            chapterIndex: currentDisplayChapterIndex,
            paragraphIndex: currentBookmarkParagraphIndex
        )
    }

    private var currentBookmarkParagraphIndex: Int {
        currentParagraphIndexForPersistence()
    }

    private var currentDisplayChapterIndex: Int {
        if readerMode != .scroll,
           pagedBlocksCache.indices.contains(pagedPageIndex) {
            let block = pagedBlocksCache[pagedPageIndex]
            if !block.isPlaceholder, block.chapterIndex >= 0 {
                return block.chapterIndex
            }
        }
        guard !windowSections.isEmpty else { return chapterIndex }
        return resolvedReadingPosition(forFlatIndex: visibleParagraphIndex).chapterIndex
    }

    private var currentDisplayChapterTitle: String {
        let index = currentDisplayChapterIndex
        if let section = windowSections.first(where: { $0.chapterIndex == index }),
           !section.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return section.title
        }
        if index == chapterIndex {
            let title = content.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty { return title }
        }
        return chapterTitle(for: index)
    }

    private var progressTitle: String {
        var parts: [String] = []
        let displayIndex = currentDisplayChapterIndex
        if let displayTotal = displayTotalChapters, displayTotal > 0 {
            let percentage = Int((Double(displayIndex + 1) / Double(displayTotal) * 100).rounded())
            let chapterNumber = min(
                max(declaredChapterNumber(in: currentDisplayChapterTitle) ?? (displayIndex + 1), 1),
                displayTotal
            )
            parts.append("第 \(chapterNumber) / \(displayTotal) 章")
            parts.append("\(percentage)%")
        } else {
            parts.append("第 \(displayIndex + 1) 章")
        }
        if readerMode != .scroll {
            if let chapterPages = currentChapterPageStatus {
                parts.append(chapterPages)
            } else {
                let pageCount = max(pagedBlocks.count, 1)
                let page = min(max(pagedPageIndex + 1, 1), pageCount)
                parts.append("页 \(page)/\(pageCount)")
            }
        }
        return parts.joined(separator: " · ")
    }

    /// Live chapter total for the footer. The bookshelf's `totalChapters`
    /// can be stale after a source reshuffle, so the live TOC wins here too.
    private var displayTotalChapters: Int? {
        if let highest = chapters.map(\.index).max(), highest >= 0 {
            return highest + 1
        }
        if let totalChapters, totalChapters > 0 {
            return totalChapters
        }
        return nil
    }

    /// Page position inside the current chapter, which is what a reader
    /// expects ("page 2 of 5") instead of a window-wide count that grows
    /// whenever a prefetched neighbour lands.
    private var currentChapterPageStatus: String? {
        guard readerMode != .scroll,
              pagedBlocks.indices.contains(pagedPageIndex) else { return nil }
        let block = pagedBlocks[pagedPageIndex]
        guard !block.isPlaceholder, block.chapterIndex >= 0 else { return nil }
        let ordinal = block.pageOrdinal + 1
        let count = chapterPageTotal(for: block.chapterIndex, fallback: ordinal)
        return "页 \(min(ordinal, count))/\(count)"
    }

    /// Total pages of one chapter, reconciled across every source of truth:
    /// the live paging window, the per-chapter cache and the current ordinal.
    /// A stale cache used to leave the footer one page short, which made the
    /// real last page unreachable ("6/7" that cannot turn).
    private func chapterPageTotal(for chapterIndex: Int, fallback: Int) -> Int {
        var windowTotal = 0
        for block in pagedBlocks where block.chapterIndex == chapterIndex && !block.isPlaceholder {
            windowTotal = max(windowTotal, block.pageOrdinal + 1)
        }
        let cached = chapterPageCounts[chapterIndex] ?? 0
        return max(windowTotal, cached, fallback, 1)
    }

    /// The chapter number printed in the TOC title ("第25章 地宫全图"), which
    /// can differ from the array index when a source ships extra volumes.
    private func declaredChapterNumber(in title: String) -> Int? {
        guard let range = title.range(of: #"第\s*[0-9]+\s*章"#, options: .regularExpression) else { return nil }
        let digits = title[range].filter(\.isNumber)
        guard let value = Int(digits), value > 0 else { return nil }
        return value
    }

    /// Scroll-mode boundary feedback. The native surface has no placeholder
    /// page, so without this a slow or failing source looks like the book
    /// simply ended. It only appears near the boundary where the reader would
    /// actually cross; a failure keeps a retry button because it needs a
    /// decision, an in-flight prefetch is just informational.
    private var scrollChapterStatus: ScrollChapterStatus? {
        guard readerMode == .scroll else { return nil }
        if isNearCurrentChapterEnd {
            let next = windowCurrentChapterIndex + 1
            if next < windowChapterUpperBound {
                if let failure = windowFailures[next] {
                    return ScrollChapterStatus(
                        chapterIndex: next,
                        message: "第 \(next + 1) 章加载失败：\(failure)",
                        isFailure: true
                    )
                }
                if windowLoadingIndices.contains(next) {
                    return ScrollChapterStatus(
                        chapterIndex: next,
                        message: "正在加载第 \(next + 1) 章…",
                        isFailure: false
                    )
                }
            }
        }
        if isNearCurrentChapterStart {
            let previous = windowCurrentChapterIndex - 1
            if previous >= 0 {
                if let failure = windowFailures[previous] {
                    return ScrollChapterStatus(
                        chapterIndex: previous,
                        message: "第 \(previous + 1) 章加载失败：\(failure)",
                        isFailure: true
                    )
                }
                if windowLoadingIndices.contains(previous) {
                    return ScrollChapterStatus(
                        chapterIndex: previous,
                        message: "正在加载第 \(previous + 1) 章…",
                        isFailure: false
                    )
                }
            }
        }
        return nil
    }

    private var isNearCurrentChapterEnd: Bool {
        guard let section = windowSections.first(where: { $0.chapterIndex == windowCurrentChapterIndex }),
              !section.paragraphs.isEmpty else { return false }
        let resolved = resolvedReadingPosition(forFlatIndex: visibleParagraphIndex)
        guard resolved.chapterIndex == windowCurrentChapterIndex else { return false }
        return section.paragraphs.count - resolved.paragraphIndex <= 6
    }

    private var isNearCurrentChapterStart: Bool {
        guard let section = windowSections.first(where: { $0.chapterIndex == windowCurrentChapterIndex }),
              !section.paragraphs.isEmpty else { return false }
        let resolved = resolvedReadingPosition(forFlatIndex: visibleParagraphIndex)
        guard resolved.chapterIndex == windowCurrentChapterIndex else { return false }
        return resolved.paragraphIndex <= 3
    }

    private var sleepTimerBadgeText: String? {
        sleepTimerCoordinator.badgeText(configuredMinutes: sleepTimerMinutes)
    }

    private var maximumReaderTarget: Int {
        switch readerMode {
        case .scroll:
            return positionMapping.maximumParagraphIndex
        case .pageTurn, .cover, .pageCurl:
            return positionMapping.maximumPageIndex
        }
    }

    private var windowChapterUpperBound: Int {
        // The live table of contents is the authority. `totalChapters` is the
        // count from the last bookshelf refresh and can exceed the chapters
        // this reader actually holds; trusting it made every boundary request
        // target a chapter that no longer exists, which looked like the book
        // had simply ended.
        let localCount = appState.bookshelfStore.book(id: bookID)?.localChapters?.count ?? 0
        return ReaderChapterWindowPolicy.upperBound(
            totalChapters: totalChapters,
            chapterIndices: chapters.map(\.index),
            fallback: max(max(chapterIndex, windowCurrentChapterIndex) + 1, localCount)
        )
    }

    private var windowRadius: Int {
        // Keep the window bounded, but local imports are cheap to widen: the
        // paragraphs already live in the bookshelf model, so the only cost is
        // pagination. Force five chapters on each side so an old AppStorage
        // value of 2 still gets ten chapters of instant back/forward reading.
        let base = ReaderChapterWindowPolicy.radius(forPreloadCount: preloadChapterCount)
        return isLocalChapterBook ? max(base, ReaderPreloadPolicy.maximumCount) : max(base, 5)
    }

    /// 本地导入的书（localChapters 在书架模型里），章节读取不经过书源。
    /// `localChapters` 是后加的可选字段，旧书架可能解码成 nil；本地导入的
    /// 身份标记还在，不能让整条本地快路径（宽窗口 + 同步 seed）因此失效。
    private var isLocalChapterBook: Bool {
        guard let book = appState.bookshelfStore.book(id: bookID) else { return false }
        if book.localChapters?.isEmpty == false { return true }
        return book.sourceURL.hasPrefix("local://") && book.localContent?.isEmpty == false
    }

    private var windowSlices: [ReaderChapterSlice] {
        windowSections.map {
            ReaderChapterSlice(chapterIndex: $0.chapterIndex, paragraphCount: $0.paragraphs.count)
        }
    }

    private var windowLayout: ReaderChapterWindowPolicy.Layout {
        ReaderChapterWindowPolicy.layout(windowSlices)
    }

    private func chapterTitle(for index: Int) -> String {
        if let section = windowSections.first(where: { $0.chapterIndex == index }) {
            return section.title
        }
        if let chapter = chapters.first(where: { $0.index == index }) {
            return chapter.title
        }
        return "第 \(index + 1) 章"
    }

    private var filteredChapters: [BookChapter] {
        tocFilterCache.chapters(
            query: debouncedTocQuery,
            reversed: tocReversed,
            chapters: chapters
        )
    }

    private var filteredNavigationEntries: [LocalTextNavigationEntry] {
        tocFilterCache.navigationEntries(
            query: debouncedTocQuery,
            reversed: tocReversed,
            entries: navigationEntries
        )
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

    /// 分页真实可用的视口。首次渲染前回退到根视口，页面首次布局后立即换成实测值。
    /// 这解决了「分页按 852pt 排、UIPageViewController 只给 793pt」导致的页尾截断。
    private var pagedLayoutViewportSize: CGSize {
        if let metrics = pagedPageContainerMetrics, metrics.isValid {
            return metrics.size
        }
        return effectiveViewportSize
    }

    /// 分页与渲染共用的唯一几何来源。
    private var pagedPageGeometry: ReaderPageGeometry {
        let margin = CGFloat(pagePadding)
        if let metrics = pagedPageContainerMetrics, metrics.isValid {
            return metrics.geometry(
                horizontalMargin: margin,
                chromeLayout: chapterHeadingStyle,
                contentExtendsIntoChrome: contentExtendsIntoChrome,
                headerFontSize: CGFloat(headerFontSize),
                headerTopGap: CGFloat(headerTopGap),
                verticalPadding: CGFloat(verticalPadding)
            )
        }
        return ReaderPageGeometry(
            viewportSize: effectiveViewportSize,
            safeTop: readerTopSafeInset,
            safeBottom: readerFooterSafeInset,
            horizontalMargin: margin,
            chromeLayout: chapterHeadingStyle,
            contentExtendsIntoChrome: contentExtendsIntoChrome,
            headerFontSize: CGFloat(headerFontSize),
            headerTopGap: CGFloat(headerTopGap),
            verticalPadding: CGFloat(verticalPadding)
        )
    }

    /// cover 模式的页面在同一棵 SwiftUI 树里，用 PreferenceKey 回传；page-curl /
    /// 滑动模式的页面在独立 UIHostingController 里，preference 出不来，改由
    /// PageCurlReaderView 的布局回调把真实 bounds 传回来。两条路都汇到这里。
    private func adoptPageContainerMetrics(_ metrics: ReaderPageContainerMetrics) {
        guard metrics.isValid else { return }
        // 0.5pt 吸附，避免像素级抖动触发无休止的重新分页。
        let snapped = ReaderPageContainerMetrics(
            size: CGSize(
                width: (metrics.size.width * 2).rounded() / 2,
                height: (metrics.size.height * 2).rounded() / 2
            ),
            globalMinY: (metrics.globalMinY * 2).rounded() / 2,
            rootViewportHeight: metrics.rootViewportHeight,
            rootSafeTop: metrics.rootSafeTop,
            rootSafeBottom: metrics.rootSafeBottom
        )
        guard pagedPageContainerMetrics != snapped else { return }
        pagedPageContainerMetrics = snapped
        schedulePagedBlocksCacheRebuild()
        scheduleGeometrySettle()
    }

    /// Holds the pagination warmup until the page container stops reporting new
    /// bounds. `pagedPageGeometry` feeds the chapter signature, so measuring a
    /// chapter against the fallback viewport and then again against the real
    /// one throws the first result away — the reason a freshly opened local
    /// book paused on "正在加载下一章" for chapters it already had in memory.
    private func endReaderSession() {
        guard !readerSessionEnded else { return }
        quiesceReaderSession()
        readerSessionEnded = true
        ambientSoundEnabled = false
    }

    /// A parked reader keeps its document and paragraph, so leaving must stop
    /// timers, speech and brightness overrides without marking the session dead.
    /// `readerSessionEnded` stays false: the same view tree is presented again.
    private func parkReaderSession() {
        guard !readerSessionEnded else { return }
        chromeCoordinator.state.closeAll()
        quiesceReaderSession()
        isReaderVisible = false
    }

    /// Shared teardown of everything that must not keep running offscreen.
    private func quiesceReaderSession() {
        windowGeneration &+= 1
        asyncPaginationGeneration &+= 1
        asyncPaginationTask?.cancel()
        asyncPaginationTask = nil
        cancelChapterJumpPreparation()
        geometrySettleTask?.cancel()
        geometrySettleTask = nil
        paginationWarmupRestartTask?.cancel()
        paginationWarmupRestartTask = nil
        chapterSeekTask?.cancel()
        chapterSeekTask = nil
        tocScrollTask?.cancel()
        tocScrollTask = nil
        positionPersistScheduler.cancel()
        pageLayoutTask?.cancel()
        cancelPrefetch()
        cancelPaginationWarmup()
        cancelWindowRetries()
        persistReadingPosition(paragraphIndexOverride: currentParagraphIndexForPersistence(),
            commitsExit: true)
        stopAutoScroll()
        sleepTimerTask?.cancel()
        sleepTimerTask = nil
        sleepTimerCoordinator.remainingSeconds = nil
        inBookSearchTask?.cancel()
        inBookSearchTask = nil
        stopSpeechPlayback()
        ReaderAmbientSoundscapeEngine.shared.stop()
        pageLayoutTask = nil
        restoreIdleTimerPreference()
        UIDevice.current.isBatteryMonitoringEnabled = false
        if let brightnessBeforeReader {
            UIScreen.main.brightness = brightnessBeforeReader
        }
        pauseReadingActivity()
    }

    /// A parked reader is pushed again without a fresh `onAppear`; the router
    /// calls this before the transition so the second stay behaves like the first.
    private func resumeReaderSession() {
        guard !readerSessionEnded else { return }
        isReaderVisible = true
        restoreReaderOnScreenState()
    }

    /// Everything scoped to the reader being on screen, minus the one-time
    /// document setup that a parked reader already completed.
    private func restoreReaderOnScreenState() {
        guard !readerSessionEnded else { return }
        applyReaderBrightness()
        applyIdleTimerPreference()
        scheduleSleepTimer()
        resumeReadingActivity()
    }

    private func resumeReadingActivity() {
        guard isReaderVisible, !readerSessionEnded, !readerOpeningManaged, scenePhase == .active else { return }
        foregroundReading.resume(at: Date())
    }

    private func pauseReadingActivity() {
        let calendar = ReadingDayActivity.calendar(in: .current)
        guard let interval = foregroundReading.pause(at: Date(), calendar: calendar) else { return }
        appState.bookshelfStore.recordReadingActivity(bookID: bookID, days: interval.days,
                                                       startsSession: interval.startsSession)
    }

    private func scheduleGeometrySettle() {
        guard !chapterGeometrySettled else { return }
        geometrySettleTask?.cancel()
        geometrySettleTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: ReaderPerformancePolicy.geometrySettleNanoseconds)
            guard !Task.isCancelled else { return }
            geometrySettleTask = nil
            chapterGeometrySettled = true
            // Far chapters were placeholders while the container settled.
            // Rebuild once so the page model and the position mapping agree,
            // then fill the rest of the window off the page-turn path.
            schedulePagedBlocksCacheRebuild()
            // Clear the pending flag for network books too: they never start a
            // warmup, and a stuck flag kept their placeholder radius at "the
            // warmup will fill this" forever.
            paginationWarmupPending = false
            guard readerMode != .scroll else { return }
            warmPaginationCache(around: windowCurrentChapterIndex)
        }
    }

    private var pageContainerLayoutHandler: (CGSize, CGFloat) -> Void {
        { size, globalMinY in
            adoptPageContainerMetrics(
                ReaderPageContainerMetrics(
                    size: size,
                    globalMinY: globalMinY,
                    rootViewportHeight: effectiveViewportSize.height,
                    rootSafeTop: readerTopSafeInset,
                    rootSafeBottom: readerFooterSafeInset
                )
            )
        }
    }

    /// Text column used by illustrations in both the SwiftUI paged surface and
    /// the TextKit scroll surface. Derived from the measured container instead
    /// of UIScreen so split view / Stage Manager keep the same geometry.
    private var illustrationColumnWidth: CGFloat {
        let viewport = readerMode == .scroll ? effectiveViewportSize : pagedLayoutViewportSize
        return max(viewport.width - CGFloat(pagePadding * 2), 200)
    }

    private var readerPageCacheKey: String {
        // Pagination depends on the viewport. Include the actual container
        // bounds so rotation, split-view and Stage Manager resize invalidate
        // the model instead of showing pages calculated for the old width.
        let viewport = pagedLayoutViewportSize
        let windowSignature = windowSections.isEmpty
            ? "base:\(content.title):\(content.paragraphs.count)"
            : windowSections.map { section in
                "\(section.chapterIndex):\(section.contentRevision):\(section.state)"
            }.joined(separator: ",")
        return [
            readerLayoutKey,
            ReaderPerformancePolicy.viewportCacheKey(viewport),
            readerContentFingerprint,
            windowSignature,
            // 主题/外观也是页面渲染的一部分：page-curl 的页面是创建时快照的
            // hosting controller，不换 key 就不会重画 —— 这正是「换主题要翻页
            // 才生效」的成因。
            backgroundRawValue,
            backgroundWallpaperRevision.uuidString,
            customFontPostScriptName,
            readerIsNight ? "dark" : "light"
        ].joined(separator: "|")
    }

    /// Per-page content signature. Deliberately excludes `windowSections`:
    /// the text of a page depends on typography and theme, not on which
    /// neighbouring chapters happen to be loaded. `PageCurlReaderView` uses
    /// this to keep the hosting controllers it already built when a prefetch
    /// renumbers the array.
    private var readerPageRevisionKey: String {
        [
            readerLayoutKey,
            chapterViewportSignature,
            textSelectionEnabled ? "selectable" : "page-taps",
            "header-render:\(headerOpacity):\(allowsDuplicateTopStatus)",
            "\(footerShowTime)-\(footerShowBatteryIcon)-\(footerShowBatteryPercent)",
            backgroundRawValue,
            backgroundWallpaperRevision.uuidString,
            customFontPostScriptName,
            "ink:\(customInkHexRaw):\(String(format: "%.2f", inkOpacity))",
            readerIsNight ? "dark" : "light",
            speechHighlightToken
        ].joined(separator: "|")
    }

    private var readerLayoutKey: String {
        [
            readerModeRawValue,
            fontFamilyRawValue,
            fontWeightRawValue,
            customFontPostScriptName,
            String(format: "%.1f", fontSize),
            String(format: "%.1f", lineSpacing),
            String(format: "%.1f", pagePadding),
            String(format: "%.1f", verticalPadding),
            String(format: "%.1f", letterSpacing),
            String(format: "%.1f", paragraphSpacing),
            String(format: "%.1f", paragraphIndent),
            String(format: "%.1f", titleSpacing),
            String(format: "%.1f", footerHeight),
            textAlignmentRawValue,
            smartLineCleanup ? "clean" : "raw",
            chapterHeadingStyleRaw,
            "title:\(chapterTitleSize):\(chapterTitleBold):\(chapterTitleFamilyRaw)",
            chapterDecorationRaw, chapterAlignmentRaw,
            "header:\(headerFontSize):\(headerTopGap)",
            contentExtendsIntoChrome ? "extend" : "inset",
            statusPosition,
            showSystemStatusBar ? "sysbar" : "immersive",
            currentImageStyle.rawValue,
            traditionalChineseEnabled ? "tc" : "sc",
            bionicReadingEnabled ? "br" : "plain"
        ].joined(separator: "|")
    }

    /// Typography half of the chapter pagination signature. A change here makes
    /// the measured page *content* of every cached chapter stale, so the page
    /// cache is dropped and the window is measured again from scratch.
    private var chapterTypographySignature: String {
        [
            fontFamilyRawValue,
            fontWeightRawValue,
            customFontPostScriptName,
            String(format: "%.1f", fontSize),
            String(format: "%.1f", lineSpacing),
            String(format: "%.1f", pagePadding),
            String(format: "%.1f", verticalPadding),
            String(format: "%.1f", letterSpacing),
            String(format: "%.1f", paragraphSpacing),
            String(format: "%.1f", paragraphIndent),
            String(format: "%.1f", titleSpacing),
            String(format: "%.1f", footerHeight),
            textAlignmentRawValue,
            smartLineCleanup ? "clean" : "raw",
            chapterHeadingStyleRaw,
            "title:\(chapterTitleSize):\(chapterTitleBold):\(chapterTitleFamilyRaw)",
            chapterDecorationRaw, chapterAlignmentRaw,
            "header:\(headerFontSize):\(headerTopGap)",
            contentExtendsIntoChrome ? "extend" : "inset",
            statusPosition,
            showSystemStatusBar ? "sysbar" : "immersive",
            currentImageStyle.rawValue,
            traditionalChineseEnabled ? "tc" : "sc",
            bionicReadingEnabled ? "br" : "plain"
        ].joined(separator: "|")
    }

    /// Container-geometry half of the signature. The measured page container
    /// arrives one frame after `onAppear` and can wobble for a moment while the
    /// reader settles, so geometry is tracked separately: a geometry change
    /// needs new measurements, but it must not wipe the chapters already
    /// measured for the previous container or restart the warmup from zero.
    private var chapterViewportSignature: String {
        let viewport = pagedLayoutViewportSize
        let geometry = pagedPageGeometry
        return [
            String(format: "%.1fx%.1f", viewport.width, viewport.height),
            String(format: "%.1f", geometry.safeTop),
            String(format: "%.1f", geometry.safeBottom),
            String(format: "%.1f", geometry.bodyTop),
            String(format: "%.1f", geometry.bodyBottom)
        ].joined(separator: "|")
    }

    /// Signature for chapter-local pagination. Unlike `readerLayoutKey` it
    /// ignores the reading mode: page-turn, cover and page-curl share one page
    /// model, so switching between them must not re-measure every chapter.
    /// A cached chapter is only reusable for the exact typography *and*
    /// geometry it was measured with, so the stored key keeps both halves.
    private var chapterPageLayoutSignature: String {
        chapterTypographySignature + "||" + chapterViewportSignature
    }

    private func chapterPageContentSignature(_ section: ReaderChapterSection) -> String {
        "\(section.chapterIndex)|\(section.contentRevision)"
    }

    /// Keeps the chapter pagination cache bounded. Entries outside the live
    /// window stay valid for quick back-reads until the cap forces the farthest
    /// chapters out.
    private func pruneChapterPageCache(keeping window: Set<Int>) {
        let limit = max(window.count + 6, 12)
        guard chapterPageCache.count > limit else { return }
        let nearest = chapterPageCache.keys.sorted {
            abs($0 - windowCurrentChapterIndex) < abs($1 - windowCurrentChapterIndex)
        }.prefix(limit)
        let keep = window.union(nearest)
        chapterPageCache = chapterPageCache.filter { keep.contains($0.key) }
    }

    private var positionMapping: ReaderPositionMapping {
        positionMappingCache
    }

    var body: some View {
        applyReaderPreferenceObservers(
            to: applyReaderContentObservers(
                to: applyReaderLifecycle(
                    to: applyReaderModals(to: readerCoreStage)
                )
            )
        )
    }

    private var readerCoreStage: some View {
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
            // The paged tree must survive page-model revisions: re-keying it
            // on every prefetched chapter destroys TabView/UIPageViewController
            // state mid-gesture. Each surface consumes its own content
            // revision instead (PageCurlReaderView.contentRevision, cover
            // data and TabView tags).
            .id(readerMode.rawValue)
            .readerOpeningContentReady(isWindowSeeded && !windowSections.isEmpty)
            .contentShape(Rectangle())
            .simultaneousGesture(
                // 仅针对非滚动分页模式使用轻触手势，绝不在距离为0时拦截拖拽，
                // 彻底释放 iOS 16 及全机型在 WKWebView 与 UIPageViewController 的原生滑动与翻页响应。
                SpatialTapGesture()
                    .onEnded { value in
                        guard readerMode != .scroll, !textSelectionEnabled else { return }
                        handleReaderTap(at: value.location)
                    }
                , including: readerMode == .scroll ? .subviews : (textSelectionEnabled ? .none : .all)
            )

            ReaderScrollChromeLayer(
                chrome: chromeCoordinator,
                speechController: speechController,
                showSystemStatusBar: showSystemStatusBar,
                topSafeInset: readerTopSafeInset,
                statusBarBackground: readerThemeBackground,
                isScrollMode: readerMode == .scroll,
                showsFooterPreference: statusPosition == "bottom" || statusPosition == "both",
                autoScrollEnabled: autoScrollEnabled,
                hasScrollStatus: scrollChapterStatus != nil,
                navigationAnimation: motion.animation(.navigation),
                makeHeader: { readerHeader },
                makeFooter: {
                    readerFooter
                },
                makeStatusBanner: {
                    Group {
                        if let status = scrollChapterStatus {
                            scrollChapterStatusBanner(status)
                        }
                    }
                }
            )
            .zIndex(2)

            ReaderInteractiveHUDLayer(
                chrome: chromeCoordinator,
                speechController: speechController,
                sleepTimer: sleepTimerCoordinator,
                goalCelebration: goalCelebrationCoordinator,
                navigationIsTransitioning: navigationIsTransitioning,
                textSelectionEnabled: textSelectionEnabled,
                topSafeInset: readerTopSafeInset,
                autoScrollEnabled: autoScrollEnabled,
                showSystemStatusBar: showSystemStatusBar,
                navigationAnimation: motion.animation(.navigation),
                expansionAnimation: motion.animation(.expansion),
                onCompleteTextSelection: {
                    textSelectionEnabled = false
                    presentOverlay()
                },
                makeTapZoneOverlay: {
                    tapZoneOverlay
                },
                makeOverlay: { sleepBadge in
                    readerOverlay(sleepBadgeText: sleepBadge)
                },
                makeSpeechErrorBanner: { message in
                    readerSpeechErrorBanner(message: message)
                },
                makeSpeechCapsule: { sleepBadge in
                    floatingSpeechCapsule(sleepBadgeText: sleepBadge)
                },
                makeAutoScrollCapsule: {
                    floatingAutoScrollCapsule
                }
            )
            .zIndex(11)

            if let statusMessage {
                readerStatusBanner(message: statusMessage)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(12)
            }

            if let jump = pendingWindowJump, !showChapterList {
                VStack {
                    HStack(spacing: 10) {
                        ProgressView().tint(readerThemeTextColor)
                        Text("正在打开 · \(chapterTitle(for: jump.chapterIndex))")
                            .font(.subheadline).lineLimit(1)
                    }
                    .padding(12)
                    .foregroundStyle(readerThemeTextColor)
                    .background(readerThemeBackground, in: Capsule())
                    .padding(.top, readerTopSafeInset + 12)
                    .padding(.horizontal, 16)
                    Spacer()
                }
                .allowsHitTesting(false)
                .zIndex(12)
            }

            ReaderSettingsDrawerLayer(
                chrome: chromeCoordinator,
                speechController: speechController,
                reducesMotion: motion.reducesMotion,
                expansionAnimation: motion.animation(.expansion),
                viewportHeight: effectiveViewportSize.height,
                footerSafeInset: readerFooterSafeInset,
                onDismiss: closeSettingsPanel,
                makeSettingsPanel: {
                    settingsPanel
                }
            )
            .zIndex(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .preference(key: ReaderViewportSizePreferenceKey.self, value: proxy.size)
            }
            .ignoresSafeArea()
        }
        .background(ReaderSafeAreaObserver { insets in
            if measuredSafeInsets != insets { measuredSafeInsets = insets }
        })
        // Native interactive pop is the only return path. The fast custom
        // fallback dismissed the route without a UIKit transition, which tore
        // down the reader and rebuilt the tab chrome mid-swipe.
        .background {
            ReaderSystemBridgesLayer(
                chrome: chromeCoordinator,
                speechController: speechController,
                nativeSession: nativeSession,
                readerUsesBookReturn: readerUsesBookReturn,
                isScrollMode: readerMode == .scroll,
                showChapterList: showChapterList,
                temporaryCoverPresented: temporaryCoverPresented,
                textSelectionEnabled: textSelectionEnabled,
                showBookmarks: showBookmarks,
                showBookDetailSheet: showBookDetailSheet,
                showContentFilter: showContentFilter,
                hasModalItemPresented: recapSeedForAI != nil || readerLoginSource != nil || showChapterWebPage,
                navigationIsTransitioning: navigationIsTransitioning,
                activeScrollTarget: activeScrollTarget,
                volumeKeyPageTurn: volumeKeyPageTurn,
                autoScrollEnabled: autoScrollEnabled,
                isReaderVisible: isReaderVisible,
                readerSessionEnded: readerSessionEnded,
                onExit: endReaderSession,
                onPark: parkReaderSession,
                onResume: resumeReaderSession,
                onSelectChapter: { selectChapter(index: $0) },
                onRequestExit: requestReaderExit,
                onVolumePageTurn: handleVolumePageTurn
            )
        }
        .background {
            ReaderSpeechFollowObserver(
                speechController: speechController,
                isScrollMode: readerMode == .scroll,
                onScrollParagraphChanged: { target in
                    guard target >= 0 else { return }
                    let chapter = speechChapterIndex
                    let title = windowSections.first { $0.chapterIndex == chapter }?.title
                        ?? chapterTitle(for: chapter)
                    appState.bookshelfStore.updateReadingProgress(
                        bookID: bookID,
                        chapterIndex: chapter,
                        chapterTitle: title,
                        totalChapters: totalChapters ?? 0,
                        paragraphIndex: target
                    )
                },
                onPagedParagraphChanged: { target in
                    guard target >= 0,
                          let flat = speechFlatParagraphIndex,
                          !interactionGate.isPageInteractionActive else { return }
                    pagedPageIndex = pageIndex(containingParagraph: flat)
                },
                onPagedRangeChanged: { range in
                    followSpeechRangeInPagedMode(range)
                },
                onSpeechHighlightTokenChanged: { token in
                    if speechHighlightToken != token {
                        speechHighlightToken = token
                    }
                }
            )
        }
        .overlay(alignment: .topLeading) { ReaderFrameHUD() }
        .toolbar(.hidden, for: .navigationBar, .tabBar)
        .task(id: backgroundRawValue) {
            if background == .custom {
                await ReaderCustomWallpaperStore.warmWallpaper()
                guard !Task.isCancelled else { return }
                customBackgroundIsDark = ReaderCustomWallpaperStore.isWallpaperDark
                if ReaderCustomWallpaperStore.hasEditedWallpaper,
                   UserDefaults.standard.object(forKey: "reader.customWallpaperFillMode") == nil {
                    customWallpaperFillModeRaw = ReaderCustomWallpaperStore.adjustment.fillMode.rawValue
                }
                backgroundWallpaperRevision = UUID()
                rebuildPagedBlocksCacheAsync()
                return
            }
            guard let name = background.wallpaperAssetName else { return }
            let loaded = await ReaderIllustratedBackgroundStore.load(name)
            guard loaded != nil, !Task.isCancelled else { return }
            // Warm before versioning UIKit snapshots; otherwise a cached page
            // could keep its pre-decode blank background forever.
            backgroundWallpaperRevision = UUID()
            rebuildPagedBlocksCacheAsync()
        }
        .preferredColorScheme(background.isDark ? .dark : .light)
        // `preferredColorScheme` only drives the window. The paged reader
        // builds `UIHostingController`s outside the SwiftUI environment, and
        // system controls inside the chrome read `colorScheme` directly, so
        // the reader theme is also pushed into the environment here.
        .environment(\.colorScheme, readerIsNight ? .dark : .light)
        .highRefreshRateSurface()
        .ignoresSafeArea()
    }

    private func applyReaderModals<Content: View>(to base: Content) -> some View {
        base
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
        .fullScreenCover(isPresented: $showChapterList) {
            chapterListSheet
        }
        .sheet(isPresented: $showBookmarks) {
            bookmarkSheet
        }
        .sheet(item: $wallpaperDraft) { draft in
            ReaderWallpaperEditorView(draft: draft) {
                backgroundRawValue = ReaderBackground.custom.rawValue
                customBackgroundIsDark = ReaderCustomWallpaperStore.isWallpaperDark
                customWallpaperFillModeRaw = ReaderCustomWallpaperStore.adjustment.fillMode.rawValue
                if ReaderCustomWallpaperStore.adjustment.linkedInkHex != nil {
                    customInkHexRaw = ""
                }
                backgroundWallpaperRevision = UUID()
                rebuildPagedBlocksCacheAsync(); syncPerBookOverrideIfNeeded(); HapticFeedback.success()
            }
        }
        .onDisappear { wallpaperImportTask?.cancel(); wallpaperImportRevision = UUID() }
        .sheet(isPresented: $showFontManagementSheet) {
            NavigationStack {
                CustomFontManagementView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("完成") {
                                showFontManagementSheet = false
                                rebuildPagedBlocksCacheAsync()
                            }
                        }
                    }
            }
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
        .sheet(isPresented: $showContentFilter) {
            NavigationStack {
                PurifyRulesView()
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { showContentFilter = false } } }
            }
        }
        .sheet(isPresented: $showBookDetailSheet) {
            NavigationStack {
                if let shelfBook = appState.bookshelfStore.book(id: bookID), shelfBook.sourceURL.hasPrefix("local://") {
                    LocalBookMetadataView(book: shelfBook, onSelectChapter: { index in
                        selectChapter(index: index)
                        showBookDetailSheet = false
                    })
                } else if let shelfBook = appState.bookshelfStore.book(id: bookID) {
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
        .sheet(isPresented: $showChapterWebPage) {
            SmartWebReaderView(initialURL: currentChapterWebURL)
        }
        .sheet(item: $readerLoginSource, onDismiss: {
            // Cookies land in the shared store while the sheet is up, so the
            // chapter that failed with 401/403 can be retried immediately.
            retryChapterManually(currentDisplayChapterIndex)
        }) { source in
            SourceLoginView(
                source: source,
                cookieStore: appState.sourceCookieStore,
                engine: appState.engine
            )
        }
        .sheet(item: $recapSeedForAI) { seed in
            NavigationStack {
                AIChatView(recapSeed: seed)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("关闭") { recapSeedForAI = nil }
                        }
                    }
            }
        }
    }

    private func applyReaderLifecycle<Content: View>(to base: Content) -> some View {
        base
            .onAppear {
            NavigationTrace.shared.mark("reader", "onAppear mode=\(readerModeRawValue)")
            nativeSession?.recordAppearance(managed: readerOpeningManaged)
            // Dismissing the full-screen TOC must not replay initial position,
            // markReaderOpened or the initial synchronous pagination pass.
            isReaderVisible = true
            if nativeSession != nil {
                guard !hasInitializedNativePresentation else {
                    // A parked reader is presented again without rebuilding its
                    // document. Its one-time setup already ran, but everything
                    // scoped to being on screen has to be restored here.
                    restoreReaderOnScreenState()
                    return
                }
                hasInitializedNativePresentation = true
            }
            guard readerPresentationLifecycle.beginAppearance() else {
                resumeReadingActivity()
                return
            }
            readerSessionEnded = false
            foregroundReading = ForegroundReadingSession()
            resumeReadingActivity()
            migrateTypographyDefaultsIfNeeded()
            if let ov = ReaderOverrideStore.shared.override(for: bookID) {
                isPerBookOverride = true
                if let mode = ov.readerMode { readerModeRawValue = mode.rawValue }
                if let font = ov.fontFamily { fontFamilyRawValue = font.rawValue }
                if let size = ov.fontSize { fontSize = size }
                if let spacing = ov.lineSpacing { lineSpacing = spacing }
                if let bg = ov.background { backgroundRawValue = bg.rawValue }
            }
            renderedReaderMode = readerMode
            if background == .custom {
                customBackgroundIsDark = ReaderCustomWallpaperStore.isWallpaperDark
            }
            chromeCoordinator.state.setInitialOverlayVisible(initialOverlayVisible)
            seedWindow()
            readerContentFingerprint = makeContentFingerprint(content)
            seededContentFingerprint = readerContentFingerprint
            let storedOpening = appState.bookshelfStore.book(id: bookID)
            let openingParagraph = initialParagraphIndex
                ?? (storedOpening?.currentChapterIndex == chapterIndex ? storedOpening?.currentParagraphIndex : nil)
                ?? 0
            let openingSection = windowSections.first(where: { $0.chapterIndex == windowCurrentChapterIndex })
            let openingChars = openingSection.map {
                ReaderPaginationSchedulingPolicy.characterCount(of: $0.paragraphs, title: $0.title)
            } ?? ReaderPaginationSchedulingPolicy.characterCount(of: content.paragraphs, title: content.title)
            if readerMode != .scroll {
                if ReaderPaginationSchedulingPolicy.shouldPaginateOffMainActor(
                    hasExistingPages: false,
                    activeChapterCharacterCount: openingChars,
                    forceAsync: false
                ) {
                    rebuildPagedBlocksCacheAsync(
                        useCachedPageAnchor: false,
                        anchorOverride: ReaderChapterPosition(chapterIndex: chapterIndex, paragraphIndex: openingParagraph),
                        forceAsync: false
                    )
                } else {
                    rebuildPagedBlocksCache()
                }
            }
            let initial = initialAutoScrollTarget()
            nativeSession?.recordOpeningCursor(requested: initialParagraphIndex, resolved: initial.paragraph)
            scrollParagraphTarget = initial.paragraph
            pagedPageIndex = initial.page
            if initial.paragraph > 0 {
                didLandInitialPosition = false
                scrollJumpGeneration &+= 1
                paragraphJumpRequest = ParagraphJumpRequest(index: initial.paragraph)
            } else {
                didLandInitialPosition = true
            }
            hasPreparedOpeningPosition = true
            UIDevice.current.isBatteryMonitoringEnabled = true
            previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
            brightnessBeforeReader = UIScreen.main.brightness
            applyReaderBrightness()
            applyIdleTimerPreference()
            scheduleSleepTimer()
            appState.bookshelfStore.markReaderOpened(bookID: bookID)
            if !readerOpeningManaged { persistReadingPosition() }
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
        .onChange(of: readerOpeningManaged) { isOpening in
            if !isOpening { resumeReadingActivity() }
        }
        // A parked reader is restored by the router before its push; see
        // NativeReaderHostingController.prepareForRepresentation().
        .onDisappear {
            NavigationTrace.shared.mark("reader", "onDisappear")
            isReaderVisible = false
            pauseReadingActivity()
            // UIKit may deliver SwiftUI disappear before the interactive-pop phase callback.
            // The native session is the sole owner of final cleanup, including that ordering.
            if nativeSession != nil { return }
            // Ownership is visibility-scoped even for temporary covers.
                // Cover presentation is not a reader exit. Keep the live session
            // and any selected chapter's download/pagination transaction alive.
            guard readerPresentationLifecycle.endAppearance(chapterListPresented: showChapterList || temporaryCoverPresented) else { return }
            endReaderSession()
        }
        .onReceive(NotificationCenter.default.publisher(for: .readerSourceWillChange)) { notice in
            guard notice.object as? String == bookID else { return }
            endReaderSession()
        }
        .onChange(of: keepScreenAwake) { _ in
            applyIdleTimerPreference()
        }
        .onChange(of: sleepTimerMinutes) { _ in
            scheduleSleepTimer()
        }
        .onChange(of: ttsRate) { newValue in
            speechController.updateRate(Float(newValue))
        }
        .onChange(of: autoScrollDelay) { value in
            let validDelay = ReaderAutomationPolicy.clampedDelay(value)
            if value != validDelay {
                autoScrollDelay = validDelay
                return
            }
            // The task captures its delay. Cancel that old wait and start the
            // new interval now, rather than only changing the displayed number.
            if autoScrollEnabled { startAutoScroll() }
        }
        .onChange(of: scenePhase) { phase in
            guard !readerSessionEnded else { return }
            if phase != .active {
                positionPersistScheduler.cancel()
                appState.finishReadingWritesInBackground {
                    pauseReadingActivity()
                    persistReadingPosition(paragraphIndexOverride: currentParagraphIndexForPersistence())
                }
                if autoScrollEnabled {
                    autoScrollPausedForScene = true
                    stopAutoScroll(clearScenePause: false)
                }
                // Speech continues playing in background / screen lock
            } else {
                resumeReadingActivity()
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
    }

    private func applyReaderContentObservers<Content: View>(to base: Content) -> some View {
        base
            .onChange(of: bindingRevision) { _ in
            backgroundWallpaperRevision = UUID()
            schedulePagedBlocksCacheRebuild()
        }
        .onChange(of: scrollParagraphTarget) { _ in
            // Persisting the whole bookshelf serializes JSON to disk. Debounce
            // target changes so paging/auto-scroll stays on the rendering path.
            scheduleReadingPositionPersistence()
        }
        .onChange(of: pagedPageIndex) { _ in
            guard pendingWindowJump == nil else { return }
            ensurePagedContinuationBuffer(pageIndex: pagedPageIndex)
            scheduleReadingPositionPersistence()
        }
        .onChange(of: content) { updatedContent in
            // Chapter handoff normally recreates the reader, but keeping a
            // revision here also handles cache refreshes that replace text in
            // place (including edits to a middle paragraph).
            readerContentFingerprint = makeContentFingerprint(updatedContent)
            // A parked reader can be re-mounted from its original request
            // snapshot (the chapter it was launched from), not only from the
            // chapter the live window crossed into. Replaying content the
            // window already holds must keep the exact paragraph; resetting
            // here silently pulled a reopened reader back to its launch chapter.
            // A genuine cache refresh or source switch changes the text, which
            // fails these comparisons and still resets everything below.
            // The launch snapshot keeps arriving and its chapter may already be
            // trimmed out of the window, so compare against what seeded this
            // reader as well as the chapter the content itself carries.
            if makeContentFingerprint(updatedContent) == seededContentFingerprint { return }
            if let live = windowSections.first(where: { $0.chapterIndex == updatedContent.chapter.index }),
               live.isReady, live.title == updatedContent.title,
               live.paragraphs == updatedContent.paragraphs {
                return
            }
            // Never carry a previous chapter's playback, page or sheet state
            // into freshly loaded content. This also covers source switching
            // when the owner reuses the same reader identity.
            stopAutoScroll()
            stopSpeechPlayback()
            pageLayoutTask?.cancel()
            pageLayoutTask = nil
            scrollParagraphTarget = 0
            pagedPageIndex = 0
            visibleParagraphIndex = 0
            paragraphJumpRequest = nil
            closeSettingsPanel()
            showChapterList = false
            showBookmarks = false
            chromeCoordinator.state.setInitialOverlayVisible(initialOverlayVisible)
            // The window owns the chapter list now. Rebuild it from the new
            // content and rebuild pages without stalling MainActor for huge chapters.
            resetWindow()
            // The old page model belongs to the previous chapter. Rebuild it
            // from the freshly reset reading position instead of restoring a
            // stale page ordinal from the replaced content.
            rebuildPagedBlocksCacheAsync(useCachedPageAnchor: false)
        }
        .onChange(of: preloadChapterCount) { _ in
            // Apply a preload change to the live window immediately: grow
            // both sides, then evict chapters that fell outside the new
            // radius. Disk-cached chapters remain available for back-reads.
            prefetchWindow(around: windowCurrentChapterIndex)
            trimWindowIfNeeded()
        }
    }

    private func applyReaderPreferenceObservers<Content: View>(to base: Content) -> some View {
        base
            .onChange(of: readerModeRawValue) { _ in
            // Capture the departing surface before rebuilding: paragraph-only
            // lookup sends a continuation page back to the paragraph's start.
            let anchor = (renderedReaderMode == .scroll ? scrollAnchorPosition() : currentPageAnchor())
                ?? scrollAnchorPosition()
            renderedReaderMode = readerMode
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            // The departing pager cannot publish from SwiftUI dismantle.
            // Its owner releases the gate before rebuilding the new mode.
            interactionGate.isPageInteractionActive = false
            interactionGate.rebuildDeferred = false
            interactionGate.isScrollInteractionActive = false
            interactionGate.scrollTrimDeferred = false
            paginationRebuildPending = false
            paginationWarmupPending = false
            // A mode switch changes the page model itself. Rebuild now so the
            // first paged frame has a valid mapping; slider/rotation changes
            // use the debounced path below. Start the warmup first: the page
            // builder turns far chapters into cheap placeholders while it
            // paginates them one per frame.
            pageLayoutTask?.cancel()
            pageLayoutTask = nil
            if readerMode != .scroll {
                warmPaginationCache(around: windowCurrentChapterIndex)
            } else {
                cancelPaginationWarmup()
            }
            rebuildPagedBlocksCacheAsync(anchorOverride: anchor)
            let paragraph = positionMapping.clampParagraph(anchor.flatMap {
                windowLayout.flatIndex(chapterIndex: $0.chapterIndex, paragraphIndex: $0.paragraphIndex)
            } ?? visibleParagraphIndex)
            stopAutoScroll()
            stopSpeechPlayback()
            scrollParagraphTarget = paragraph
            visibleParagraphIndex = paragraph
            scrollJumpGeneration &+= 1
            paragraphJumpRequest = readerMode == .scroll
                ? ParagraphJumpRequest(index: paragraph, utf16Offset: anchor?.paragraphUTF16Offset ?? 0)
                : nil
            // The rebuild restored the UTF-16 anchor. A paragraph-to-page
            // mapping here would undo that restoration on every mode switch.
            if readerMode != .scroll { reportCoverVisibleIdentity(pagedPageIndex) }
            positionPersistScheduler.cancel()
            // The scroll target is window-flat; the sidecar always stores
            // the chapter-local cursor resolved from the committed surface.
            persistReadingPosition()
            syncPerBookOverrideIfNeeded()
        }
        .onChange(of: fontFamilyRawValue) { _ in
            syncPerBookOverrideIfNeeded()
        }
        .onChange(of: fontSize) { _ in
            syncPerBookOverrideIfNeeded()
        }
        .onChange(of: lineSpacing) { _ in
            syncPerBookOverrideIfNeeded()
        }
        .onChange(of: backgroundRawValue) { _ in
            syncPerBookOverrideIfNeeded()
        }
        .onChange(of: initialParagraphIndex) { target in
            guard let target, content.paragraphs.indices.contains(target) else { return }
            guard let flat = windowLayout.flatIndex(chapterIndex: chapterIndex, paragraphIndex: target) else { return }
            guard flat != visibleParagraphIndex else { return }
            jumpToParagraph(target)
        }
        .onChange(of: readerPageCacheKey) { _ in
            schedulePagedBlocksCacheRebuild()
        }
        .onChange(of: chapterTypographySignature) { _ in
            // Typography or content styling changed: every cached chapter is
            // stale. Drop the cache now and measure the window again one
            // chapter per frame.
            guard readerMode != .scroll else { return }
            chapterPageCache.removeAll()
            chapterPageCacheSignature = chapterPageLayoutSignature
            warmPaginationCache(around: windowCurrentChapterIndex)
        }
        .onChange(of: chapterViewportSignature) { _ in
            // Geometry only. Cached chapters stay around — they are simply not
            // reusable for the new container — and the warmup restarts after
            // the container stops moving instead of being cancelled mid-flight.
            guard readerMode != .scroll else { return }
            schedulePagedBlocksCacheRebuild()
            schedulePaginationWarmupRestart()
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

    private func syncPerBookOverrideIfNeeded() {
        guard isPerBookOverride else { return }
        let ov = BookReaderOverride(
            readerMode: ReaderMode(rawValue: readerModeRawValue),
            fontFamily: ReaderFontFamily(rawValue: fontFamilyRawValue),
            fontSize: fontSize,
            lineSpacing: lineSpacing,
            background: ReaderBackground(rawValue: backgroundRawValue)
        )
        ReaderOverrideStore.shared.setOverride(ov, for: bookID)
    }

    private var readerBackdrop: some View {
        pageBackground.ignoresSafeArea()
    }

    // 顶栏文字也属于主题：系统深色 + 浅色主题时 .primary/.secondary
    // 会解析成白色，压在米色栏上直接看不见。
    private var chromeForeground: Color {
        readerThemeTextColor.opacity(0.94)
    }

    private var chromeSecondaryForeground: Color {
        readerThemeTextColor.opacity(0.62)
    }

    private var readerIsNight: Bool {
        (background != .custom && background.isDark) || (followSystemPaper && colorScheme == .dark)
    }

    private var readerThemeTextColor: Color {
        background.resolvedTextColor(isNight: readerIsNight, customInkHex: parsedCustomInkHex, inkOpacity: inkOpacity)
    }

    private var readerUITextColor: UIColor {
        background.resolvedUITextColor(isNight: readerIsNight, customInkHex: parsedCustomInkHex, inkOpacity: inkOpacity)
    }

    private var chapterDecoration: ReaderChapterDecoration { ReaderChapterDecoration(rawValue: chapterDecorationRaw) ?? .none }
    private var chapterAlignment: ReaderChapterAlignment { ReaderChapterAlignment(rawValue: chapterAlignmentRaw) ?? .leading }
    private var resolvedTitleSize: Double { ReaderHeadingPreferences.titleSize(custom: chapterTitleSize, body: fontSize) }
    private var chapterTitleFamily: ReaderFontFamily { ReaderFontFamily(rawValue: chapterTitleFamilyRaw) ?? fontFamily }
    private var showsTopStatus: Bool {
        ReaderHeadingPreferences.showsTopStatus(position: statusPosition, systemBar: showSystemStatusBar, allowsDuplicates: allowsDuplicateTopStatus)
    }

    private var readerThemeBackground: Color {
        background.color(isNight: readerIsNight)
    }

    private var readerControlAccent: Color {
        background == .custom ? Color(hex: background.recommendedAccentHex) : AppTheme.accent
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
        // 每次 body 求值都重建这个数组（几百到上千段）是滚动期最稳定的一笔浪费：
        // 指纹没变就复用上次的结果，只有章节窗口或正文真的变了才重建。
        let key = "\(bookID)|\(scrollContentFingerprint)"
        return ReaderScrollParagraphCache.shared.paragraphs(for: key) {
            guard !windowSections.isEmpty else { return content.paragraphs }
            var result: [String] = []
            for (offset, section) in windowSections.enumerated() {
                if offset > 0 {
                    // 章节标题不再加破折号：阅读器里标题应当左对齐、干净一行。
        result.append(section.title)
                }
                result.append(contentsOf: section.paragraphs)
            }
            return result
        }
    }

    private var scrollContentFingerprint: String {
        let window = windowSections.map { section in
            "\(section.chapterIndex):\(section.contentRevision):\(section.isReady ? "r" : "l")"
        }.joined(separator: ",")
        // The window signature catches chapters arriving/leaving; the base
        // fingerprint catches an in-place refresh of the current chapter with
        // the same paragraph count.
        return "\(readerContentFingerprint)|\(window)"
    }

    /// 结构化章节窗口，滚动面用它生成章节标题与段落元素。
    ///
    /// 旧实现把窗口压成一维 `[String]`：分隔用的章节标题和正文段落长得一模一样，
    /// 于是标题只能继承正文字号与颜色。现在标题有独立元素，样式表里改一处就够。
    private var scrollSections: [WebReaderSection] {
        if windowSections.isEmpty {
            return [
                WebReaderSection(
                    chapterIndex: chapterIndex,
                    title: content.title,
                    paragraphs: content.paragraphs
                )
            ]
        }
        return windowSections.map { section in
            WebReaderSection(
                chapterIndex: section.chapterIndex,
                title: section.title,
                paragraphs: section.paragraphs,
                isReady: section.isReady,
                contentRevision: section.contentRevision
            )
        }
    }

    private func resolvedReadingPosition(forFlatIndex index: Int) -> (chapterIndex: Int, chapterTitle: String, paragraphIndex: Int) {
        guard let position = ReaderChapterWindowPolicy.resolvedPosition(
            flatIndex: index,
            layout: windowLayout
        ) else {
            // The flat index can point outside the live window right after a
            // chapter was appended or trimmed. Falling back to the chapter the
            // reader was *opened* with silently rewinds the saved position to an
            // earlier chapter: reopening after reading across chapters landed on
            // the stale one. The window cursor is the chapter the header already
            // shows, so it is the only honest fallback.
            let fallback = max(min(index, max(content.paragraphs.count - 1, 0)), 0)
            let chapter = windowSections.isEmpty ? chapterIndex : windowCurrentChapterIndex
            let title = windowSections.first { $0.chapterIndex == chapter }?.title
                ?? (chapter == chapterIndex ? content.title : chapterTitle(for: chapter))
            return (chapter, title, fallback)
        }
        let title = windowSections.first { $0.chapterIndex == position.chapterIndex }?.title ?? content.title
        return (position.chapterIndex, title, position.paragraphIndex)
    }

    /// The speech controller numbers paragraphs inside the chapter it was
    /// given. The native surface and page mapping use the window-wide flat
    /// index, so both sides must meet in the same space.
    private var speechFlatParagraphIndex: Int? {
        guard speechController.currentParagraphIndex >= 0 else { return nil }
        if windowSections.isEmpty { return speechController.currentParagraphIndex }
        return windowLayout.flatIndex(
            chapterIndex: speechChapterIndex,
            paragraphIndex: speechController.currentParagraphIndex
        )
    }

    private var activeScrollTarget: Int? {
        if speechController.isSpeaking, let flat = speechFlatParagraphIndex {
            return flat
        }
        if let jump = paragraphJumpRequest {
            return jump.index
        }
        return nil
    }

    /// Chapter page for the "open in web view" escape hatch. Some API-style
    /// sources only return a preview through `ruleContent`; the site page is
    /// the only place the rest of the text exists, so keep that route one tap
    /// away instead of pretending the truncated paragraph is the chapter end.
    private var currentChapterWebURL: URL? {
        let raw = content.chapter.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        if let url = URL(string: raw), url.scheme?.isEmpty == false {
            return url
        }
        guard let baseText = currentBookSource?.bookSourceUrl.nilIfEmpty,
              let base = URL(string: baseText) ?? URL(string: "https://" + baseText),
              let url = URL(string: raw, relativeTo: base)?.absoluteURL,
              url.scheme?.isEmpty == false else {
            return nil
        }
        return url
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
        if content.imageStyle != nil {
            return content.readerImageStyle
        }
        return ReaderImageStyle(rawValue: globalImageStyleRaw) ?? .default
    }

    /// 首章加载中的占位：主题色底 + 进度指示，避免「点进书先白一会儿」。
    private var readerLoadingPlaceholder: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(readerThemeTextColor.opacity(0.55))
            Text("正在加载章节…")
                .font(.footnote)
                .foregroundStyle(readerThemeTextColor.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(readerThemeBackground)
        .allowsHitTesting(false)
    }

    private var initialSurfaceOpacity: Double {
        1
    }

    /// 滚动模式的正文顶部内边距：显示页眉时让出页眉带，否则只避让刘海。
    private var scrollContentTopInset: Double {
        if scrollChromeGeometry.headerVisible {
            return Double(scrollChromeGeometry.protectedHeight)
        }
        return Double(
            ReaderPageLayoutEngine.minimumTopInset(
                pagePadding: CGFloat(pagePadding),
                safeTop: readerTopSafeInset
            )
        )
    }

    private var scrollChromeGeometry: ReaderScrollChromeGeometry {
        ReaderScrollChromeGeometry(
            safeTop: readerTopSafeInset,
            headerVisible: ReaderScrollChromePolicy.headerVisible(
                chapterStyle: chapterHeadingStyle, statusPosition: statusPosition),
            showSystemStatusBar: showSystemStatusBar, fontSize: CGFloat(headerFontSize), topGap: CGFloat(headerTopGap)
        )
    }

    /// 滚动模式底部状态带：给页脚独立高度，正文视口在页脚上方截止。
    private var scrollFooterReservedHeight: CGFloat {
        ReaderPageChrome.scrollFooterReservedHeight(statusPosition: statusPosition)
    }

    private var scrollReaderContent: some View {
        // 滚动模式改由 WKWebView 渲染。章节窗口的增删在文档内做 DOM 补丁，
        // 不再整串重建 attributed string —— 跳章/跨章滑动不再有「先清空再排版」
        // 的那一帧，也就不会整屏空白；标题成为独立的 h1/h2，可以和正文分开造型。
        WebScrollReaderView(
            sections: scrollSections,
            contentFingerprint: scrollContentFingerprint,
            resetToken: bookID,
            fontFamily: fontFamily,
            fontWeight: fontWeight,
            fontSize: fontSize,
            chapterTitleSize: chapterTitleSize, chapterTitleBold: chapterTitleBold,
            chapterTitleFamily: chapterTitleFamily,
            chapterDecoration: chapterDecoration, chapterAlignment: chapterAlignment,
            lineSpacing: lineSpacing,
            pagePadding: pagePadding,
            letterSpacing: letterSpacing,
            paragraphSpacing: paragraphSpacing,
            paragraphIndent: paragraphIndent,
            titleSpacing: titleSpacing,
            footerHeight: footerHeight,
            // 工具栏是浮层：正文的顶部内边距必须与菜单开合无关，
            // 否则每次呼出菜单整页文字都会往下掉一格（关掉再弹回来）。
            topInset: scrollContentTopInset,
            textColor: readerUITextColor,
            surfaceColor: background == .custom || background.hasTexture ? .clear : background.uiColor(isNight: readerIsNight),
            highlightColor: UIColor(hex: background.recommendedAccentHex).withAlphaComponent(readerIsNight ? 0.22 : 0.12),
            currentParagraphIndex: speechFlatParagraphIndex ?? -1,
            scrollTarget: activeScrollTarget,
            scrollRequestKey: nativeScrollRequestKey,
            isOpeningPositionPrepared: hasPreparedOpeningPosition,
            scrollTargetUTF16Offset: speechController.isSpeaking ? 0 : (paragraphJumpRequest?.utf16Offset ?? 0),
            animatedScrollDuration: autoScrollEnabled ? max(ReaderAutomationPolicy.clampedDelay(autoScrollDelay) * 0.9, 0.25) : (speechController.isSpeaking ? 0.35 : 0),
            textSelectionEnabled: textSelectionEnabled,
            showChapterEndBadge: false,
            traditionalChineseEnabled: traditionalChineseEnabled,
            bionicReadingEnabled: bionicReadingEnabled,
            textAlignment: textAlignment,
            verticalPadding: verticalPadding,
            smartLineCleanup: smartLineCleanup,
            imageStyle: currentImageStyle,
            imageHeaders: imageRequestHeaders,
            imageColumnWidth: illustrationColumnWidth,
            prioritizesSystemEdgeReturn: readerUsesBookReturn,
            onVisibleParagraph: { index in
                guard didLandInitialPosition else { return }
                if paragraphJumpRequest != nil {
                    paragraphJumpRequest = nil
                }
                updateVisibleParagraphInScroll(index)
            },
            onVisiblePosition: { index, offset in
                guard didLandInitialPosition else { return }
                // Character changes inside one paragraph do not invalidate
                // the entire SwiftUI reader tree on every scroll callback.
                scrollPositionTracker.flatIndex = index
                scrollPositionTracker.utf16Offset = offset
            },
            onPresented: {
                guard didLandInitialPosition else { return }
                resolveOpeningPreview()
            },
            onScrollInteractionChanged: { active in
                interactionGate.isScrollInteractionActive = active
                guard !active else { return }
                if !interactionGate.deferredWindowSections.isEmpty {
                    let deferred = interactionGate.deferredWindowSections
                    interactionGate.deferredWindowSections.removeAll()
                    for section in deferred { upsertWindowSection(section) }
                }
                if let pending = interactionGate.pendingScrollChapterIndex {
                    interactionGate.pendingScrollChapterIndex = nil
                    adoptScrollChapterCursor(pending)
                }
                guard !readerSessionEnded, interactionGate.scrollTrimDeferred else { return }
                interactionGate.scrollTrimDeferred = false
                trimWindowIfNeeded()
            },
            onNearBottom: {
                requestScrollForwardChapter()
            },
            onReachTop: {
                requestScrollBackwardChapter()
            },
            onNearTop: nil,
            onReachBottom: {
                requestScrollForwardChapter()
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
            },
            onScrollTargetApplied: {
                didLandInitialPosition = true
            },
            onTap: { point in
                // 文档内部已经做过位移 / 时长 / 惯性三重判定，这里只把坐标
                // 换成 3x3 点击区，配置与三种翻页模式共用同一套。
                handleReaderTap(at: point)
            },
            nativeSession: nativeSession
        )
        .ignoresSafeArea(.container, edges: .bottom)
        // 先铺满物理屏，再从底部让出状态带：页脚不再和正文重叠。
        .padding(.bottom, scrollFooterReservedHeight)
        .overlay {
            // 只有「这一段窗口里确实没有任何段落」才盖占位层。
            // 之前只判 scrollModeParagraphs 是否为空：滑动跨章时它会被重算成空数组，
            // 于是整屏被不透明占位盖住 —— 就是「往上滑一点突然全白」。
            if scrollSections.allSatisfy({ $0.paragraphs.isEmpty }) {
                readerLoadingPlaceholder
            }
        }
        // Opening and mode changes issue their own scroll requests. Appearing
        // again after parking must not replay the previous programmatic target.
        .onChange(of: chapterIndex) { newValue in
            // 父层可能先发布新章号、后拿到正文；此时重置会把上一章的
            // 段落挂到新章号上。等 content 追上再重置。
            guard content.chapter.index == newValue else { return }
            // Same replay guard as above: the window still holding a ready copy
            // of this chapter means the reader is already where it belongs.
            guard !(newValue == windowCurrentChapterIndex
                && windowSections.contains(where: { $0.chapterIndex == newValue && $0.isReady }))
            else { return }
            resetWindow()
        }
    }

    // MARK: - Continuous chapter window

    /// Seeds the live window from the chapter the owner opened. The window is
    /// the single source of truth for scroll, cover and page-curl, so a
    /// chapter handoff never tears the reader tree down.
    private func seedWindow() {
        guard !isWindowSeeded else { return }
        isWindowSeeded = true
        layoutAnchorOldParagraph = visibleParagraphIndex
        windowGeneration &+= 1
        cancelPrefetch()
        cancelPaginationWarmup()
        cancelWindowRetries()
        windowFailures.removeAll()
        windowRetryAttempts.removeAll()
        if seedLocalWindowSynchronously(around: chapterIndex) {
            warmPaginationCache(around: chapterIndex)
            touchChapterCache(chapterIndex)
            return
        }
        windowSections = [
            ReaderChapterSection(
                chapterIndex: chapterIndex,
                title: content.title,
                paragraphs: content.paragraphs
            )
        ]
        windowCurrentChapterIndex = chapterIndex
        lastWindowChangeWasAppend = false
        pendingSpeechChapterIndex = nil
        pendingAutoScrollChapterIndex = nil
        pendingWindowJump = nil
        rebuildWindowPositionMapping()
        prefetchWindow(around: chapterIndex)
        touchChapterCache(chapterIndex)
    }

    private func resetWindow() {
        scrollPositionTracker.flatIndex = -1
        scrollPositionTracker.utf16Offset = 0
        windowGeneration &+= 1
        cancelChapterJumpPreparation()
        cancelPrefetch()
        cancelPaginationWarmup()
        cancelWindowRetries()
        windowFailures.removeAll()
        windowRetryAttempts.removeAll()
        layoutAnchorOldParagraph = visibleParagraphIndex
        windowLoadingIndices.removeAll()
        if seedLocalWindowSynchronously(around: chapterIndex) {
            warmPaginationCache(around: chapterIndex)
            touchChapterCache(chapterIndex)
            return
        }
        windowSections = [
            ReaderChapterSection(
                chapterIndex: chapterIndex,
                title: content.title,
                paragraphs: content.paragraphs
            )
        ]
        windowCurrentChapterIndex = chapterIndex
        lastWindowChangeWasAppend = false
        pendingSpeechChapterIndex = nil
        pendingAutoScrollChapterIndex = nil
        pendingWindowJump = nil
        rebuildWindowPositionMapping()
        prefetchWindow(around: chapterIndex)
        touchChapterCache(chapterIndex)
    }

    /// Local imports keep every chapter in the bookshelf model, so the whole
    /// window can be seeded in one synchronous pass. The old path upserted one
    /// chapter at a time; every upsert rebuilt the full page model and restored
    /// the anchor, which is the stutter seen when a local book opened or a TOC
    /// entry was tapped and the reader kept paging.
    @discardableResult
    private func seedLocalWindowSynchronously(around current: Int) -> Bool {
        guard let book = appState.bookshelfStore.book(id: bookID),
              let localChapters = book.localChapters,
              !localChapters.isEmpty,
              localChapters.indices.contains(current) else { return false }
        let indices = ReaderChapterWindowPolicy.indices(
            around: current,
            radius: windowRadius,
            lowerBound: 0,
            upperBound: min(windowChapterUpperBound, localChapters.count)
        )
        guard !indices.isEmpty else { return false }
        windowSections = indices.map { index in
            let local = localChapters[index]
            return ReaderChapterSection(
                chapterIndex: index,
                title: local.title,
                paragraphs: local.paragraphs
            )
        }
        windowCurrentChapterIndex = current
        lastWindowChangeWasAppend = false
        pendingSpeechChapterIndex = nil
        pendingAutoScrollChapterIndex = nil
        pendingWindowJump = nil
        rebuildWindowPositionMapping()
        return true
    }

    /// Warms both sides of the cursor. Forward chapters are requested first
    /// because reading is overwhelmingly forward, but the previous chapter is
    /// loaded with the same priority as the next one so a backward swipe never
    /// waits for a network round trip.
    private func prefetchWindow(around chapter: Int) {
        precacheDiskWindow(around: chapter)
        let loaded = Set(windowSections.map(\.chapterIndex)).union(windowLoadingIndices)
        let order = ReaderChapterWindowPolicy.prefetchOrder(
            current: chapter,
            radius: windowRadius,
            lowerBound: 0,
            upperBound: windowChapterUpperBound,
            loaded: loaded
        )
        if readerMode == .scroll {
            // In scroll mode, background prefetch must only append forward
            // chapters at the bottom of the DOM. Prepending previous chapters
            // above the viewport while the user scrolls down shifts scrollY
            // and causes a visible jump/flash.
            queuePrefetch(order.filter { $0 > chapter })
        } else {
            queuePrefetch(order)
        }
    }

    /// Forward chapters already belong to the visible-window queue. Only warm
    /// the backward disk-only side in scroll mode, without inserting DOM above it.
    private func precacheDiskWindow(around chapter: Int) {
        guard readerMode == .scroll,
              let sourceURL = windowSourceURL,
              let source = appState.sourceStore.source(for: sourceURL) else {
            backgroundChapterPrecache.cancel()
            return
        }
        let available = Set(windowSections.map(\.chapterIndex)).union(windowLoadingIndices)
        let targetIndices = (1...5).map { chapter - $0 }.filter { $0 >= 0 && !available.contains($0) }
        let targets = targetIndices.compactMap { index -> BookChapter? in
            if chapters.indices.contains(index), chapters[index].index == index { return chapters[index] }
            return chapters.first(where: { $0.index == index })
        }
        let engine = appState.engine
        let cacheStore = appState.chapterContentCacheStore
        let purifyRules = appState.purifyRuleStore.enabledPatterns
        let key = "\(windowGeneration)|\(sourceURL)|\(chapter)"
        backgroundChapterPrecache.start(key: key, chapters: targets, load: { targetChapter in
            guard cacheStore.content(sourceURL: sourceURL, chapter: targetChapter, purifyRules: purifyRules) == nil else {
                return nil
            }
            let result = await AsyncTimeout.run(seconds: 12) {
                await engine.getContent(source: source, chapter: targetChapter)
            }
            guard case .success(let content)? = result else { return nil }
            return content
        }, commit: { content in
            cacheStore.save(content, sourceURL: sourceURL, purifyRules: purifyRules)
        })
    }

    private func requestScrollForwardChapter() {
        let maxLoaded = windowSections.map(\.chapterIndex).max() ?? windowCurrentChapterIndex
        let nextTarget = max(windowCurrentChapterIndex + 1, maxLoaded + 1)
        if nextTarget < windowChapterUpperBound {
            loadWindowChapter(nextTarget)
        }
        prefetchWindow(around: windowCurrentChapterIndex)
    }

    private func requestScrollBackwardChapter() {
        let minLoaded = windowSections.map(\.chapterIndex).min() ?? windowCurrentChapterIndex
        let prevTarget = minLoaded - 1
        guard prevTarget >= 0 else { return }
        loadWindowChapter(prevTarget)
    }

    /// Loads prefetched chapters one at a time in nearest-first order.
    /// Launching the whole radius concurrently let chapter N+2 finish before
    /// N+1, which left a hole in the page stream and showed a loading page
    /// exactly when the reader crossed the boundary. A serial queue also
    /// keeps a large preload setting from bursting the source with requests.
    private func queuePrefetch(_ indices: [Int]) {
        prefetchState.queue = indices.filter { index in
            !windowSections.contains { $0.chapterIndex == index && $0.isReady }
                && !windowLoadingIndices.contains(index)
        }
        guard !prefetchState.queue.isEmpty else { return }
        guard prefetchState.task == nil else { return }
        let generation = windowGeneration
        prefetchState.generation &+= 1
        let token = prefetchState.generation
        prefetchState.task = Task { @MainActor in
            // Let the first document/page commit before neighbouring chapters
            // start patching it. Cancellation still takes effect immediately.
            try? await Task.sleep(nanoseconds: 180_000_000)
            while !prefetchState.queue.isEmpty,
                  !Task.isCancelled,
                  prefetchState.generation == token,
                  windowGeneration == generation {
                // One runloop between chapters: DOM patches and page
                // rebuilds are main-actor work, and a back-to-back burst is
                // what made neighbour prefetch stutter.
                await Task.yield()
                let index = prefetchState.queue.removeFirst()
                if windowSections.contains(where: { $0.chapterIndex == index && $0.isReady }) { continue }
                if windowLoadingIndices.contains(index) { continue }
                await loadWindowChapterNow(index, generation: generation)
            }
            if prefetchState.generation == token {
                prefetchState.task = nil
            }
        }
    }

    private func cancelPrefetch() {
        backgroundChapterPrecache.cancel()
        prefetchState.generation &+= 1
        prefetchState.task?.cancel()
        prefetchState.task = nil
        prefetchState.queue.removeAll()
    }

    private func cancelPaginationWarmup() {
        paginationWarmupGeneration &+= 1
        paginationWarmupTask?.cancel()
        paginationWarmupTask = nil
        // The pending flag drives the placeholder radius. Leaving it set after
        // a cancel collapsed the synchronous radius to "warmup owns the
        // window" while no warmup was running, so the pages never came back.
        paginationWarmupPending = false
    }

    /// Paginates prefetched chapters one at a time, yielding a frame between
    /// chapters. `buildReaderPageBlocks` keeps a placeholder for the chapters
    /// this task has not reached yet, so opening a local book no longer measures
    /// ten chapters in the same main-thread turn as the first page.
    private func warmPaginationCache(around current: Int) {
        guard readerMode != .scroll else { return }
        guard pendingWindowJump == nil else { return }
        // The page container is still moving: every measurement would be
        // thrown away when the real bounds land. The settle task restarts the
        // warmup with the final geometry.
        guard chapterGeometrySettled else {
            paginationWarmupPending = true
            scheduleGeometrySettle()
            return
        }
        paginationWarmupPending = false
        cancelPaginationWarmup()
        let token = paginationWarmupGeneration
        let generation = windowGeneration
        let signature = chapterPageLayoutSignature
        let (typography, titleTypography) = chapterPaginationTypography()
        // One immutable snapshot per pass. The workers below never read
        // @AppStorage or any other main-actor state.
        let context = chapterPaginationContext(
            typography: typography,
            titleTypography: titleTypography
        )
        let order = [current] + ReaderChapterWindowPolicy.prefetchOrder(
            current: current,
            radius: windowRadius,
            lowerBound: 0,
            upperBound: windowChapterUpperBound,
            loaded: []
        )
        paginationWarmupTask = Task { @MainActor in
            // Cutting a chapter is a pure function of the snapshot, so it runs
            // on the cooperative pool. The old version measured one chapter
            // per runloop turn on the main actor; a swipe faster than that
            // landed on a chapter that was still being cut and showed its
            // placeholder for a frame - the per-page loading hitch.
            let batchSize = ReaderPerformancePolicy.paginationWarmupBatchSize
            var attempted = Set<Int>()
            while true {
                guard !Task.isCancelled, windowGeneration == generation,
                      token == paginationWarmupGeneration else { break }
                guard readerMode != .scroll, chapterPageLayoutSignature == signature else { break }
                // A page-turn gesture owns the main thread. Polling here put a
                // 40 ms timer on the main actor for the whole drag; park the
                // warmup instead and let `handlePageInteraction(false)` restart
                // it once the finger is up.
                if interactionGate.isPageInteractionActive {
                    paginationWarmupPending = true
                    break
                }
                guard !Task.isCancelled, windowGeneration == generation,
                      token == paginationWarmupGeneration else { break }
                guard readerMode != .scroll, chapterPageLayoutSignature == signature else { break }
                var batch: [(index: Int, title: String, paragraphs: [String], contentSignature: String)] = []
                for index in order where !attempted.contains(index) {
                    attempted.insert(index)
                    guard let section = windowSections.first(where: {
                        $0.chapterIndex == index && $0.isReady
                    }) else { continue }
                    let contentSignature = chapterPageContentSignature(section)
                    if let cached = chapterPageCache[index],
                       cached.layoutSignature == signature,
                       cached.contentSignature == contentSignature {
                        continue
                    }
                    batch.append((index, section.title, section.paragraphs, contentSignature))
                    if batch.count == batchSize { break }
                }
                if batch.isEmpty { break }
                let measured: [(Int, String, [ReaderPageBlock])] = await withTaskGroup(
                    of: (Int, String, [ReaderPageBlock]).self
                ) { group in
                    for job in batch {
                        let jobIndex = job.index
                        let jobTitle = job.title
                        let jobParagraphs = job.paragraphs
                        let jobSignature = job.contentSignature
                        group.addTask(priority: .utility) {
                            // Each call builds its own TextKit stack and
                            // shares no state, so this is safe off the main
                            // actor.
                            let pages = ReaderChapterPaginator.paginate(
                                chapterIndex: jobIndex,
                                title: jobTitle,
                                paragraphs: jobParagraphs,
                                context: context
                            )
                            return (jobIndex, jobSignature, pages)
                        }
                    }
                    var collected: [(Int, String, [ReaderPageBlock])] = []
                    collected.reserveCapacity(batch.count)
                    for await result in group {
                        collected.append(result)
                    }
                    return collected
                }
                guard !Task.isCancelled, windowGeneration == generation,
                      token == paginationWarmupGeneration else { break }
                guard readerMode != .scroll, chapterPageLayoutSignature == signature else { break }
                var merged = false
                for (index, contentSignature, pages) in measured {
                    chapterPageCache[index] = ReaderChapterPageCacheEntry(
                        layoutSignature: signature,
                        contentSignature: contentSignature,
                        blocks: pages
                    )
                    merged = true
                }
                if merged {
                    requestWarmupPageRebuild()
                }
                // Hand the main run loop a frame between batches: the merge
                // above can schedule a rebuild, and that rebuild must not queue
                // behind the next three chapters.
                try? await Task.sleep(nanoseconds: ReaderPerformancePolicy.paginationWarmupInterBatchNanoseconds)
            }
            if windowGeneration == generation, token == paginationWarmupGeneration {
                paginationWarmupTask = nil
                schedulePagedBlocksCacheRebuild()
            }
        }
    }

    /// Warmup writes one chapter at a time. The regular rebuild entry point
    /// debounces, so calling it after every chapter cancelled the pending
    /// rebuild each time and the measured pages only replaced their
    /// placeholders once the whole window finished. Keep the rebuild that is
    /// already in flight and let the next chapter schedule the following one,
    /// so the page right after the current chapter becomes readable while the
    /// rest of the window is still being measured.
    private func requestWarmupPageRebuild() {
        guard !interactionGate.isPageInteractionActive else {
            // Mid-gesture rebuilds used to be dropped outright, so the page the
            // finger had already moved onto kept rendering its placeholder
            // until the *next* chapter finished. Record it and flush when the
            // interaction ends.
            paginationRebuildPending = true
            return
        }
        guard pageLayoutTask == nil else { return }
        schedulePagedBlocksCacheRebuild()
    }

    /// Geometry changes arrive in bursts (first layout, safe-area adoption,
    /// rotation). Restart the warmup only after the burst ends: cancelling and
    /// re-measuring on every intermediate value wasted more work than the
    /// settle window it was protecting.
    private func schedulePaginationWarmupRestart(
        delayNanoseconds: UInt64 = ReaderPerformancePolicy.paginationWarmupRestartNanoseconds
    ) {
        guard readerMode != .scroll, chapterGeometrySettled else { return }
        paginationWarmupRestartTask?.cancel()
        paginationWarmupRestartTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled else { return }
            paginationWarmupRestartTask = nil
            warmPaginationCache(around: windowCurrentChapterIndex)
        }
    }

    /// Boundary handoff shared by the three reading surfaces. A chapter is
    /// only requested when it is actually missing; already-loaded neighbours
    /// make the handoff instant and keep the page cursor inside the window.
    private func requestAdjacentChapter(direction: Int) {
        guard direction != 0 else { return }
        requestChapter(windowCurrentChapterIndex + direction)
    }

    /// Requests one concrete chapter. Page placeholders call this with the
    /// chapter printed on the placeholder, not with a cursor-relative index,
    /// so a leading placeholder can never accidentally load the chapter after
    /// the one the user is waiting for.
    private func requestChapter(_ index: Int) {
        guard index >= 0, index < windowChapterUpperBound else { return }
        if windowSections.contains(where: { $0.chapterIndex == index && $0.isReady }) {
            prefetchWindow(around: windowCurrentChapterIndex)
            return
        }
        loadWindowChapter(index)
        prefetchWindow(around: windowCurrentChapterIndex)
    }

    /// A chapter may be requested only while it has automatic attempts left,
    /// is not already loading, and is not waiting for its backoff timer. Once
    /// the attempts are exhausted the placeholder keeps a manual retry button;
    /// without this gate every scroll tick or prefetch pass would restart the
    /// same failing request and the reader would never settle.
    private func shouldAttemptLoad(_ index: Int) -> Bool {
        guard index >= 0, index < windowChapterUpperBound else { return false }
        if windowSections.contains(where: { $0.chapterIndex == index && $0.isReady }) { return false }
        guard !windowLoadingIndices.contains(index) else { return false }
        if windowRetryTasks[index] != nil { return false }
        if windowFailures[index] != nil,
           windowRetryAttempts[index, default: 0] >= ReaderChapterRetryPolicy.maximumAutomaticAttempts {
            return false
        }
        return true
    }

    private func loadWindowChapter(_ index: Int, force: Bool = false) {
        if force {
            guard index >= 0, index < windowChapterUpperBound else { return }
        } else {
            guard shouldAttemptLoad(index) else { return }
        }
        if windowSections.contains(where: { $0.chapterIndex == index && $0.isReady }) { return }
        guard !windowLoadingIndices.contains(index) else { return }

        let generation = windowGeneration
        windowLoadingIndices.insert(index)

        Task { @MainActor in
            await self.performWindowLoad(index, generation: generation)
        }
    }

    /// Queue-owned load. The caller already checked the window state; the
    /// loading mark prevents a direct request and the queue from racing.
    private func loadWindowChapterNow(_ index: Int, generation: Int) async {
        guard shouldAttemptLoad(index) else { return }
        windowLoadingIndices.insert(index)
        await performWindowLoad(index, generation: generation)
    }

    @discardableResult
    private func performWindowLoad(_ index: Int, generation: Int) async -> Bool {
        let outcome = await fetchWindowChapter(index)
        guard windowGeneration == generation else { return false }
        windowLoadingIndices.remove(index)
        guard !Task.isCancelled else { return false }
        switch outcome {
        case .success(let loaded):
            guard acceptsWindowChapter(index) else { return false }
            cancelWindowRetry(for: index)
            windowFailures.removeValue(forKey: index)
            windowRetryAttempts.removeValue(forKey: index)
            upsertWindowSection(loaded)
            return true
        case .failure(let message):
            // A chapter the cursor has already left is not worth a retry
            // timer; recording it would surface a stale error later.
            guard acceptsWindowChapter(index) else { return false }
            windowFailures[index] = message
            let resumable = ReaderChapterRetryPolicy.delay(
                afterAttempt: windowRetryAttempts[index, default: 0]
            ) != nil
            if !resumable, let jump = pendingWindowJump, jump.chapterIndex == index {
                // Every automatic attempt failed. Fall back to the owner
                // contract once so a dead source still opens something.
                pendingWindowJump = nil
                if let target = chapters.first(where: { $0.index == index }) {
                    if let onSelectChapterWithPosition {
                        onSelectChapterWithPosition(
                            target,
                            jump.startAtEnd ? Int.max : jump.paragraphIndex
                        )
                    } else {
                        onSelectChapter?(target)
                    }
                }
            }
            scheduleWindowRetry(for: index)
            return false
        }
    }

    @MainActor
    private func fetchWindowChapter(_ index: Int) async -> ReaderWindowChapterOutcome {
        if let book = appState.bookshelfStore.book(id: bookID),
           let localChapters = book.localChapters,
           localChapters.indices.contains(index) {
            let local = localChapters[index]
            return .success(
                await ReaderChapterSection.prepare(
                    chapterIndex: index,
                    title: local.title,
                    paragraphs: local.paragraphs
                )
            )
        }

        let chapter: BookChapter?
        if chapters.indices.contains(index) && chapters[index].index == index {
            chapter = chapters[index]
        } else {
            chapter = chapters.first(where: { $0.index == index })
        }
        guard let chapter else {
            return .failure("目录中没有第 \(index + 1) 章，可能已被书源移除")
        }
        guard let sourceURL = windowSourceURL,
              let source = appState.sourceStore.source(for: sourceURL) else {
            return .failure("书源不存在或已被删除")
        }
        let purifyRules = appState.purifyRuleStore.enabledPatterns

        if let cached = appState.chapterContentCacheStore.content(
            sourceURL: source.bookSourceUrl,
            chapter: chapter,
            purifyRules: purifyRules
        ) {
            return .success(
                await ReaderChapterSection.prepare(
                    chapterIndex: index,
                    title: chapter.title,
                    paragraphs: cached.paragraphs
                )
            )
        }

        let engine = appState.engine
        let result = await AsyncTimeout.run(seconds: 12) {
            await engine.getContent(source: source, chapter: chapter)
        } ?? .failure(.network("Chapter window load timed out"))
        switch result {
        case .success(let loaded):
            appState.chapterContentCacheStore.save(
                loaded,
                sourceURL: source.bookSourceUrl,
                purifyRules: purifyRules
            )
            return .success(
                await ReaderChapterSection.prepare(
                    chapterIndex: index,
                    title: loaded.title,
                    paragraphs: loaded.paragraphs
                )
            )
        case .failure(let error):
            return .failure(error.displayMessage)
        }
    }

    /// Source of truth for the book's source URL; the bookshelf copy is
    /// authoritative and the encoded book id is the fallback.
    private var windowSourceURL: String? {
        appState.bookshelfStore.book(id: bookID)?.sourceURL
            ?? (bookID.contains("|") ? String(bookID.split(separator: "|")[0]) : nil)
    }

    /// Refresh the disk cache's LRU position when a chapter is actually read.
    /// One array move plus one write per chapter transition is cheap, and it
    /// is what makes "already read" mean "still cached" after heavy prefetch.
    private func touchChapterCache(_ index: Int) {
        guard let chapter = chapters.first(where: { $0.index == index }),
              let sourceURL = windowSourceURL,
              let source = appState.sourceStore.source(for: sourceURL) else { return }
        appState.chapterContentCacheStore.markRead(
            sourceURL: source.bookSourceUrl,
            chapter: chapter,
            purifyRules: appState.purifyRuleStore.enabledPatterns
        )
    }

    // MARK: - Chapter load retry

    /// Schedules the next automatic attempt with backoff. The failure is
    /// already recorded, so the placeholder shows the reason while the timer
    /// runs; the task map also blocks prefetch from hammering the same chapter
    /// during the wait.
    private func scheduleWindowRetry(for index: Int) {
        let attempt = windowRetryAttempts[index, default: 0]
        guard let delay = ReaderChapterRetryPolicy.delay(afterAttempt: attempt) else { return }
        windowRetryTasks[index]?.cancel()
        let generation = windowGeneration
        windowRetryTasks[index] = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, windowGeneration == generation else { return }
            windowRetryTasks[index] = nil
            guard windowFailures[index] != nil else { return }
            windowRetryAttempts[index] = attempt + 1
            loadWindowChapter(index, force: true)
        }
    }

    private func cancelWindowRetry(for index: Int) {
        windowRetryTasks[index]?.cancel()
        windowRetryTasks[index] = nil
    }

    private func cancelWindowRetries() {
        for task in windowRetryTasks.values {
            task.cancel()
        }
        windowRetryTasks.removeAll()
    }

    /// User-initiated retry: a fresh automatic cycle, then an immediate load.
    private func retryChapterManually(_ index: Int) {
        cancelWindowRetry(for: index)
        windowRetryAttempts[index] = 0
        windowFailures.removeValue(forKey: index)
        loadWindowChapter(index, force: true)
    }

    /// The in-flight load may finish after the cursor moved. Accept it when it
    /// is still inside the radius or directly extends the loaded block; a
    /// strict radius-only check used to discard the chapter the user had just
    /// asked for at the boundary.
    private func acceptsWindowChapter(_ index: Int) -> Bool {
        // A jump requested from the TOC, a bookmark or the slider may land
        // far outside the cursor radius. Without this the freshly downloaded
        // chapter was rejected and the jump silently never happened.
        if let jump = pendingWindowJump { return jump.chapterIndex == index }
        if index == windowCurrentChapterIndex { return true }
        let radiusIndices = ReaderChapterWindowPolicy.indices(
            around: windowCurrentChapterIndex,
            radius: windowRadius,
            lowerBound: 0,
            upperBound: windowChapterUpperBound
        )
        if radiusIndices.contains(index) { return true }
        let loaded = windowSections.map(\.chapterIndex)
        guard let first = loaded.min(), let last = loaded.max() else { return true }
        return index == first - 1 || index == last + 1
    }

    private func upsertWindowSection(_ section: ReaderChapterSection) {
        // A network chapter arriving mid-fling changes the whole window's
        // paragraph mapping and rebuilds the reader body. The WebView already
        // defers the DOM patch; defer the SwiftUI mutation to the same moment
        // so the frame budget belongs to the scroll, not to bookkeeping.
        if readerMode == .scroll, interactionGate.isScrollInteractionActive,
           pendingWindowJump == nil {
            interactionGate.deferredWindowSections.append(section)
            return
        }
        if pendingWindowJump?.chapterIndex == section.chapterIndex {
            // A distant selection is a foreground transaction, not an append
            // to the old cursor. Do not lay out/prewarm the abandoned window
            // before preparing the requested chapter.
            windowSections.removeAll { abs($0.chapterIndex - section.chapterIndex) > windowRadius }
            insertWindowSection(section)
            rebuildWindowPositionMapping()
            resumePendingContinuation(for: section.chapterIndex)
            precacheDiskWindow(around: section.chapterIndex)
            return
        }
        let anchor = scrollAnchorPosition()
        let oldMax = windowSections.map(\.chapterIndex).max() ?? windowCurrentChapterIndex
        insertWindowSection(section)
        let appended = section.chapterIndex > oldMax
        applyWindowChange(anchor: anchor, appended: appended)
        rebuildWindowPositionMapping()
        scheduleWindowRebuild()
        // Resume the jump before trimming: a TOC target can sit outside the
        // cursor's retention radius, and trimming first deleted the chapter
        // the reader was waiting for. This is why "pick a chapter in the TOC
        // and keep scrolling" never advanced to the next one.
        resumePendingContinuation(for: section.chapterIndex)
        trimWindowIfNeeded()
        if readerMode != .scroll {
            // A chapter that just entered the window needs its page
            // cache as well. Restart the warmup so the new edge chapter is
            // measured off the page-turn path instead of in the next rebuild.
            warmPaginationCache(around: windowCurrentChapterIndex)
        }
    }

    /// Resumes a speech or auto-scroll handoff that was waiting for this
    /// chapter. The reader stays on the same window and native surface.
    private func resumePendingContinuation(for chapter: Int) {
        guard windowSections.contains(where: { $0.chapterIndex == chapter && $0.isReady }) else { return }
        if let jump = pendingWindowJump, jump.chapterIndex == chapter {
            pendingWindowJump = nil
            activateWindowChapter(
                chapter,
                startAtEnd: jump.startAtEnd,
                paragraphIndex: jump.paragraphIndex
            )
        }
        if pendingSpeechChapterIndex == chapter {
            pendingSpeechChapterIndex = nil
            activateWindowChapter(chapter)
            DispatchQueue.main.async { beginSpeechPlayback() }
        }
        if pendingAutoScrollChapterIndex == chapter {
            pendingAutoScrollChapterIndex = nil
            activateWindowChapter(chapter)
            DispatchQueue.main.async { startAutoScroll() }
        }
    }

    private func insertWindowSection(_ section: ReaderChapterSection) {
        if let existing = windowSections.firstIndex(where: { $0.chapterIndex == section.chapterIndex }) {
            windowSections[existing] = section
        } else {
            windowSections.append(section)
            windowSections.sort { $0.chapterIndex < $1.chapterIndex }
        }
    }

    /// The paragraph currently under the reader's eye, expressed in stable
    /// chapter-local coordinates. Re-resolving that position in the new window
    /// is what keeps a prepended chapter from moving the visible line, even
    /// when SwiftUI coalesces several window mutations into one update.
    private func scrollAnchorPosition() -> ReaderChapterPosition? {
        guard !windowSections.isEmpty, windowLayout.totalCount > 0 else { return nil }
        let flat = min(max(visibleParagraphIndex, 0), windowLayout.totalCount - 1)
        let position = resolvedReadingPosition(forFlatIndex: flat)
        return ReaderChapterPosition(
            chapterIndex: position.chapterIndex,
            paragraphIndex: position.paragraphIndex,
            paragraphUTF16Offset: scrollPositionTracker.flatIndex == flat ? scrollPositionTracker.utf16Offset : 0
        )
    }

    private func applyWindowChange(anchor: ReaderChapterPosition?, appended: Bool) {
        lastWindowChangeWasAppend = appended
        guard !appended, let anchor else { return }
        layoutAnchorOldParagraph = visibleParagraphIndex
        guard let newFlat = windowLayout.flatIndex(
            chapterIndex: anchor.chapterIndex,
            paragraphIndex: anchor.paragraphIndex
        ) else {
            let fallback = min(max(visibleParagraphIndex, 0), max(windowLayout.totalCount - 1, 0))
            if fallback != visibleParagraphIndex {
                visibleParagraphIndex = fallback
                scrollParagraphTarget = fallback
                layoutAnchorRevision &+= 1
            }
            return
        }
        guard newFlat != visibleParagraphIndex else { return }
        let delta = newFlat - visibleParagraphIndex
        if scrollPositionTracker.flatIndex == visibleParagraphIndex {
            scrollPositionTracker.flatIndex = newFlat
        }
        visibleParagraphIndex = newFlat
        scrollParagraphTarget = newFlat
        if let jump = paragraphJumpRequest {
            paragraphJumpRequest = ParagraphJumpRequest(index: max(jump.index + delta, 0), utf16Offset: jump.utf16Offset)
        }
        layoutAnchorRevision &+= 1
    }

    /// Keeps the live window bounded. Chapters dropped from memory are still on
    /// disk: opening one again is a synchronous cache hit, not a new request.
    /// In-flight chapters and the cursor chapter are never evicted.
    private func trimWindowIfNeeded() {
        if readerMode == .scroll, interactionGate.isScrollInteractionActive {
            interactionGate.scrollTrimDeferred = true
            return
        }
        var keep = ReaderChapterWindowPolicy.retainedIndices(
            around: windowCurrentChapterIndex,
            radius: windowRadius,
            lowerBound: 0,
            upperBound: windowChapterUpperBound,
            loading: windowLoadingIndices
        )
        // Network loading ends before off-thread pagination. Retain a distant
        // target until the foreground jump commits, not just while downloading.
        if let jump = pendingWindowJump { keep.insert(jump.chapterIndex) }
        if readerMode == .scroll {
            // In continuous vertical scroll mode, evicting chapters above the
            // viewport right as the user crosses a chapter boundary shifts the
            // entire document upward by thousands of pixels and causes a flash.
            // Retain up to 20 already-loaded trailing chapters above the cursor.
            let minRetained = max(0, windowCurrentChapterIndex - 20)
            let maxRetained = min(
                max(windowChapterUpperBound - 1, 0),
                max(windowCurrentChapterIndex + windowRadius + 2, windowSections.map(\.chapterIndex).max() ?? windowCurrentChapterIndex)
            )
            if minRetained <= maxRetained {
                keep.formUnion(minRetained...maxRetained)
            }
        }
        // Drop failure state and pending retries for chapters the window has
        // left behind; otherwise a long session accumulates timers for
        // chapters the reader will never see again.
        let staleFailures = windowFailures.keys.filter { !keep.contains($0) }
        for index in staleFailures {
            windowFailures.removeValue(forKey: index)
            windowRetryAttempts.removeValue(forKey: index)
            cancelWindowRetry(for: index)
        }
        let removed = windowSections.contains { !keep.contains($0.chapterIndex) }
        guard removed else { return }
        let anchor = scrollAnchorPosition()
        windowSections.removeAll { !keep.contains($0.chapterIndex) }
        applyWindowChange(anchor: anchor, appended: false)
        rebuildWindowPositionMapping()
        scheduleWindowRebuild()
    }

    private func rebuildWindowPositionMapping() {
        let layout = windowLayout
        positionMappingCache = ReaderPositionMapping(
            paragraphCount: layout.totalCount,
            pageFirstParagraphs: ReaderPositionMapping.pageStarts(
                from: pagedBlocksCache.map { block in
                    guard !block.isPlaceholder,
                          let start = layout.paragraphStart(chapterIndex: block.chapterIndex) else { return nil }
                    return start + (block.firstParagraphIndex ?? 0)
                }
            )
        )
    }

    /// A UIPageViewController gesture owns the screen until its curl or
    /// scroll settles. Rebuilding the page model in that window replaces the
    /// hosting controllers under the finger and is the main cause of the
    /// dropped frame plus the “page jumps back” symptom. Defer the rebuild
    /// until `didFinishAnimating` has committed the new page cursor.
    private func handlePageInteraction(_ active: Bool) {
        guard !readerSessionEnded else { return }
        // `interactionGate` is a reference box on purpose: assigning a @State
        // here would invalidate the whole reader body at the exact moment the
        // page-turn gesture starts, which is the visible hitch at the
        // beginning of every swipe.
        interactionGate.isPageInteractionActive = active
        guard !active else { return }
        // Three different pieces of work can be parked for the duration of a
        // gesture: a debounced window rebuild, a page-cache rebuild that
        // arrived mid-drag, and a warmup that stopped at a chapter boundary.
        // Only the first used to be replayed, so a turn that landed next to an
        // unmeasured chapter kept its placeholder until something else
        // happened - the "have to pick the chapter again from the TOC" stall.
        let rebuildDeferred = interactionGate.rebuildDeferred || paginationRebuildPending
        let warmupDeferred = paginationWarmupPending
        interactionGate.rebuildDeferred = false
        paginationRebuildPending = false
        paginationWarmupPending = false
        guard rebuildDeferred || warmupDeferred else { return }
        schedulePagedBlocksCacheRebuild()
        if warmupDeferred {
            warmPaginationCache(around: windowCurrentChapterIndex)
        }
    }

    private func scheduleWindowRebuild() {
        guard readerMode != .scroll, pendingWindowJump == nil else { return }
        pageLayoutTask?.cancel()
        if interactionGate.isPageInteractionActive {
            interactionGate.rebuildDeferred = true
            return
        }
        pageLayoutTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: ReaderPerformancePolicy.pageLayoutDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            if interactionGate.isPageInteractionActive {
                interactionGate.rebuildDeferred = true
                pageLayoutTask = nil
                return
            }
            rebuildPagedBlocksCacheAsync()
            pageLayoutTask = nil
        }
    }

    private func updateVisibleParagraphInScroll(_ index: Int) {
        let total = windowLayout.totalCount
        guard total > 0 else { return }
        let safeIndex = min(max(index, 0), total - 1)
        guard visibleParagraphIndex != safeIndex else { return }
        // Only a chapter change needs to redraw the reader chrome. The latest
        // paragraph remains synchronous for bookmarks, mode switches and saves.
        scrollPositionTracker.visibleIndex = safeIndex
        if !hasResolvedOpeningPreview { hasResolvedOpeningPreview = true }
        let resolved = resolvedReadingPosition(forFlatIndex: safeIndex)
        if resolved.chapterIndex != windowCurrentChapterIndex {
            if interactionGate.isScrollInteractionActive {
                // The chapter cursor drives the header and a full SwiftUI body
                // pass. Committing it mid-fling turned every chapter crossing
                // into a hitch; keep it in the reference box and adopt it once
                // the deceleration ends. Prefetch and the cache LRU touch are
                // deferred with it because both also write window/cache state.
                if interactionGate.pendingScrollChapterIndex != resolved.chapterIndex {
                    interactionGate.pendingScrollChapterIndex = resolved.chapterIndex
                }
            } else {
                adoptScrollChapterCursor(resolved.chapterIndex)
            }
        }
        scheduleReadingPositionPersistence()
    }

    /// Commits a chapter cursor that was held back during a fling. Running the
    /// same three follow-ups here keeps prefetch, retention and the header in
    /// agreement no matter where the crossing happened.
    private func adoptScrollChapterCursor(_ chapter: Int) {
        guard chapter != windowCurrentChapterIndex else { return }
        windowCurrentChapterIndex = chapter
        prefetchWindow(around: chapter)
        trimWindowIfNeeded()
        touchChapterCache(chapter)
    }

    /// Adopts the chapter shown by a freshly built page model. Page-curl moves
    /// programmatically through `setViewControllers`, which does not fire the
    /// user-transition delegate, so the rebuild path must advance the cursor
    /// itself for prefetch/trim to follow the reader.
    private func syncWindowCursorToVisiblePage() {
        guard readerMode != .scroll,
              pagedBlocksCache.indices.contains(pagedPageIndex) else { return }
        let block = pagedBlocksCache[pagedPageIndex]
        guard !block.isPlaceholder else { return }
        guard block.chapterIndex >= 0, block.chapterIndex != windowCurrentChapterIndex else { return }
        windowCurrentChapterIndex = block.chapterIndex
        prefetchWindow(around: block.chapterIndex)
        trimWindowIfNeeded()
        touchChapterCache(block.chapterIndex)
    }

    private var nativeScrollRequestKey: String {
        [
            String(chapterIndex),
            String(scrollJumpGeneration),
            paragraphJumpRequest?.id.uuidString ?? "none",
            String(speechFlatParagraphIndex ?? -1)
        ].joined(separator: "|")
    }

    @ViewBuilder
    private var pagedReaderContent: some View {
        Group {
            switch readerMode {
            // Cover and slide share transaction semantics, not displacement.
            case .cover, .pageTurn:
                coverPagedReaderContent
            case .pageCurl:
                pageCurlReaderContent
            default:
                horizontalPagedReaderContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        // Build the 5-page window on both sides ahead of the turn.
        .onAppear { prewarmPageText(around: pagedPageIndex) }
        .onChange(of: pagedPageIndex) { target in prewarmPageText(around: target) }
        .onChange(of: pagedBlocksCacheKey) { _ in prewarmPageText(around: pagedPageIndex) }
        .onChange(of: readerPageRevisionKey) { _ in prewarmPageText(around: pagedPageIndex) }
    }

    private var pageCurlReaderContent: some View {
        PageCurlReaderView(
            pages: pagedBlocks,
            contentRevision: pagedBlocksCacheKey + "|" + readerPageRevisionKey,
            currentPageIndex: $pagedPageIndex,
            turnRequest: tapPageTurnRequest,
            onPageChanged: { target in
                updatePagedVisibleParagraph(pageIndex: target)
            },
            onPageContainerLayout: pageContainerLayoutHandler,
            onVisiblePageIdentity: { key in
                recordVisiblePageIdentity(key)
            },
            onInteractionChanged: { active in
                handlePageInteraction(active)
            },
            pageKey: { page in
                ReaderPageIdentity(page: page).key
            },
            pageRevision: { page in
                pageTextCacheKey(for: page)
            },
            prewarmSize: pagedLayoutViewportSize,
            pageBackgroundColor: pagedPageBackgroundColor,
            userInterfaceStyle: pagedUserInterfaceStyle,
            pageBuilder: { page in
                readerPage(for: page)
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var horizontalPagedReaderContent: some View {
        PageCurlReaderView(
            pages: pagedBlocks,
            contentRevision: pagedBlocksCacheKey + "|" + readerPageRevisionKey,
            transitionStyle: .scroll,
            currentPageIndex: $pagedPageIndex,
            turnRequest: tapPageTurnRequest,
            onPageChanged: { target in
                updatePagedVisibleParagraph(pageIndex: target)
            },
            onPageContainerLayout: pageContainerLayoutHandler,
            onVisiblePageIdentity: { key in
                recordVisiblePageIdentity(key)
            },
            onInteractionChanged: { active in
                handlePageInteraction(active)
            },
            pageKey: { page in
                ReaderPageIdentity(page: page).key
            },
            pageRevision: { page in
                pageTextCacheKey(for: page)
            },
            prewarmSize: pagedLayoutViewportSize,
            pageBackgroundColor: pagedPageBackgroundColor,
            userInterfaceStyle: pagedUserInterfaceStyle,
            pageBuilder: { page in
                readerPage(for: page)
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    /// Opaque paper colour handed to the UIKit paging hosts. `nil` for a
    /// custom wallpaper, which must stay transparent so the image shows
    /// through; every other theme paints the paper itself, which is what stops
    /// the white flash while a chapter is swapped.
    private var pagedPageBackgroundColor: UIColor? {
        background == .custom || background.hasTexture ? nil : background.uiColor(isNight: readerIsNight)
    }

    /// `preferredColorScheme` on the SwiftUI root does not reach the
    /// `UIHostingController`s inside the paging surfaces, so the reader theme
    /// is pushed into them explicitly. Without this a system-dark device made
    /// every paper black regardless of the selected appearance.
    private var pagedUserInterfaceStyle: UIUserInterfaceStyle {
        readerIsNight ? .dark : .light
    }

    private var coverPagedReaderContent: some View {
        // UIKit owns pan displacement and animation; SwiftUI supplies versioned
        // snapshots only. Cover and slide share the transaction, not the motion.
        let safeIndex = min(max(pagedPageIndex, 0), max(pagedBlocks.count - 1, 0))
        let previousBlock = pagedBlocks.indices.contains(safeIndex - 1) ? pagedBlocks[safeIndex - 1] : nil
        let currentBlock = pagedBlocks.indices.contains(safeIndex) ? pagedBlocks[safeIndex] : nil
        let nextBlock = pagedBlocks.indices.contains(safeIndex + 1) ? pagedBlocks[safeIndex + 1] : nil
        let previous2Block = pagedBlocks.indices.contains(safeIndex - 2) ? pagedBlocks[safeIndex - 2] : nil
        let next2Block = pagedBlocks.indices.contains(safeIndex + 2) ? pagedBlocks[safeIndex + 2] : nil
        let currentView: AnyView
        if let currentBlock {
            currentView = AnyView(readerPage(for: currentBlock))
        } else {
            currentView = AnyView(Color.clear)
        }
        return CoverPageReaderView(
            turnRequest: tapPageTurnRequest,
            pageIdentity: currentBlock.map { ReaderPageIdentity(page: $0).key } ?? "",
            contentRevision: readerPageRevisionKey,
            previousIdentity: previousBlock.map { pageTextCacheKey(for: $0) } ?? "",
            currentIdentity: currentBlock.map { pageTextCacheKey(for: $0) } ?? "",
            nextIdentity: nextBlock.map { pageTextCacheKey(for: $0) } ?? "",
            previous2Identity: previous2Block.map { pageTextCacheKey(for: $0) } ?? "",
            next2Identity: next2Block.map { pageTextCacheKey(for: $0) } ?? "",
            hasPrevious: previousBlock != nil,
            hasNext: nextBlock != nil,
            previous: previousBlock.map { block -> AnyView in AnyView(readerPage(for: block)) },
            current: currentView,
            next: nextBlock.map { block -> AnyView in AnyView(readerPage(for: block)) },
            previous2: previous2Block.map { block -> AnyView in AnyView(readerPage(for: block)) },
            next2: next2Block.map { block -> AnyView in AnyView(readerPage(for: block)) },
            onCommit: { direction in
                commitCoverTurn(direction)
            },
            onInteractionChange: { active in
                handlePageInteraction(active)
            },
            onPageContainerLayout: pageContainerLayoutHandler,
            turnStyle: readerMode == .pageTurn ? .slide : .cover,
            pageBackgroundColor: pagedPageBackgroundColor,
            userInterfaceStyle: pagedUserInterfaceStyle
        )
        .onChange(of: pagedPageIndex) { target in
            updatePagedVisibleParagraph(pageIndex: target)
            reportCoverVisibleIdentity(target)
        }
        .onAppear {
            reportCoverVisibleIdentity(pagedPageIndex)
        }
    }

    /// Commit one cover-mode turn.
    ///
    /// The UIKit animator has already moved the page under the finger; this only
    /// advances the cursor. The anchor is resolved again after the window has
    /// settled, because prefetching the next chapter renumbers every page
    /// after the insertion point (the 1.0.81 "chapter 5 jumps to chapter 2"
    /// defect).
    private func commitCoverTurn(_ direction: Int) {
        guard !pagedBlocks.isEmpty else { return }
        let target = min(max(pagedPageIndex + direction, 0), pagedBlocks.count - 1)
        guard target != pagedPageIndex else { return }
        let targetAnchor = pageAnchor(for: pagedBlocks[target])
        pagedPageIndex = target
        reportCoverVisibleIdentity(target)
        updatePagedVisibleParagraph(pageIndex: target)
        let resolved = ReaderPageRestoration.index(
            anchor: targetAnchor,
            in: pagedBlocksCache,
            fallbackIndex: target
        )
        if resolved != pagedPageIndex {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                pagedPageIndex = resolved
            }
        }
        reportCoverVisibleIdentity(resolved)
        updatePagedVisibleParagraph(pageIndex: resolved)
    }

    /// Cover mode hosts SwiftUI snapshots without `UIPageViewController`,
    /// so it must publish the same stable page
    /// identity. Without it the page model fell back to a raw array index.
    private func reportCoverVisibleIdentity(_ index: Int) {
        guard pagedBlocksCache.indices.contains(index) else { return }
        recordVisiblePageIdentity(ReaderPageIdentity(page: pagedBlocksCache[index]).key)
    }

    private func recordVisiblePageIdentity(_ key: String) {
        pageIdentityTracker.key = key
        guard !hasResolvedOpeningPreview, pagedBlocksCache.indices.contains(pagedPageIndex) else { return }
        let page = pagedBlocksCache[pagedPageIndex]
        guard !page.isPlaceholder, ReaderPageIdentity(page: page).key == key else { return }
        // UIKit can publish the identity from updateUIViewController.
        DispatchQueue.main.async {
            guard pageIdentityTracker.key == key else { return }
            resolveOpeningPreview()
        }
    }

    @ViewBuilder
    private func readerPage(for page: ReaderPageBlock) -> some View {
        if page.isPlaceholder {
            chapterPlaceholderPage(page)
        } else if page.paragraphs.contains(where: { ReaderImageSizingPolicy.imageURL(in: $0.text) != nil }) {
            // Illustration pages keep the SwiftUI stack: the image card owns
            // its own tap target and cannot live inside a text view.
            pageSurface(for: page) {
                legacyTextStack(for: page)
            }
        } else {
            pageSurface(for: page) {
                ReaderPageTextView(
                    attributedTextProvider: { pageAttributedText(for: page) },
                    contentKey: pageTextCacheKey(for: page),
                    isSelectable: textSelectionEnabled
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private func legacyTextStack(for page: ReaderPageBlock) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if page.includesTitle {
                if page.pageOrdinal == 0, chapterDecoration != .none {
                    ReaderChapterMotif(decoration: chapterDecoration).padding(.bottom, 8)
                        .frame(maxWidth: .infinity, alignment: chapterAlignment == .center ? .center : chapterAlignment == .trailing ? .trailing : .leading)
                }
                Text(ReaderTextTransform.displayText(page.chapterTitle.isEmpty ? chapterTitle(for: page.chapterIndex) : page.chapterTitle, traditionalChinese: traditionalChineseEnabled))
                    .font(chapterTitleFamily.swiftUIFont(size: CGFloat(resolvedTitleSize), weight: chapterTitleBold ? .bold : .regular, customPostScriptName: customFontPostScriptName))
                    .foregroundStyle(readerThemeTextColor)
                    .multilineTextAlignment(chapterAlignment.swiftUI)
                    .frame(maxWidth: .infinity, alignment: chapterAlignment == .center ? .center : chapterAlignment == .trailing ? .trailing : .leading)
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
    }

    /// Cache key for one rendered page: identity + speech highlight, then the
    /// layout revision. `ReaderPageTextView` compares the same string instead
    /// of diffing the whole attributed string on every layout pass.
    private func pageTextCacheKey(for page: ReaderPageBlock) -> String {
        let containsSpeech = speechController.currentParagraphIndex >= 0 && page.paragraphs.contains { entry in
            let ownerChapter = entry.chapterIndex >= 0 ? entry.chapterIndex : windowCurrentChapterIndex
            return ownerChapter == speechChapterIndex && entry.index == speechController.currentParagraphIndex
        }
        let sentenceKey: String
        if containsSpeech, let range = speechController.currentSpeechRange, range.location != NSNotFound, range.length > 0 {
            sentenceKey = "\(range.location):\(range.length)"
        } else {
            sentenceKey = "-"
        }
        let highlightKey = "\(speechChapterIndex)-\(speechController.currentParagraphIndex)-\(sentenceKey)"
        let statusKey = page.isPlaceholder ? String((windowFailures[page.chapterIndex] ?? "loading").hashValue) : "ready"
        return "\(ReaderPageIdentity(page: page).key)|\(ReaderRenderRevision.page(page))|\(highlightKey)|\(statusKey)|\(readerPageRevisionKey)"
    }

    private func pageAttributedText(for page: ReaderPageBlock) -> NSAttributedString {
        // A page body is immutable between page-model revisions. Rebuilding
        // the attributed string on every SwiftUI pass was a measurable hitch
        // during page curls; keep one cached copy per page and speech cursor.
        return pageTextCache.text(key: pageTextCacheKey(for: page), signature: readerPageRevisionKey) {
            buildPageAttributedText(for: page)
        }
    }

    private func buildPageAttributedText(for page: ReaderPageBlock) -> NSAttributedString {
        pageTextSpec(for: page).attributedString
    }

    /// Main-thread snapshot of one page's rich text. Fonts, theme colours and
    /// the speech cursor are read here; the character-level build (paragraph
    /// styles + CJK punctuation compression) then runs off the main thread.
    private func pageTextSpec(for page: ReaderPageBlock) -> ReaderPageTextSpec {
        let bodyFont = fontFamily.uiFont(
            ofSize: CGFloat(fontSize),
            weight: fontWeight.uiWeight,
            customPostScriptName: customFontPostScriptName
        )
        let titleFont = chapterTitleFamily.uiFont(
            ofSize: CGFloat(resolvedTitleSize),
            weight: chapterTitleBold ? .bold : .regular,
            customPostScriptName: customFontPostScriptName
        )
        let rawTitle = page.inlineTitleText ?? (page.chapterTitle.isEmpty ? chapterTitle(for: page.chapterIndex) : page.chapterTitle)
        let title = page.includesTitle
            ? ReaderTextTransform.displayText(rawTitle, traditionalChinese: traditionalChineseEnabled)
            : nil
        let activeSpeechRange = speechController.currentSpeechRange
        let paragraphs = page.paragraphs.map { entry -> ReaderPageTextBuilder.Paragraph in
            let ownerChapter = entry.chapterIndex >= 0 ? entry.chapterIndex : windowCurrentChapterIndex
            let paragraphHighlighted = speechChapterIndex == ownerChapter
                && speechController.currentParagraphIndex == entry.index
            var localSentenceRange: NSRange? = nil
            var effectiveHighlighted = paragraphHighlighted
            if paragraphHighlighted,
               let activeSpeechRange,
               activeSpeechRange.location != NSNotFound,
               activeSpeechRange.length > 0 {
                let entryStart = entry.sourceUTF16Offset
                let entryLength = (entry.text as NSString).length
                let entryEnd = entryStart + entryLength
                let speechStart = activeSpeechRange.location
                let speechEnd = speechStart + activeSpeechRange.length
                let overlapStart = max(entryStart, speechStart)
                let overlapEnd = min(entryEnd, speechEnd)
                if overlapEnd > overlapStart {
                    localSentenceRange = NSRange(
                        location: overlapStart - entryStart,
                        length: overlapEnd - overlapStart
                    )
                } else {
                    effectiveHighlighted = false
                }
            }
            return ReaderPageTextBuilder.Paragraph(
                text: entry.text,
                isContinuation: entry.isContinuation,
                isHighlighted: effectiveHighlighted,
                sentenceHighlightRange: localSentenceRange
            )
        }
        return ReaderPageTextSpec(
            title: title,
            paragraphs: paragraphs,
            style: ReaderPageTextBuilder.Style(
                bodyFont: bodyFont,
                titleFont: titleFont,
                textColor: readerUITextColor,
                highlightColor: UIColor(hex: background.recommendedAccentHex).withAlphaComponent(readerIsNight ? 0.22 : 0.12),
                lineSpacing: CGFloat(lineSpacing),
                letterSpacing: CGFloat(letterSpacing),
                paragraphSpacing: CGFloat(paragraphSpacing),
                titleSpacing: CGFloat(titleSpacing),
                firstLineIndent: CGFloat(paragraphIndent),
                chapterDecoration: page.pageOrdinal == 0 && pagedPageGeometry.contentHeight >= chapterDecoration.height + titleFont.lineHeight + CGFloat(titleSpacing) + 8 ? chapterDecoration : .none,
                chapterAlignment: chapterAlignment,
                textAlignment: textAlignment
            )
        )
    }

    /// 预建前后各 radius 页的富文本（前 5 后 5）。
    /// 翻页首帧只保留 TextKit 排字，逐字符的标点压缩在抬手前就已算完。
    private func prewarmPageText(around index: Int, radius: Int = 4) {
        guard readerMode != .scroll, !pagedBlocks.isEmpty else { return }
        let lower = max(0, index - radius)
        let upper = min(pagedBlocks.count - 1, index + radius)
        guard lower <= upper else { return }
        let signature = readerPageRevisionKey
        var items: [(key: String, spec: ReaderPageTextSpec)] = []
        items.reserveCapacity(upper - lower + 1)
        for pageIndex in lower...upper {
            let page = pagedBlocks[pageIndex]
            guard !page.isPlaceholder else { continue }
            let key = pageTextCacheKey(for: page)
            guard !pageTextCache.contains(key: key, signature: signature) else { continue }
            items.append((key, pageTextSpec(for: page)))
        }
        guard !items.isEmpty else { return }
        let cache = pageTextCache
        DispatchQueue.global(qos: .userInitiated).async {
            for item in items {
                cache.storeIfAbsent(key: item.key, signature: signature) {
                    item.spec.attributedString
                }
            }
        }
    }

    /// The page shown while the neighbouring chapter is still downloading, or
    /// after the source rejected it. Without a real failure state a timeout
    /// looked like the end of the book and forced the reader back to the TOC.
    /// A 401/403 or an explicit VIP/permission message means the source needs
    /// an account.  Surfacing the login sheet where the chapter failed removes
    /// the dead end where the reader only offered "retry".
    private func chapterFailureSuggestsLogin(_ message: String) -> Bool {
        let text = message.lowercased()
        return text.contains("401") || text.contains("403")
            || text.contains("登录") || text.contains("登陆")
            || text.contains("vip") || text.contains("权限")
            || text.contains("订阅") || text.contains("购买")
    }

    private func chapterPlaceholderPage(_ page: ReaderPageBlock) -> some View {
        pageSurface(for: page) {
            VStack(spacing: 12) {
                if let failure = windowFailures[page.chapterIndex] {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.orange)
                    Text(page.placeholderDirection < 0 ? "上一章加载失败" : "章节加载失败")
                        .font(.footnote.weight(.semibold))
                    if !page.chapterTitle.isEmpty {
                        Text(page.chapterTitle)
                            .font(.subheadline)
                            .foregroundStyle(readerThemeTextColor.opacity(0.82))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                    Text(failure)
                        .font(.caption2)
                        .foregroundStyle(readerThemeTextColor.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                        .padding(.horizontal, 24)
                    Button("重试") {
                        retryChapterManually(page.chapterIndex)
                    }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
                    if let source = currentBookSource,
                       SourceLoginURLResolver.resolve(source: source) != nil,
                       chapterFailureSuggestsLogin(failure) {
                        Button("登录书源") {
                            readerLoginSource = source
                        }
                        .font(.footnote.weight(.semibold))
                        .buttonStyle(.bordered)
                        .tint(AppTheme.accent)
                    }
                } else {
                    ProgressView()
                    Text(
                        page.placeholderDirection < 0
                            ? "正在加载上一章"
                            : (page.placeholderDirection > 0 ? "正在加载下一章" : "正在加载章节")
                    )
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(readerThemeTextColor.opacity(0.65))
                    if !page.chapterTitle.isEmpty {
                        Text(page.chapterTitle)
                            .font(.subheadline)
                            .foregroundStyle(readerThemeTextColor.opacity(0.82))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                    Button("重新加载") {
                        retryChapterManually(page.chapterIndex)
                    }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.bordered)
                    .tint(AppTheme.accent)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    /// 阅读页唯一画布。
    ///
    /// 几何来源只有 `ReaderPageGeometry`：页眉带、正文矩形、页脚带各自有确定坐标，
    /// 不再通过三层 padding / frame / safeArea 叠加去「猜」。页面容器尺寸会回传给
    /// 分页引擎（ReaderPageContainerMetricsKey），所以分页高度与实际可画高度永远一致。
    private func pageSurface<Content: View>(for page: ReaderPageBlock, @ViewBuilder content: @escaping () -> Content) -> some View {
        let surfaceSize = pagedLayoutViewportSize
        let geometry = pagedPageGeometry
        let resolvedWidth = surfaceSize.width > 1 ? surfaceSize.width : effectiveViewportSize.width
        let resolvedHeight = surfaceSize.height > 1 ? surfaceSize.height : effectiveViewportSize.height

        return ZStack(alignment: .topLeading) {
            content()
                .frame(
                    width: geometry.contentWidth,
                    height: geometry.contentHeight,
                    alignment: .topLeading
                )
                .clipped()
                .offset(x: geometry.horizontalMargin, y: geometry.bodyTop)

            ZStack(alignment: .topLeading) {
                if geometry.showsHeader {
                    pagedPageHeader(page: page, geometry: geometry)
                }
                pagedPageFooter(page: page, geometry: geometry)
            }
            .frame(width: resolvedWidth, height: resolvedHeight, alignment: .topLeading)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .frame(width: resolvedWidth, height: resolvedHeight, alignment: .topLeading)
        .background(pageBackground.ignoresSafeArea())
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var pageBackground: some View {
        if background == .custom, let image = ReaderCustomWallpaperStore.cachedWallpaper {
            ReaderWallpaperView(
                image: image,
                fillMode: ReaderWallpaperFillMode(rawValue: customWallpaperFillModeRaw) ?? .fill,
                adjustment: ReaderCustomWallpaperStore.adjustment,
                isNight: readerIsNight
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(backgroundWallpaperRevision)
        } else if background.hasTexture {
            ReaderPaperTextureView(background: background, night: readerIsNight)
        } else {
            readerThemeBackground
        }
    }

    /// 页眉：12pt 章节名 +（可选）时间 / 电量。位置由 geometry 决定，永远在安全区内。
    private func pagedPageHeader(page: ReaderPageBlock, geometry: ReaderPageGeometry) -> some View {
        HStack(spacing: 10) {
            // In inline mode the first page already carries the large
            // chapter title in the body; repeating it in the 12pt page
            // header is what users reported as a duplicated heading.
            if !(page.includesTitle && chapterHeadingStyle == .inline) {
                Text(page.chapterTitle.isEmpty ? chapterTitle(for: page.chapterIndex) : page.chapterTitle)
                    .font(.system(size: CGFloat(ReaderHeadingPreferences.headerSize(headerFontSize)), weight: .regular))
                    .foregroundStyle(readerThemeTextColor.opacity(ReaderHeadingPreferences.opacity(headerOpacity)))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Spacer(minLength: 8)

            if showsTopStatus {
                if footerShowTime {
                    ReaderMinuteClockText()
                        .font(.system(size: CGFloat(ReaderHeadingPreferences.headerSize(headerFontSize)), weight: .medium).monospacedDigit())
                        .foregroundStyle(readerThemeTextColor.opacity(0.50))
                }
                if footerShowBatteryIcon || footerShowBatteryPercent {
                    HStack(spacing: 3) {
                        if footerShowBatteryIcon {
                            Image(systemName: batterySymbolName)
                        }
                        if footerShowBatteryPercent {
                            Text(batteryPercentageText)
                        }
                    }
                    .font(.system(size: CGFloat(ReaderHeadingPreferences.headerSize(headerFontSize)) - 1, weight: .medium).monospacedDigit())
                    .foregroundStyle(readerThemeTextColor.opacity(0.50))
                }
            }
        }
        .padding(.horizontal, geometry.contentExtendsIntoChrome ? 6 : 0)
        .frame(
            width: geometry.contentExtendsIntoChrome
                ? geometry.contentWidth + 12
                : geometry.contentWidth,
            height: geometry.headerHeight,
            alignment: .leading
        )
        .background(
            geometry.contentExtendsIntoChrome
                ? readerThemeBackground.opacity(0.86)
                : Color.clear
        )
        .offset(
            x: geometry.contentExtendsIntoChrome
                ? geometry.horizontalMargin - 6
                : geometry.horizontalMargin,
            y: geometry.headerTop
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// 页脚：右下角 `当前页/本章总页`（竞品格式 3/35），时间与电量按开关排列。
    private func pagedPageFooter(page: ReaderPageBlock, geometry: ReaderPageGeometry) -> some View {
        HStack(spacing: 10) {
            if statusPosition == "bottom" || statusPosition == "both" {
                if footerShowTime {
                    ReaderMinuteClockText()
                        .frame(width: 42, alignment: .leading)
                }
            }

            Spacer(minLength: 4)

            if statusPosition == "bottom" || statusPosition == "both",
               footerShowBatteryIcon || footerShowBatteryPercent {
                HStack(spacing: 3) {
                    if footerShowBatteryIcon {
                        Image(systemName: batterySymbolName)
                    }
                    if footerShowBatteryPercent {
                        Text(batteryPercentageText)
                    }
                }
            }

            Text(pageNumberText(for: page))
                .frame(minWidth: 34, alignment: .trailing)
        }
        .font(.system(size: ReaderPageChrome.footerFontSize, weight: .medium).monospacedDigit())
        .foregroundStyle(readerThemeTextColor.opacity(0.45))
        .padding(.horizontal, geometry.contentExtendsIntoChrome ? 6 : 0)
        .frame(
            width: geometry.contentExtendsIntoChrome
                ? geometry.contentWidth + 12
                : geometry.contentWidth,
            height: ReaderPageChrome.footerHeight,
            alignment: .center
        )
        .background(
            geometry.contentExtendsIntoChrome
                ? readerThemeBackground.opacity(0.86)
                : Color.clear
        )
        .offset(
            x: geometry.contentExtendsIntoChrome
                ? geometry.horizontalMargin - 6
                : geometry.horizontalMargin,
            y: geometry.footerTop
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func pageNumberText(for page: ReaderPageBlock) -> String {
        guard !page.isPlaceholder, page.chapterIndex >= 0 else { return "" }
        let total = chapterPageTotal(for: page.chapterIndex, fallback: page.pageOrdinal + 1)
        return "\(min(page.pageOrdinal + 1, total))/\(total)"
    }

    /// 页脚实际占用高度（20pt 条 + 6pt 间距），分页模式固定预留 26pt。
    private var readerFooterReservedHeight: CGFloat {
        26
    }

    @ViewBuilder
    private func paragraphText(_ entry: ReaderPageEntry) -> some View {
        if let url = ReaderImageSizingPolicy.imageURL(in: entry.text) {
            illustrationCard(url: url)
        } else {
            standardParagraphText(entry.text, index: entry.index, chapterIndex: entry.chapterIndex)
        }
    }

    private func standardParagraphText(_ paragraph: String, index: Int, chapterIndex: Int) -> some View {
        let ownerChapter = chapterIndex >= 0 ? chapterIndex : windowCurrentChapterIndex
        let highlighted = speechChapterIndex == ownerChapter
            && speechController.currentParagraphIndex == index
        let sentenceRange = highlighted ? speechController.currentSpeechRange : nil
        let sentenceHighlightedAttributed: AttributedString? = {
            guard highlighted, !bionicReadingEnabled,
                  let sentenceRange,
                  sentenceRange.location != NSNotFound,
                  sentenceRange.length > 0 else { return nil }
            let nsString = paragraph as NSString
            guard sentenceRange.location < nsString.length else { return nil }
            let clamped = NSRange(location: sentenceRange.location, length: min(sentenceRange.length, nsString.length - sentenceRange.location))
            guard let swiftRange = Range(clamped, in: paragraph) else { return nil }
            var attr = AttributedString(paragraph)
            if let attrStart = AttributedString.Index(swiftRange.lowerBound, within: attr),
               let attrEnd = AttributedString.Index(swiftRange.upperBound, within: attr) {
                attr[attrStart..<attrEnd].backgroundColor = AppTheme.accent.opacity(background.isDark ? 0.25 : 0.14)
                return attr
            }
            return nil
        }()
        let textView: Text
        if bionicReadingEnabled {
            textView = Text(
                ReaderTextTransform.bionicAttributedString(
                    for: paragraph,
                    regularFont: fontFamily.swiftUIFont(size: CGFloat(fontSize), weight: .regular, customPostScriptName: customFontPostScriptName),
                    boldFont: fontFamily.swiftUIFont(size: CGFloat(fontSize), weight: .bold, customPostScriptName: customFontPostScriptName)
                )
            )
        } else if let sentenceHighlightedAttributed {
            textView = Text(sentenceHighlightedAttributed)
        } else {
            textView = Text(paragraph)
        }
        let wholeParagraphHighlighted = highlighted && sentenceHighlightedAttributed == nil
        return textView
            .font(fontFamily.swiftUIFont(size: CGFloat(fontSize), weight: .regular, customPostScriptName: customFontPostScriptName))
            .foregroundStyle(readerThemeTextColor)
            .kerning(letterSpacing)
            .lineSpacing(lineSpacing)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, wholeParagraphHighlighted ? 6 : 0)
            .background {
                if wholeParagraphHighlighted {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppTheme.accent.opacity(background.isDark ? 0.22 : 0.12))
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
                    viewportHeight: pagedLayoutViewportSize.height,
                    pagePadding: pagePadding,
                    footerHeight: footerHeight
                )
            )
        }
        .buttonStyle(.plain)
    }

    private var readerHeader: some View {
        VStack(spacing: 0) {
            ReaderScrollChapterHeader(
                title: chapterHeadingStyle == .hidden ? nil : currentDisplayChapterTitle,
                geometry: scrollChromeGeometry,
                horizontalPadding: CGFloat(pagePadding),
                foreground: readerThemeTextColor,
                paper: readerThemeBackground,
                textOpacity: ReaderHeadingPreferences.opacity(headerOpacity),
                wallpaper: background == .custom || background.hasTexture
                    ? AnyView(readerBackdrop.frame(height: effectiveViewportSize.height)
                        .frame(height: scrollChromeGeometry.protectedHeight, alignment: .top).clipped()) : nil
            ) {
                // Keep explicit top-clock/battery preferences; the default
                // bottom-status layout leaves only the chapter name here.
                if showsTopStatus {
                    HStack(spacing: 8) {
                        if footerShowTime {
                            ReaderMinuteClockText()
                        }
                        if footerShowBatteryIcon { Image(systemName: batterySymbolName) }
                        if footerShowBatteryPercent { Text(batteryPercentageText) }
                    }
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(readerThemeTextColor.opacity(ReaderHeadingPreferences.opacity(headerOpacity)))
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var readerFooter: some View {
        VStack {
            Spacer(minLength: 0)
            HStack(spacing: 12) {
                if footerShowTime {
                    ReaderMinuteClockText()
                        .frame(width: 54, alignment: .leading)

                    Spacer(minLength: 4)
                }

                Text(progressTitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity)

                if footerShowBatteryIcon || footerShowBatteryPercent {
                    Spacer(minLength: 4)

                    HStack(spacing: 3) {
                        if footerShowBatteryIcon {
                            Image(systemName: batterySymbolName)
                        }
                        if footerShowBatteryPercent {
                            Text(batteryPercentageText)
                        }
                    }
                    .frame(width: footerShowBatteryIcon && footerShowBatteryPercent ? 58 : nil, alignment: .trailing)
                }
            }
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .foregroundStyle(readerThemeTextColor.opacity(0.45))
            .padding(.horizontal, max(CGFloat(pagePadding), 18))
            .frame(height: 20, alignment: .center)
            // 阅读页忽略了安全区，页脚要自己让开 home indicator。
            // 0.35×底部安全区（34pt → 12pt）与竞品页码离底 12.3pt 对齐：
            // 文字落在手势条上方，但不会像旧版 0.25× 那样压到指示条上。
            .padding(.bottom, max(readerFooterSafeInset * 0.35, ReaderPageChrome.footerBottomInset))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Slim status pill above the footer for scroll mode. It is the only
    /// boundary feedback the TextKit surface has: a chapter that is still
    /// downloading, or one the source refused.
    private func scrollChapterStatusBanner(_ status: ScrollChapterStatus) -> some View {
        VStack {
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                if status.isFailure {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(status.message)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Button("重试") {
                        retryChapterManually(status.chapterIndex)
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                } else {
                    ProgressView()
                        .controlSize(.mini)
                    Text(status.message)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            .font(.caption)
            .foregroundStyle(readerThemeTextColor.opacity(0.85))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .modifier(ReaderChromeSurface(paper: readerThemeBackground, ink: readerThemeTextColor, cornerRadius: 999))
            .padding(.horizontal, 24)
            .padding(.bottom, max(CGFloat(footerHeight), 24) + 8)
        }
        .allowsHitTesting(status.isFailure)
        .animation(.easeInOut(duration: 0.2), value: status)
    }

    /// Full-screen content consumes the reading window's last layout snapshot.
    /// Containers reporting zero keep the existing size-based fallback.
    private var readerResolvedSafeInsets: ReaderSafeAreaResolver.Insets {
        // Querying the window/status-bar geometry while body is resolving its
        // own statusBarHidden preference can re-enter the SwiftUI layout graph.
        ReaderSafeAreaResolver.resolve(
            windowTop: measuredSafeInsets.top,
            windowBottom: measuredSafeInsets.bottom,
            statusBarHeight: 0,
            screenSize: effectiveViewportSize
        )
    }

    private var readerTopSafeInset: CGFloat { readerResolvedSafeInsets.top }

    private var readerFooterSafeInset: CGFloat { readerResolvedSafeInsets.bottom }

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

    private func readerOverlay(sleepBadgeText: String?) -> some View {
        VStack {
            HStack {
                chromeIconButton(systemName: "chevron.left") {
                    requestReaderExit()
                }
                .accessibilityIdentifier("reader.returnToShelf")

                VStack(alignment: .leading, spacing: 2) {
                    Text(currentDisplayChapterTitle)
                        .accessibilityIdentifier("reader.currentChapterHeading")
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

                if background == .custom {
                    chromeIconButton(systemName: customBackgroundIsDark ? "sun.max" : "moon.stars") {
                        customBackgroundIsDark.toggle()
                        UserDefaults.standard.set(true, forKey: "reader.customBackgroundIsDarkManual")
                        UserDefaults.standard.set(customBackgroundIsDark, forKey: "reader.customBackgroundIsDark")
                        backgroundWallpaperRevision = UUID()
                        rebuildPagedBlocksCacheAsync()
                        HapticFeedback.light()
                    }
                    .accessibilityLabel("切换壁纸文字黑白色")
                }

                chromeIconButton(systemName: isCurrentChapterBookmarked ? "bookmark.fill" : "bookmark") {
                    toggleCurrentBookmark(openList: false)
                }

                ReaderNativeMenuButton(
                    menuIdentity: readerNativeMenuIdentity,
                    makeMenu: { readerNativeMenu },
                    foregroundColor: readerUITextColor,
                    backgroundColor: readerUsesTranslucentChrome ? .clear : background.uiColor(isNight: readerIsNight),
                    presentation: nativeMoreMenuPresentation
                )
                .frame(width: 44, height: 44)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .modifier(ReaderChromeSurface(paper: readerThemeBackground, ink: readerThemeTextColor))
            .padding(.horizontal, 16)
            .padding(.top, readerTopSafeInset + 4)

            Spacer()

            VStack(spacing: 12) {
                // 滚动模式显示落点章节，分页模式显示本章页码；两者语义不同，
                // 分页时拖章节滑条会让整章重排，正是「翻页卡住」的来源之一。
                Text(readerMode == .scroll ? chapterSliderLabel : pageSliderLabel)
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(readerThemeTextColor.opacity(0.55))
                    .frame(height: 13)

                HStack(spacing: 10) {
                    navChapterButton(icon: "chevron.left", title: "上一章") {
                        selectRelativeChapter(offset: -1)
                    }
                    .disabled(!canSelectRelativeChapter(offset: -1))

                    if readerMode == .scroll {
                        let totalChapterCount = displayTotalChapters ?? chapters.count
                        let maxChapterSlider = max(totalChapterCount - 1, 1)
                        Slider(
                            value: Binding(
                                get: { chapterSliderTarget ?? Double(currentDisplayChapterIndex) },
                                set: { newValue in
                                    chapterSliderTarget = newValue
                                    scheduleLiveChapterSeek(to: newValue)
                                }
                            ),
                            in: 0...Double(maxChapterSlider),
                            step: 1,
                            onEditingChanged: { editing in
                                guard !editing else { return }
                                chapterSeekTask?.cancel()
                                chapterSeekTask = nil
                                guard let target = chapterSliderTarget else { return }
                                chapterSliderTarget = nil
                                let index = Int(target.rounded())
                                guard index != currentDisplayChapterIndex else { return }
                                selectChapter(index: index)
                            }
                        )
                            .tint(readerControlAccent)
                            .padding(.horizontal, 16)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .disabled(totalChapterCount <= 1)
                            .accessibilityLabel("章节进度")
                    } else {
                        let maxPageSlider = max(currentChapterPageTotalForSlider - 1, 1)
                        Slider(
                            value: Binding(
                                get: { Double(currentChapterPageOrdinal) },
                                set: { newValue in seekPagedPage(ordinal: Int(newValue.rounded())) }
                            ),
                            in: 0...Double(maxPageSlider),
                            step: 1,
                            onEditingChanged: { _ in }
                        )
                            .tint(readerControlAccent)
                            .padding(.horizontal, 16)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .disabled(currentChapterPageTotalForSlider <= 1)
                            .accessibilityLabel("本章页码")
                    }

                    navChapterButton(icon: "chevron.right", title: "下一章") {
                        selectRelativeChapter(offset: 1)
                    }
                    .disabled(!canSelectRelativeChapter(offset: 1))
                }

                // TTS and auto-scroll moved into the top-right overflow menu.
                // Keeping five equal-width buttons made the bottom panel the
                // busiest part of the reader; the two primary actions stay
                // here and every secondary action is one tap away.
                HStack(spacing: 8) {
                    toolButton(icon: "list.bullet", title: "目录") {
                        tocTab = 0
                        tocScrollIntent = .currentChapter
                        showChapterList = true
                        closeSettingsPanel()
                    }

                    // 换源入口从右上角溢出菜单提到常驻底栏：换源是追更时
                    // 最高频的操作之一，藏在二级菜单里每次要多两次点击。
                    toolButton(icon: "arrow.triangle.2.circlepath", title: "换源") {
                        closeSettingsPanel()
                        onRequestSourceSwitch?()
                    }
                    .disabled(onRequestSourceSwitch == nil)
                    .opacity(onRequestSourceSwitch == nil ? 0.35 : 1)

                    // 第五个入口给朗读/暂停：TTS 原来只在右上角溢出菜单里，
                    // 追更时一边听一边翻页是高频操作，底栏一键可达。
                    toolButton(
                        icon: speechController.isSpeaking && !speechController.isPaused ? "pause.fill" : "speaker.wave.2",
                        title: speechController.isSpeaking && !speechController.isPaused ? "暂停" : "朗读"
                    ) {
                        closeSettingsPanel()
                        toggleSpeech()
                    }

                    toolButton(icon: "gearshape", title: "设置") {
                        toggleSettingsPanel()
                    }
                    .accessibilityIdentifier("reader.openSettings")
                    .overlay(alignment: .topTrailing) {
                        if let badge = sleepBadgeText {
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
            .padding(12)
            .modifier(ReaderChromeSurface(paper: readerThemeBackground, ink: readerThemeTextColor))
            .padding(.horizontal, 16)
            .padding(.bottom, max(readerFooterSafeInset, 10) + 10)
        }
        .foregroundStyle(chromeForeground)
        .environment(\.colorScheme, readerIsNight ? .dark : .light)
    }

    private func requestReaderExit() {
        if onPreviewPosition != nil { persistReadingPosition() }
        if let onRequestExit { onRequestExit() } else { dismiss() }
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
            .background(readerThemeTextColor.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(ReaderControlPressStyle())
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
        .buttonStyle(ReaderControlPressStyle())
    }

    private func chromeIconButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(Circle().fill(readerUsesTranslucentChrome ? Color.clear : readerThemeBackground))
                .contentShape(Circle())
        }
        .buttonStyle(ReaderControlPressStyle())
    }

    private var readerUsesTranslucentChrome: Bool {
        ReaderChromeSurface.permitsTranslucency(reduceTransparency: UIAccessibility.isReduceTransparencyEnabled,
            increasedContrast: UIAccessibility.isDarkerSystemColorsEnabled, menuStyle: menuSurfaceStyle,
            usesWallpaper: menuUsesWallpaper)
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

    @ViewBuilder private var settingsPanel: some View {
        atelierPanel
    }

    private var atelierPanel: some View {
        ReaderSettingsWorkbench(context: ReaderWorkbenchContext(
            bookTitle: appState.bookshelfStore.book(id: bookID)?.title ?? content.title,
            background: background, bottomInset: readerFooterSafeInset,
            isNightOverride: readerIsNight,
            customInkColor: readerThemeTextColor,
            customAccentColor: readerControlAccent,
            isSpeechActive: speechController.isSpeaking,
            isAutoScrollActive: autoScrollEnabled), preview: {
                let paragraphs = windowSections.first(where: { $0.chapterIndex == currentDisplayChapterIndex })?.paragraphs ?? content.paragraphs
                let excerpt = paragraphs.first(where: { ReaderImageSizingPolicy.imageURL(in: $0) == nil }) ?? ""
                return AnyView(ReaderAtelierPreview(title: currentDisplayChapterTitle, excerpt: String(excerpt.prefix(512)), paperRevision: backgroundWallpaperRevision))
            }, page: { workbenchPage($0) }, actions: ReaderWorkbenchActions(
                close: closeSettingsPanel,
                routeChanged: {
                    chromeCoordinator.settingsTab = $0 == .assistance ? 2 : $0 == .typography ? 1 : 0
                },
                openWallpaperEditor: ReaderCustomWallpaperStore.hasCustomWallpaper ? {
                    closeSettingsPanel()
                    openSavedWallpaperEditor()
                } : nil,
                toggleSpeech: {
                    closeSettingsPanel()
                    toggleSpeech()
                },
                toggleAutoScroll: {
                    closeSettingsPanel()
                    toggleAutoScroll()
                }
            ))
    }

    /// Routes to production controls; legacy page boundaries remain stack-bounded.
    func workbenchPage(_ route: ReaderWorkbenchRoute) -> AnyView {
        switch route {
        case .themes: return AnyView(ReaderBindingLibraryView())
        case .heading: return AnyView(ReaderChapterDesignEditor())
        case .chrome: return AnyView(ReaderChromeEditor())
        case .typography: return AnyView(ReaderSettingsContent { layoutSettingsBody(showsPreview: false, includesLegacySections: false) })
        case .appearance: return AnyView(ReaderSettingsContent { appearanceSettingsBody(showsPreview: false) })
        case .assistance: return AnyView(settingsPage(for: 2))
        }
    }

    /// Builds the real settings page behind a bounded, deferred view boundary.
    @ViewBuilder func settingsPage(for tab: Int) -> some View {
        switch tab {
        case 0:
            appearanceSettings
        case 1:
            layoutSettings
        default:
            advancedSettings
        }
    }

    // Inspect the concrete values without evaluating AppStorage or building UI.
    // A 1 MB device stack cannot tolerate repeated copies of a giant page tuple.
    func settingsViewValueSizes() -> [String: Int] {
        func byteCount<Content: View>(_ build: () -> Content) -> Int {
            MemoryLayout<Content>.size
        }
        return [
            "appearance": byteCount { appearanceSettings },
            "layout": byteCount { layoutSettings },
            "advanced": byteCount { advancedSettings },
            "selection": byteCount { settingsPage(for: 0) }
        ]
    }

    private var readerNativeMenuIdentity: String {
        [
            bookID, String(windowCurrentChapterIndex), windowSourceURL ?? "",
            currentChapterWebURL?.absoluteString ?? "",
            String(onRefreshChapter != nil), String(onCacheNextChapters != nil),
            String(canShowPayAction), String(isPerformingPayAction), String(autoScrollEnabled),
            String(currentBookSource != nil)
        ].joined(separator: "\n")
    }

    private var readerNativeMenu: UIMenu {
        func action(_ title: String, _ symbol: String, enabled: Bool = true, leavesReader: Bool = false, run: @escaping () -> Void) -> UIAction {
            var attributes: UIMenuElement.Attributes = []
            if !enabled { attributes.insert(.disabled) }
            return UIAction(title: title, image: UIImage(systemName: symbol), attributes: attributes) { _ in
                if leavesReader { closeReaderChromeFromMenu() }
                run()
            }
        }
        var chapterActions: [UIMenuElement] = [
            action("刷新本章", "arrow.clockwise", enabled: onRefreshChapter != nil) { onRefreshChapter?() },
            action("缓存前后章节", "square.and.arrow.down", enabled: onCacheNextChapters != nil) { onCacheNextChapters?(windowCurrentChapterIndex) },
            action("网页打开本章", "safari", enabled: currentChapterWebURL != nil, leavesReader: true) { showChapterWebPage = true }
        ]
        if canShowPayAction {
            chapterActions.append(action("购买本章", "cart", enabled: !isPerformingPayAction, leavesReader: true) { showPayActionConfirmation = true })
        }
        let playback: [UIMenuElement] = [
            action(autoScrollEnabled ? "暂停自动翻页" : "开始自动翻页", autoScrollEnabled ? "pause.fill" : "play.fill") { toggleAutoScroll() }
        ]
        let bookActions: [UIMenuElement] = [
            action("全书关键词搜索", "magnifyingglass", leavesReader: false) {
                closeReaderChromeFromMenu()
                tocTab = 2
                showChapterList = true
            },
            action("AI 前情提要（无剧透）", "sparkles", leavesReader: true) {
                openAISpoilerFreeRecap()
            },
            action("书籍详情", "info.circle", leavesReader: true) {
                if appState.bookshelfStore.book(id: bookID)?.sourceURL.hasPrefix("local://") == true {
                    showBookDetailSheet = true
                } else if let onRequestBookDetail { onRequestBookDetail() } else { showBookDetailSheet = true }
            },
            action("内容过滤", "line.3.horizontal.decrease.circle", leavesReader: true) { showContentFilter = true },
            action("登录书源", "person.badge.key", enabled: currentBookSource != nil, leavesReader: true) { readerLoginSource = currentBookSource }
        ]
        return UIMenu(children: [
            UIMenu(options: .displayInline, children: chapterActions),
            UIMenu(options: .displayInline, children: playback),
            UIMenu(options: .displayInline, children: bookActions)
        ])
    }

    private func closeSettingsPanel() {
        guard showSettings else { return }
        chromeCoordinator.state.closeSettings()
    }

    private func settingsTabButton(title: String, tag: Int) -> some View {
        Button {
            chromeCoordinator.settingsTab = tag
        } label: {
            Text(title)
                .font(.subheadline.weight(settingsTab == tag ? .semibold : .regular))
                .foregroundStyle(settingsTab == tag ? .white : readerThemeTextColor.opacity(0.75))
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background {
                    if settingsTab == tag {
                        Capsule().fill(AppTheme.accent)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private var appearanceSettings: ReaderSettingsContent {
        ReaderSettingsContent { appearanceSettingsBody(showsPreview: true) }
    }

    private func appearanceSettingsBody(showsPreview: Bool) -> some View {
        Group {
            if showsPreview { appearancePreview }
            readerModeSection
            perBookOverrideToggle
            backgroundPickerSection
            if background == .custom {
                customWallpaperSection
            }
            nightPaperAndInkSection
            readerBrightnessSection
        }
    }

    private var nightPaperAndInkSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("正文纸张随系统深色切换", isOn: $followSystemPaper)
                .font(.subheadline.weight(.semibold))

            readerValueSlider(
                "文字不透明度",
                value: $inkOpacity,
                range: 0.55...1.0,
                step: 0.05,
                unit: "",
                help: ""
            )

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("正文墨色")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(readerThemeTextColor.opacity(0.72))
                    Spacer()
                    if !customInkHexRaw.isEmpty {
                        Button("恢复主题配色") {
                            customInkHexRaw = ""
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.accent)
                    }
                }

                HStack(spacing: 10) {
                    let presets: [(String, String)] = [
                        ("1C1E21", "墨黑"),
                        ("2C3E50", "黛青"),
                        ("4A3728", "深褐"),
                        ("EDE6D6", "暖白"),
                        ("D6B46A", "星金")
                    ]
                    ForEach(presets, id: \.0) { hex, label in
                        let selected = customInkHexRaw.uppercased() == hex
                        Button {
                            customInkHexRaw = selected ? "" : hex
                            HapticFeedback.light()
                        } label: {
                            Circle()
                                .fill(Color(hex: UInt32(hex, radix: 16) ?? 0x1C1E21))
                                .frame(width: 26, height: 26)
                                .overlay {
                                    Circle().stroke(
                                        selected ? AppTheme.accent : readerThemeTextColor.opacity(0.24),
                                        lineWidth: selected ? 2.2 : 0.8
                                    )
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(label)
                    }
                }
            }
        }
    }

    private var readerModeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("翻页模式")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(readerThemeTextColor.opacity(0.62))
            Text(readerModeHint)
                .font(.caption2)
                .foregroundStyle(readerThemeTextColor.opacity(0.62))
            BrandSegmentedControl("翻页模式", selection: $readerModeRawValue, options:
                            ReaderMode.allCases.map { ($0.rawValue, $0.title) })
            .padding(.bottom, 8)
        }
    }

    private var perBookOverrideToggle: some View {
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
    }

    private var backgroundPickerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("阅读背景 · 纸纹与插画")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(readerThemeTextColor.opacity(0.62))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(ReaderBackground.pickerCases) { item in
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            backgroundRawValue = item.rawValue
                            if item == .custom {
                                customBackgroundIsDark = ReaderCustomWallpaperStore.isWallpaperDark
                            }
                        } label: {
                            VStack(spacing: 4) {
                                ZStack {
                                    item.color(isNight: item.isDark)
                                    if item.hasTexture { ReaderPaperTextureView(background: item, night: item.isDark) }
                                }
                                    .frame(width: 40, height: 40)
                                    .clipShape(Circle())
                                    .overlay {
                                        Circle()
                                            .stroke(background == item ? AppTheme.accent : readerThemeTextColor.opacity(0.25), lineWidth: background == item ? 3 : 1)
                                    }
                                Text(item.title)
                                    .font(.caption2)
                                    .foregroundStyle(background == item ? AppTheme.accent : readerThemeTextColor.opacity(0.62))
                            }
                        }
                        .accessibilityLabel(item.title)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private var customWallpaperSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                HStack(spacing: 8) {
                    Image(systemName: "photo.badge.plus")
                    Text(ReaderCustomWallpaperStore.hasCustomWallpaper ? "更换自定义壁纸" : "从相册选择壁纸")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundStyle(AppTheme.accent)
            }
            .onChange(of: selectedPhotoItem) { item in
                guard let item else { return }
                prepareWallpaper(from: item)
            }
            .disabled(isPreparingWallpaper)

            if isPreparingWallpaper { Text("正在准备壁纸预览…").font(.caption) }
            if let wallpaperMessage { Text(wallpaperMessage).font(.caption).foregroundStyle(.secondary) }
            if ReaderCustomWallpaperStore.hasCustomWallpaper {
                Button("编辑已保存壁纸") {
                    openSavedWallpaperEditor()
                }.buttonStyle(.bordered)
            }

            BrandSegmentedControl("壁纸基底与文字风格", selection: $customBackgroundIsDark, options:
                            [(false, "浅色壁纸 (深色字)"), (true, "深色壁纸 (浅色字)")])
            .padding(.top, 2)
            .onChange(of: customBackgroundIsDark) { newValue in
                UserDefaults.standard.set(true, forKey: "reader.customBackgroundIsDarkManual")
                UserDefaults.standard.set(newValue, forKey: "reader.customBackgroundIsDark")
                backgroundWallpaperRevision = UUID()
                rebuildPagedBlocksCacheAsync()
            }

            BrandSegmentedControl("壁纸填充方式", selection: $customWallpaperFillModeRaw, options:
                            ReaderWallpaperFillMode.allCases.map { ($0.rawValue, $0.title) })
            .padding(.top, 2)

            if ReaderCustomWallpaperStore.hasCustomWallpaper {
                Button(role: .destructive) {
                    confirmClearWallpaper = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text("删除自定义壁纸，恢复素白背景")
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                }
                .padding(.top, 2)
                .confirmationDialog("删除自定义壁纸？裁切与原图将一并移除。", isPresented: $confirmClearWallpaper, titleVisibility: .visible) {
                    Button("删除自定义壁纸", role: .destructive) {
                        Task { @MainActor in
                            do {
                                try await ReaderCustomWallpaperStore.clearEditedWallpaper()
                                backgroundRawValue = ReaderBackground.white.rawValue
                                backgroundWallpaperRevision = UUID(); rebuildPagedBlocksCacheAsync()
                            } catch { wallpaperMessage = "删除未完成，请重试。" + error.localizedDescription }
                        }
                    }
                    Button("保留壁纸", role: .cancel) {}
                }
            }

            Text(ReaderCustomWallpaperStore.hasCustomWallpaper
                 ? "壁纸已生效，支持自主切换浅色/深色文字样式以保证最佳对比度。"
                 : "可从相册选择壁纸，支持自由搭配浅色或深色文字。")
                .font(.caption2)
                .foregroundStyle(readerThemeTextColor.opacity(0.42))
        }
    }

    private func prepareWallpaper(from item: PhotosPickerItem) {
        wallpaperImportTask?.cancel()
        let revision = UUID(); wallpaperImportRevision = revision
        isPreparingWallpaper = true; wallpaperMessage = nil
        wallpaperImportTask = Task { @MainActor in
            defer { if wallpaperImportRevision == revision { isPreparingWallpaper = false } }
            do {
                guard let bytes = try await item.loadTransferable(type: Data.self) else { throw ReaderWallpaperFailure.invalidImage }
                let snapshot = try await Task.detached(priority: .userInitiated) {
                    let image = try ReaderWallpaperRepository.decodeImage(bytes)
                    var adjustment = ReaderWallpaperAdjustment(); adjustment.usesLightText = image.isDarkPerception
                    return ReaderWallpaperSnapshot(image: image, adjustment: adjustment)
                }.value
                guard !Task.isCancelled, wallpaperImportRevision == revision else { return }
                wallpaperDraft = ReaderWallpaperDraft(image: snapshot.image, adjustment: snapshot.adjustment, viewportSize: effectiveViewportSize)
                selectedPhotoItem = nil
            } catch {
                if !Task.isCancelled, wallpaperImportRevision == revision { wallpaperMessage = error.localizedDescription }
            }
        }
    }

    private var readerBrightnessSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("阅读亮度")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(readerThemeTextColor.opacity(0.62))
                Spacer()
                Text(readerBrightness < 0 ? "自动亮度" : "\(Int(readerBrightness * 100))%")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.accent)
                Button("跟随系统") {
                    readerBrightness = -1
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(readerBrightness < 0 ? readerThemeTextColor.opacity(0.45) : AppTheme.accent)
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
                .foregroundStyle(readerThemeTextColor.opacity(0.42))
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
                .stroke(readerThemeTextColor.opacity(background.isDark ? 0.12 : 0.06), lineWidth: 0.8)
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
                    .stroke(Color.white.opacity(background.isDark ? 0.08 : 0.35), lineWidth: 0.8)
            }
            .padding(.horizontal, 18)
            .padding(.top, readerTopSafeInset + 12)

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
                        .foregroundStyle(readerThemeTextColor.opacity(0.62))
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
            .padding(.top, readerTopSafeInset + (statusMessage == nil ? 12 : 58))

            Spacer()
        }
        .animation(.easeInOut(duration: 0.2), value: message)
        .accessibilityIdentifier("reader.speechErrorBanner")
    }

    private var layoutSettings: ReaderSettingsContent {
        ReaderSettingsContent { layoutSettingsBody(showsPreview: true) }
    }

    private func layoutSettingsBody(showsPreview: Bool, includesLegacySections: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if showsPreview { appearancePreview }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("字体")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(readerThemeTextColor.opacity(0.62))
                    Spacer()
                    Button {
                        showFontManagementSheet = true
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
                                            : readerThemeTextColor.opacity(0.10)
                                    )
                                    .foregroundColor(
                                        fontFamilyRawValue == item.rawValue ? .white : readerThemeTextColor
                                    )
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(ReaderControlPressStyle())
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("快速排版预设")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(readerThemeTextColor.opacity(0.65))
                HStack(spacing: 8) {
                    ForEach(ReaderTypographyPreset.allCases) { preset in
                        Button {
                            fontSize = preset.fontSize
                            lineSpacing = preset.lineSpacing
                            paragraphSpacing = preset.paragraphSpacing
                            paragraphIndent = preset.paragraphIndent
                            pagePadding = preset.pagePadding
                            verticalPadding = preset.verticalPadding
                            HapticFeedback.medium()
                            schedulePagedBlocksCacheRebuild()
                        } label: {
                            VStack(spacing: 2) {
                                Text(preset.title)
                                    .font(.caption.weight(.semibold))
                                Text(preset.subtitle)
                                    .font(.system(size: 10))
                                    .opacity(0.72)
                            }
                            .foregroundStyle(readerThemeTextColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(readerThemeTextColor.opacity(0.065), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(ReaderControlPressStyle())
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("正文字重")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(readerThemeTextColor.opacity(0.65))
                BrandSegmentedControl("字重", selection: $fontWeightRawValue, options:
                    ReaderBodyFontWeight.allCases.map { ($0.rawValue, $0.title) })
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("对齐与标点")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(readerThemeTextColor.opacity(0.65))
                BrandSegmentedControl("对齐", selection: $textAlignmentRawValue, options:
                    ReaderTextAlignment.allCases.map { ($0.rawValue, $0.title) })
            }

            // 1. 段落差（段间距）
            readerValueSlider("段落差（段间距）", value: $paragraphSpacing, range: 0...28, step: 1, unit: "pt", help: "")

            // 2. 正文字号
            readerValueSlider("正文字号", value: $fontSize, range: 12...34, step: 1, unit: "pt", help: "")

            // 3. 行距
            readerValueSlider("行距", value: $lineSpacing, range: 0...18, step: 1, unit: "pt", help: "")

            // 4. 段首缩进
            readerValueSlider("段首缩进", value: $paragraphIndent, range: 0...50, step: 2, unit: "pt", help: "")

            // 5. 字间距
            readerValueSlider("字间距（字距）", value: $letterSpacing, range: 0...4, step: 0.2, unit: "pt", help: "")

            // 6. 左右边距
            readerValueSlider("屏幕左右留白", value: $pagePadding, range: 10...40, step: 1, unit: "pt", help: "")

            // 7. 上下留白
            readerValueSlider("屏幕上下留白", value: $verticalPadding, range: 0...36, step: 2, unit: "pt", help: "")

            Toggle("智能分段/空行净化", isOn: $smartLineCleanup)
                .font(.subheadline.weight(.semibold))

            Toggle("繁体中文显示（简转繁）", isOn: $traditionalChineseEnabled)
                .font(.subheadline.weight(.semibold))

            if includesLegacySections { legacyLayoutHeadingControls }

            Button {
                applyReaderTypographyPreset(includesLegacySections: includesLegacySections)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "wand.and.stars")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("应用纸间推荐排版").font(.subheadline.weight(.semibold))
                        Text("调整正文的字号、行距、段距、边距和首行缩进。")
                            .font(.caption2)
                            .foregroundStyle(readerThemeTextColor.opacity(0.62))
                    }
                    Spacer()
                }
                .padding(12)
                .background(AppTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)

            if includesLegacySections { legacyLayoutStatusControls }
        }
    }

    @ViewBuilder private var legacyLayoutHeadingControls: some View {
        // 7. 章节标题
        VStack(alignment: .leading, spacing: 8) {
            Text("章节标题位置")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(readerThemeTextColor.opacity(0.62))
            BrandSegmentedControl("章节标题位置", selection: $chapterHeadingStyleRaw, options:
                            ReaderPageChromeLayout.allCases.map { ($0.rawValue, $0.title) })
            Text(chapterHeadingStyle.help)
                .font(.caption2)
                .foregroundStyle(readerThemeTextColor.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
        }

        VStack(alignment: .leading, spacing: 10) {
            Text("章节名 · 独立排版").font(.headline)
            Toggle("章节名加粗", isOn: $chapterTitleBold)
            Picker("章节名字体", selection: $chapterTitleFamilyRaw) {
                Text("跟随正文").tag("")
                ForEach(ReaderFontFamily.allCases) { family in Text(family.title).tag(family.rawValue) }
            }
            readerValueSlider("章节名字号", value: Binding(get: { resolvedTitleSize }, set: { chapterTitleSize = $0 }), range: 14...44, step: 1, unit: "pt", help: "只改变章节名，不改变正文字号；滚动与分页模式共用。")
            Button("章节名字号跟随正文") { chapterTitleSize = 0 }
        }

        VStack(alignment: .leading, spacing: 10) {
            Text("页眉 · 独立排版").font(.headline)
            readerValueSlider("页眉字号", value: $headerFontSize, range: 9...18, step: 1, unit: "pt", help: "增大字号会同步预留页眉高度，不覆盖正文。")
            readerValueSlider("页眉顶部间距", value: $headerTopGap, range: 0...24, step: 1, unit: "pt", help: "从安全区下沿开始计算，避免挡住灵动岛。")
            readerValueSlider("页眉文字浓度", value: $headerOpacity, range: 0.35...1, step: 0.05, unit: "", help: "独立于正文颜色；背景图仍连续覆盖顶部。")
            Toggle("系统状态栏可见时仍重复顶部时间电量", isOn: $allowsDuplicateTopStatus)
        }

        readerValueSlider("章节标题间距", value: $titleSpacing, range: 0...36, step: 2, unit: "pt", help: "仅「正文大标题」模式生效：大章节标题与正文第一行之间的垂直留白（推荐 8~16pt）。页眉模式不占用正文高度。")

        Toggle("内容延伸至页眉页脚区域", isOn: $contentExtendsIntoChrome)
            .font(.subheadline.weight(.semibold))
    }

    @ViewBuilder private var legacyLayoutStatusControls: some View {
        // 8. 底部安全留白
        readerValueSlider("底部安全留白", value: $footerHeight, range: 40...180, step: 8, unit: "pt", help: "屏幕最底部向上预留的安全空隙，防止手势遮挡最后一行正文（推荐 80~100pt）")

        // 9. 页脚内容开关。对照同类阅读器（香色闺阁的 tr_showTime / tr_showBatView /
        // tr_showBatLabel 就是三个独立开关），把「时间 / 电量图标 / 电量百分比」拆开，
        // 全屏时不想看就不显示，也就不存在「位置奇怪」这件事。
        VStack(alignment: .leading, spacing: 10) {
            Text("页眉与页脚状态栏")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(readerThemeTextColor.opacity(0.62))

            HStack {
                Text("状态栏位置")
                Spacer()
                BrandSegmentedControl("位置", selection: $statusPosition, options:
                            [("bottom", "仅页脚"), ("top", "仅页眉"), ("both", "页眉+页脚")])
                .frame(width: 200)
            }

            Toggle("始终保留系统原生状态栏", isOn: $showSystemStatusBar)
            Toggle("显示时间", isOn: $footerShowTime)
            Toggle("显示电量图标", isOn: $footerShowBatteryIcon)
            Toggle("显示电量百分比", isOn: $footerShowBatteryPercent)
        }
        .font(.subheadline)
    }

    /// 1.0.64 shipped `paragraphSpacing = 0`, which made every paragraph touch
    /// the previous one. Raise only the untouched legacy defaults so a reader
    /// who deliberately picked a tighter value keeps it.
    private func migrateTypographyDefaultsIfNeeded() {
        if !typographyMigratedV65 {
            if paragraphSpacing == 0 {
                paragraphSpacing = ReaderTypographyDefaults.paragraphSpacing
            }
            if titleSpacing == 8 {
                titleSpacing = ReaderTypographyDefaults.titleSpacing
            }
            typographyMigratedV65 = true
        }
        if !typographyMigratedV66 {
            // 1.0.65 defaults: lineSpacing 12 / paragraphSpacing 10.
            if lineSpacing == 12 {
                lineSpacing = ReaderTypographyDefaults.lineSpacing
            }
            if paragraphSpacing == 10 {
                paragraphSpacing = ReaderTypographyDefaults.paragraphSpacing
            }
            typographyMigratedV66 = true
        }
    }

    private func applyReaderTypographyPreset(includesLegacySections: Bool) {
        defer {
            HapticFeedback.medium()
            schedulePagedBlocksCacheRebuild()
        }
        fontSize = 20
        lineSpacing = ReaderTypographyDefaults.lineSpacing
        pagePadding = 21
        verticalPadding = 0
        paragraphIndent = 40
        paragraphSpacing = ReaderTypographyDefaults.paragraphSpacing
        fontWeightRawValue = ReaderBodyFontWeight.regular.rawValue
        textAlignmentRawValue = ReaderTextAlignment.smart.rawValue
        smartLineCleanup = false
        guard includesLegacySections else { return }
        titleSpacing = ReaderTypographyDefaults.titleSpacing
        chapterHeadingStyleRaw = ReaderPageChromeLayout.header.rawValue
        contentExtendsIntoChrome = false
        statusPosition = "bottom"
        footerShowTime = true
        footerShowBatteryIcon = true
        footerShowBatteryPercent = true
    }

    private var advancedSettings: ReaderSettingsContent {
        ReaderSettingsContent { advancedSettingsBody }
    }

    private var advancedSettingsBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("高级里只放阅读辅助，不再重复前面的翻页和字号入口。朗读速度只管语速，自动滚动在主阅读菜单。")
                .font(.caption)
                .foregroundStyle(readerThemeTextColor.opacity(0.62))

            readerValueSlider(
                "自动滚动间隔",
                value: $autoScrollDelay,
                range: ReaderAutomationPolicy.minDelay...ReaderAutomationPolicy.maxDelay,
                step: 0.25,
                unit: "秒",
                help: "自动滚动间隔最长 60 秒，数值越大滚动越慢；运行中修改立即重新计时。朗读与自动滚动互斥。"
            )

            readerValueSlider("朗读速度", value: $ttsRate, range: 0.35...0.65, step: 0.01, unit: "倍速", help: "调整语音朗读语速（0.35x ~ 0.65x），从当前可见段落开始朗读，不会跳回章节开头")

            Text("睡眠定时")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(readerThemeTextColor.opacity(0.62))
            BrandSegmentedControl("睡眠定时", selection: $sleepTimerMinutes, options:
                            [(0, "关闭"), (-1, "播完当章"), (15, "15 分钟"), (30, "30 分钟"), (60, "60 分钟")])

            Toggle("阅读时保持屏幕常亮", isOn: $keepScreenAwake)
                .font(.subheadline.weight(.semibold))

            Toggle("允许正文文字选择", isOn: $textSelectionEnabled)
                .font(.subheadline.weight(.semibold))

            Toggle("繁体中文显示（简转繁）", isOn: $traditionalChineseEnabled)
                .font(.subheadline.weight(.semibold))

            Toggle("仿生阅读（Bionic Reading 词首加粗）", isOn: $bionicReadingEnabled)
                .font(.subheadline.weight(.semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text("插图排版样式")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(readerThemeTextColor.opacity(0.62))
                BrandSegmentedControl("插图排版样式", selection: $globalImageStyleRaw, options:
                            ReaderImageStyle.allCases.map { ($0.rawValue, $0.title) })
            }

            settingStepper(title: "预加载章节", value: ReaderPreloadPolicy.title(for: preloadChapterCount)) {
                preloadChapterCount = ReaderPreloadPolicy.clamp(preloadChapterCount - 1)
            } increase: {
                preloadChapterCount = ReaderPreloadPolicy.clamp(preloadChapterCount + 1)
            }

            Toggle("物理音量键翻页（朗读时自动让渡）", isOn: $volumeKeyPageTurn)
                .font(.subheadline.weight(.semibold))

            ReaderAmbientControlsSection(
                enabled: $ambientSoundEnabled,
                presetRaw: $ambientSoundPresetRaw,
                volume: $ambientSoundVolume,
                timerMinutes: $ambientTimerMinutes,
                textColor: readerThemeTextColor
            )

            tapZoneSettings
        }
    }

    private func openSavedWallpaperEditor() {
        Task { @MainActor in
            await ReaderCustomWallpaperStore.warmWallpaper()
            guard let image = ReaderCustomWallpaperStore.cachedWallpaper else {
                wallpaperMessage = ReaderCustomWallpaperStore.lastError ?? "壁纸无法读取，请重新选择图片。"
                return
            }
            var adjustment = ReaderCustomWallpaperStore.adjustment
            adjustment.fillMode = ReaderWallpaperFillMode(rawValue: customWallpaperFillModeRaw) ?? .fill
            adjustment.usesLightText = customBackgroundIsDark
            wallpaperDraft = ReaderWallpaperDraft(image: image, adjustment: adjustment, viewportSize: effectiveViewportSize)
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
        let _ = help
        return ReaderSettingsContent {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(readerThemeTextColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .layoutPriority(1)

                    Spacer(minLength: 6)

                    ReaderNumberInput(
                        title: title,
                        value: value,
                        range: range,
                        step: step,
                        unit: unit
                    )
                }

                HStack(spacing: 12) {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        value.wrappedValue = max(range.lowerBound, (value.wrappedValue - step))
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(value.wrappedValue <= range.lowerBound ? readerThemeTextColor.opacity(0.25) : readerControlAccent)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .disabled(value.wrappedValue <= range.lowerBound)
                    .buttonStyle(ReaderControlPressStyle())

                    Slider(value: value, in: range, step: step)
                        .tint(readerControlAccent)

                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        value.wrappedValue = min(range.upperBound, (value.wrappedValue + step))
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(value.wrappedValue >= range.upperBound ? readerThemeTextColor.opacity(0.25) : readerControlAccent)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .disabled(value.wrappedValue >= range.upperBound)
                    .buttonStyle(ReaderControlPressStyle())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(readerThemeTextColor.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.vertical, 1)
        }
    }

    private var tapZoneSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("九宫格点击区域")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(readerThemeTextColor.opacity(0.62))
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
                .foregroundStyle(readerThemeTextColor.opacity(0.62))
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
                    } else if tocTab == 1 {
                        bookmarkList(includeAddButton: true)
                    } else {
                        inBookSearchTabView
                    }
                }
            }
            // List 自带 systemBackground，叠在主题背景上就是「章节 (N)」下面那条白带。
            // 把滚动内容背景设为透明，让 readerBackdrop 透上来；行背景已经是 clear。
            .scrollContentBackground(.hidden)
            .background(readerThemeBackground.ignoresSafeArea())
            .navigationTitle(tocTab == 0 ? "目录" : (tocTab == 1 ? "书签" : "全书搜索"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if tocTab == 0 {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(tocReversed ? "倒序" : "顺序") {
                            tocScrollTask?.cancel()
                            tocScrollTask = nil
                            tocScrollIntent = .firstRow
                            tocUserHasScrolled = false
                            var transaction = Transaction()
                            transaction.disablesAnimations = true
                            withTransaction(transaction) { tocReversed.toggle() }
                        }
                        .foregroundStyle(readerThemeTextColor)
                    }
                } else if tocTab == 1 && !bookmarks.isEmpty {
                    ToolbarItem(placement: .navigationBarLeading) {
                        bookmarkExportMenu
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
            .toolbarColorScheme(background.isDark ? .dark : .light, for: .navigationBar)
            .sheet(item: $bookmarkExportURL) { item in
                ShareSheet(items: [item.url])
            }
            .onDisappear {
                inBookSearchTask?.cancel()
                inBookSearchTask = nil
            }
        }
        .readerSheetPresentation(color: readerThemeBackground)
        // 目录固定全屏：带 .medium 时 SwiftUI 默认选最小 detent，每次都要手动上拉。
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .tint(AppTheme.accent)
        .preferredColorScheme(background.isDark ? .dark : .light)
    }

    private var customTocSegmentedPicker: some View {
        HStack(spacing: 0) {
            tocTabButton(title: "目录", tag: 0)
            tocTabButton(title: "书签", tag: 1)
            tocTabButton(title: "搜全书", tag: 2)
        }
        .padding(3)
        .background(readerThemeTextColor.opacity(background.isDark ? 0.16 : 0.08), in: Capsule())
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
        // List asks every row for its identity up front. Never let that pass
        // rescan the complete TOC once per row (canJump -> upperBound -> map).
        let visibleChapters = filteredChapters
        let visibleNavigationEntries = filteredNavigationEntries
        let currentIndex = currentDisplayChapterIndex
        let upperBound = windowChapterUpperBound
        let readyIndices = readyWindowIndices
        let ownerCanLoad = onSelectChapter != nil || onSelectChapterWithPosition != nil
        return VStack(spacing: 8) {
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

            // 没有 ScrollViewReader 时，每次打开目录都停在第一行：
            // 读了两百章再点目录，还要自己往下翻。这里用行 identity
            // 直接定位到当前阅读章。
            ScrollViewReader { proxy in
            List {
                if chapters.isEmpty && navigationEntries.isEmpty {
                    Text("当前章节没有可切换目录")
                        .foregroundStyle(readerThemeTextColor.opacity(0.6))
                        .listRowBackground(Color.clear)
                } else if visibleChapters.isEmpty && visibleNavigationEntries.isEmpty {
                    Text("没有匹配章节")
                        .foregroundStyle(readerThemeTextColor.opacity(0.6))
                        .listRowBackground(Color.clear)
                } else {
                    if !visibleChapters.isEmpty {
                        Section {
                            // Stable presentation slots avoid moving every
                            // identity (or recreating the List) on reversal.
                            // Selection still uses the actual chapter index.
                            ForEach(visibleChapters.indices, id: \.self) { row in
                                let chapter = visibleChapters[row]
                                Button {
                                    // Apply the jump before dismissing the sheet:
                                    // `showChapterList = false` tears the window down
                                    // with the old chapter, and a jump landing in the
                                    // same runloop was dropped — after which the reader
                                    // could not continue into the next chapter.
                                    presentOverlay()
                                    selectChapter(index: chapter.index)
                                    showChapterList = false
                                } label: {
                                    TocChapterRow(
                                        index: chapter.index,
                                        title: chapter.title,
                                        isCurrent: chapter.index == currentIndex,
                                        textColor: readerThemeTextColor
                                    )
                                    .equatable()
                                }
                                .buttonStyle(.plain)
                                .disabled(chapter.index == currentIndex || !(readyIndices.contains(chapter.index)
                                    || (chapter.index >= 0 && chapter.index < upperBound) || ownerCanLoad))
                                .listRowInsets(EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 16))
                                .listRowBackground(Color.clear)
                                .listRowSeparatorTint(readerThemeTextColor.opacity(0.15))
                            }
                        } header: {
                            Text("章节 (\(visibleChapters.count))")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(readerThemeTextColor.opacity(0.65))
                        }
                    }
                    if !visibleNavigationEntries.isEmpty {
                        Section {
                            ForEach(Array(visibleNavigationEntries.enumerated()), id: \.offset) { offset, entry in
                                Button {
                                    presentOverlay()
                                    onSelectNavigationEntry?(entry)
                                    showChapterList = false
                                } label: {
                                    navigationEntryRow(entry, ordinal: offset)
                                }
                                .id("toc-nav-\(offset)")
                                .disabled(onSelectNavigationEntry == nil || entry.chapterIndex == nil)
                                .listRowInsets(EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 16))
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
            .simultaneousGesture(DragGesture(minimumDistance: 3).onChanged { _ in
                guard !tocUserHasScrolled else { return }
                tocUserHasScrolled = true
                tocScrollTask?.cancel()
                tocScrollTask = nil
            })
            .onAppear {
                // 首帧的行还没建出来，同一 runloop 里 scrollTo 会落空，
                // 挪到下一拍再滚动。
                tocUserHasScrolled = false
                scrollTocToCurrentChapter(proxy)
            }
            .onChange(of: tocReversed) { _ in
                scrollTocToCurrentChapter(proxy)
            }
            .onChange(of: debouncedTocQuery) { _ in
                tocScrollIntent = .firstRow
                scrollTocToCurrentChapter(proxy)
            }
            .onChange(of: chapters.count) { _ in
                if !tocUserHasScrolled { scrollTocToCurrentChapter(proxy) }
            }
            }
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
                .foregroundStyle(chapter.index == currentDisplayChapterIndex ? AppTheme.accent : readerThemeTextColor.opacity(0.55))
                .frame(width: 48, alignment: .leading)
            Text(chapter.title)
                .foregroundStyle(chapter.index == currentDisplayChapterIndex ? AppTheme.accent : readerThemeTextColor)
                .fontWeight(chapter.index == currentDisplayChapterIndex ? .semibold : .regular)
                .lineLimit(1)
            Spacer()
            if chapter.index == currentDisplayChapterIndex {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppTheme.accent)
            }
        }
    }

    /// 打开目录定位当前章；手动排序或筛选定位新列表首行。
    private func scrollTocToCurrentChapter(_ proxy: ScrollViewProxy) {
        let id: AnyHashable
        if let row = tocScrollIntent.row(in: filteredChapters, preferred: windowCurrentChapterIndex,
                                        fallback: currentDisplayChapterIndex) {
            id = AnyHashable(row)
        } else if !filteredNavigationEntries.isEmpty {
            id = AnyHashable("toc-nav-0")
        } else { return }
        tocScrollTask?.cancel()
        tocScrollTask = Task { @MainActor in
            await Task.yield()
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled, showChapterList else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { proxy.scrollTo(id, anchor: tocScrollIntent == .firstRow ? .top : .center) }
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
                        if !bookmarks.isEmpty {
                            ToolbarItem(placement: .navigationBarLeading) {
                                bookmarkExportMenu
                            }
                        }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("完成") {
                                showBookmarks = false
                            }
                            .foregroundStyle(readerThemeTextColor)
                        }
                    }
            }
            .toolbarBackground(readerThemeBackground, for: .navigationBar)
            .toolbarColorScheme(background.isDark ? .dark : .light, for: .navigationBar)
            .sheet(item: $bookmarkExportURL) { item in
                ShareSheet(items: [item.url])
            }
            .alert("导出失败", isPresented: Binding(
                get: { bookmarkExportError != nil },
                set: { if !$0 { bookmarkExportError = nil } }
            )) {
                Button("好", role: .cancel) { bookmarkExportError = nil }
            } message: {
                Text(bookmarkExportError ?? "")
            }
        }
        .readerSheetPresentation(color: readerThemeBackground)
        .presentationDetents([.large])
        .tint(AppTheme.accent)
        .preferredColorScheme(background.isDark ? .dark : .light)
    }

    private var bookmarkExportMenu: some View {
        Menu {
            Button {
                exportCurrentBookBookmarks(asMarkdown: true)
            } label: {
                Label("导出 Markdown (.md)", systemImage: "doc.richtext")
            }
            Button {
                exportCurrentBookBookmarks(asMarkdown: false)
            } label: {
                Label("导出纯文本 (.txt)", systemImage: "doc.plaintext")
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
                .foregroundStyle(readerThemeTextColor)
        }
        .accessibilityLabel("导出本书书签")
    }

    private var inBookSearchTabView: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(readerThemeTextColor.opacity(0.55))
                    TextField("搜索已加载或已缓存章节中的关键词…", text: $inBookSearchQuery)
                        .textFieldStyle(.plain)
                        .foregroundStyle(readerThemeTextColor)
                        .submitLabel(.search)
                        .onSubmit { runInBookSearch() }
                    if !inBookSearchQuery.isEmpty {
                        Button {
                            inBookSearchQuery = ""
                            inBookSearchHits = []
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(readerThemeTextColor.opacity(0.45))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(readerThemeTextColor.opacity(background.isDark ? 0.14 : 0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(.horizontal)
            .padding(.top, 10)

            HStack {
                if inBookSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("将检索当前窗口章节、本地书籍全文与已离线缓存章节（已扫描 \(inBookSearchScannedCount) 章）")
                } else {
                    Text("在 \(inBookSearchScannedCount) 章中找到 \(inBookSearchHits.count) 处匹配")
                }
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(readerThemeTextColor.opacity(0.6))
            .padding(.horizontal)

            List {
                if inBookSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("输入人名、地名或剧情关键词即可精确跳转到对应章节与段落。")
                        .font(.subheadline)
                        .foregroundStyle(readerThemeTextColor.opacity(0.6))
                        .listRowBackground(Color.clear)
                } else if inBookSearchHits.isEmpty {
                    Text("已检索的 \(inBookSearchScannedCount) 章中暂无匹配内容。若部分网络章节尚未缓存，可先在目录菜单批量缓存后再搜。")
                        .font(.subheadline)
                        .foregroundStyle(readerThemeTextColor.opacity(0.6))
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(inBookSearchHits) { hit in
                        Button {
                            jumpToInBookSearchHit(hit)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(hit.chapterTitle)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(AppTheme.accent)
                                        .lineLimit(1)
                                    Spacer()
                                    Text("第 \(hit.chapterIndex + 1) 章 · 第 \(hit.paragraphIndex + 1) 段")
                                        .font(.caption2)
                                        .foregroundStyle(readerThemeTextColor.opacity(0.5))
                                }
                                Text(hit.previewText)
                                    .font(.subheadline)
                                    .foregroundStyle(readerThemeTextColor)
                                    .lineLimit(3)
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(readerThemeTextColor.opacity(0.15))
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .onAppear { runInBookSearch() }
        .onChange(of: inBookSearchQuery) { _ in
            runInBookSearch()
        }
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
                                if bookmark.chapterIndex == currentDisplayChapterIndex {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(AppTheme.accent)
                                } else {
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(readerThemeTextColor.opacity(0.35))
                                }
                            }
                        }
                        .disabled(
                            bookmark.chapterIndex == currentDisplayChapterIndex
                                ? false
                                : !canJump(to: bookmark.chapterIndex)
                        )
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
        bookmark.chapterIndex == currentDisplayChapterIndex
            && bookmark.paragraphIndex == currentBookmarkParagraphIndex
    }

    private func jumpToBookmark(_ bookmark: ReaderBookmark) {
        showBookmarks = false
        closeReaderChrome()
        if windowSections.contains(where: { $0.chapterIndex == bookmark.chapterIndex && $0.isReady }) {
            jumpToWindowChapter(bookmark.chapterIndex, paragraphIndex: bookmark.paragraphIndex ?? 0)
            return
        }
        guard bookmark.chapterIndex >= 0, bookmark.chapterIndex < windowChapterUpperBound else { return }
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
        // Load the chapter into the live window instead of asking the owner
        // to rebuild the reader: the owner callback replaced the web view and
        // threw away the scroll position.
        beginWindowJump(to: bookmark.chapterIndex, paragraphIndex: paragraphIndex ?? 0)
    }

    private func jumpToParagraph(_ paragraphIndex: Int?) {
        guard let paragraphIndex else { return }
        guard let flat = windowLayout.flatIndex(
            chapterIndex: windowCurrentChapterIndex,
            paragraphIndex: paragraphIndex
        ) else { return }
        jumpToWindowFlat(flat, paragraphIndex: paragraphIndex)
    }

    /// Moves both surfaces to a flat paragraph index in the live window.
    private func jumpToWindowFlat(_ flatIndex: Int, paragraphIndex: Int) {
        let safeFlat = min(max(flatIndex, 0), max(windowLayout.totalCount - 1, 0))
        visibleParagraphIndex = safeFlat
        switch readerMode {
        case .scroll:
            scrollParagraphTarget = safeFlat
            scrollJumpGeneration &+= 1
            paragraphJumpRequest = ParagraphJumpRequest(index: safeFlat)
        case .pageTurn, .cover, .pageCurl:
            pagedPageIndex = pageIndex(containingParagraph: safeFlat)
        }
        persistReadingPosition(paragraphIndexOverride: paragraphIndex)
    }

    private func activateWindowChapter(
        _ index: Int,
        startAtEnd: Bool = false,
        paragraphIndex: Int? = nil
    ) {
        guard let section = windowSections.first(where: { $0.chapterIndex == index && $0.isReady }) else { return }
        let fallback = startAtEnd ? max(section.paragraphs.count - 1, 0) : 0
        jumpToWindowChapter(index, paragraphIndex: paragraphIndex ?? fallback)
    }

    /// Jumps inside the already-loaded window without asking the owner to
    /// rebuild the reader. This is what makes TOC and bookmark navigation
    /// instant while the user has prefetched neighbours in memory.
    private func jumpToWindowChapter(_ index: Int, paragraphIndex: Int) {
        guard let section = windowSections.first(where: { $0.chapterIndex == index && $0.isReady }) else { return }
        cancelChapterJumpPreparation()
        let signature = chapterPageLayoutSignature
        let contentSignature = chapterPageContentSignature(section)
        let cached = chapterPageCache[index]
        if readerMode != .scroll,
           cached?.layoutSignature != signature || cached?.contentSignature != contentSignature {
            // A TOC selection must not run TextKit in the button/dismiss action.
            // Keep the last rendered surface while one foreground worker cuts
            // the target, then install pages + paragraph mapping atomically.
            cancelPaginationWarmup()
            pageLayoutTask?.cancel()
            pageLayoutTask = nil
            positionPersistScheduler.cancel()
            pendingWindowJump = ReaderPendingChapterJump(chapterIndex: index, paragraphIndex: paragraphIndex, startAtEnd: false)
            let requestID = chapterJumpRequestID
            let generation = windowGeneration
            let (typography, titleTypography) = chapterPaginationTypography()
            let context = chapterPaginationContext(typography: typography, titleTypography: titleTypography)
            chapterJumpTask = Task { @MainActor in
                let pages = await Task.detached(priority: .userInitiated) {
                    ReaderChapterPaginator.paginate(chapterIndex: index, title: section.title,
                                                    paragraphs: section.paragraphs, context: context)
                }.value
                guard !Task.isCancelled, requestID == chapterJumpRequestID,
                      generation == windowGeneration else { return }
                guard chapterPageLayoutSignature == signature, readerMode != .scroll,
                      windowSections.first(where: { $0.chapterIndex == index })?.contentRevision == section.contentRevision else {
                    // Rotation/settings may have changed while measuring.
                    jumpToWindowChapter(index, paragraphIndex: paragraphIndex)
                    return
                }
                chapterPageCache[index] = ReaderChapterPageCacheEntry(
                    layoutSignature: signature, contentSignature: contentSignature, blocks: pages)
                chapterJumpTask = nil
                pendingWindowJump = nil
                commitWindowChapterJump(index, paragraphIndex: paragraphIndex)
            }
            return
        }
        pendingWindowJump = nil
        commitWindowChapterJump(index, paragraphIndex: paragraphIndex)
    }

    private func cancelChapterJumpPreparation() {
        chapterJumpRequestID = UUID()
        chapterJumpTask?.cancel()
        chapterJumpTask = nil
    }

    private func commitWindowChapterJump(_ index: Int, paragraphIndex: Int) {
        guard let section = windowSections.first(where: { $0.chapterIndex == index && $0.isReady }) else { return }
        closeReaderChrome()
        stopAutoScroll()
        stopSpeechPlayback()
        windowCurrentChapterIndex = index
        prefetchWindow(around: index)
        trimWindowIfNeeded()
        let paragraph = min(max(paragraphIndex, 0), max(section.paragraphs.count - 1, 0))
        if readerMode != .scroll {
            // In a distant network/cache jump the old page array still points
            // at the previous chapter. Resolving flat -> page against it made
            // the new chapter stay invisible until an unrelated warmup ended.
            rebuildPagedBlocksCacheAsync(anchorOverride: ReaderChapterPosition(chapterIndex: index, paragraphIndex: paragraph)) {
                if let flat = windowLayout.flatIndex(chapterIndex: index, paragraphIndex: paragraph) {
                    jumpToWindowFlat(flat, paragraphIndex: paragraph)
                }
                warmPaginationCache(around: index)
            }
            return
        }
        guard let flat = windowLayout.flatIndex(chapterIndex: index, paragraphIndex: paragraph) else { return }
        jumpToWindowFlat(flat, paragraphIndex: paragraph)
        warmPaginationCache(around: index)
    }

    /// Chapters already live in the window. TOC / bookmark / slider jumps use
    /// this so a loaded neighbour is activated without touching the network.
    private var readyWindowIndices: Set<Int> {
        Set(windowSections.filter { $0.isReady }.map(\.chapterIndex))
    }

    /// Defers a jump until the target chapter lands in the window. The reader
    /// keeps its web view and page cache; `resumePendingContinuation` performs
    /// the actual jump from `upsertWindowSection`.
    private func beginWindowJump(to index: Int, paragraphIndex: Int, startAtEnd: Bool = false) {
        guard index >= 0, index < windowChapterUpperBound else { return }
        cancelChapterJumpPreparation()
        // Local imports hold every chapter in memory. Re-seed the whole window
        // around the TOC target in one pass instead of loading the target and
        // then prefetching ten neighbours one upsert at a time; each upsert
        // rebuilt the page model, which is what stalled reading after a jump.
        if isLocalChapterBook, seedLocalWindowSynchronously(around: index) {
            cancelPrefetch()
            windowGeneration &+= 1
            cancelPaginationWarmup()
            touchChapterCache(index)
            jumpToWindowChapter(index, paragraphIndex: startAtEnd ? Int.max : paragraphIndex)
            return
        }
        if abs(index - windowCurrentChapterIndex) > 5 {
            windowSections.removeAll { abs($0.chapterIndex - index) > windowRadius }
        }
        pendingWindowJump = ReaderPendingChapterJump(
            chapterIndex: index,
            paragraphIndex: paragraphIndex,
            startAtEnd: startAtEnd
        )
        pageLayoutTask?.cancel()
        pageLayoutTask = nil
        // A deliberate selection outranks speculative work for the old cursor.
        // Do not enqueue another old-window prefetch through requestChapter.
        if windowLoadingIndices.contains(index) {
            // If this exact chapter is already being prefetched, promote its
            // in-flight request instead of cancelling it and waiting for retry.
            prefetchState.queue.removeAll()
        } else {
            cancelPrefetch()
        }
        cancelPaginationWarmup()
        positionPersistScheduler.cancel()
        loadWindowChapter(index)
    }

    private var canJumpToChapter: Bool {
        onSelectChapter != nil || onSelectChapterWithPosition != nil || !windowSections.isEmpty
    }

    /// A TOC row is usable when the chapter is already live or when the owner
    /// can load it. Window-loaded chapters never rebuild the reader.
    private func canJump(to targetIndex: Int) -> Bool {
        if windowSections.contains(where: { $0.chapterIndex == targetIndex && $0.isReady }) {
            return true
        }
        if targetIndex >= 0, targetIndex < windowChapterUpperBound {
            return true
        }
        return onSelectChapter != nil || onSelectChapterWithPosition != nil
    }

    private func canSelectRelativeChapter(offset: Int) -> Bool {
        let target = windowCurrentChapterIndex + offset
        if windowSections.contains(where: { $0.chapterIndex == target && $0.isReady }) {
            return true
        }
        if target >= 0, target < windowChapterUpperBound {
            return true
        }
        guard onSelectChapter != nil || onSelectChapterWithPosition != nil else { return false }
        return chapters.contains { $0.index == target }
    }

    private func selectRelativeChapter(offset: Int, startAtEnd: Bool = false) {
        let targetIndex = windowCurrentChapterIndex + offset
        switch ReaderChapterWindowPolicy.jumpDisposition(
            target: targetIndex,
            loadedIndices: readyWindowIndices,
            upperBound: windowChapterUpperBound
        ) {
        case .activate:
            activateWindowChapter(targetIndex, startAtEnd: startAtEnd)
        case .loadIntoWindow:
            closeReaderChrome()
            stopAutoScroll()
            stopSpeechPlayback()
            beginWindowJump(to: targetIndex, paragraphIndex: 0, startAtEnd: startAtEnd)
        case .outOfRange:
            return
        }
    }

    private func selectChapter(index: Int, keepChrome: Bool = false) {
        switch ReaderChapterWindowPolicy.jumpDisposition(
            target: index,
            loadedIndices: readyWindowIndices,
            upperBound: windowChapterUpperBound
        ) {
        case .activate:
            activateWindowChapter(index)
        case .loadIntoWindow:
            // 拖动进度条时不能顺手把控制面板关掉，否则滑到一半面板就消失了。
            if !keepChrome { closeReaderChrome() }
            stopAutoScroll()
            stopSpeechPlayback()
            beginWindowJump(to: index, paragraphIndex: 0)
        case .outOfRange:
            return
        }
    }

    /// 当前页在本章内的 0-based 序号。
    private var currentChapterPageOrdinal: Int {
        guard pagedBlocks.indices.contains(pagedPageIndex) else { return 0 }
        return pagedBlocks[pagedPageIndex].pageOrdinal
    }

    /// 当前章总页数，用于分页模式滑条上限。
    private var currentChapterPageTotalForSlider: Int {
        guard pagedBlocks.indices.contains(pagedPageIndex) else { return max(pagedBlocks.count, 1) }
        let block = pagedBlocks[pagedPageIndex]
        return max(chapterPageTotal(for: block.chapterIndex, fallback: block.pageOrdinal + 1), 1)
    }

    /// 分页模式底栏文案：本章第几页 / 共几页。
    private var pageSliderLabel: String {
        let total = currentChapterPageTotalForSlider
        return "第 \(min(currentChapterPageOrdinal + 1, total)) / \(total) 页"
    }

    /// 分页模式跳页：只在当前章节内移动，不触发章节重排。
    private func seekPagedPage(ordinal: Int) {
        guard pagedBlocks.indices.contains(pagedPageIndex) else { return }
        let block = pagedBlocks[pagedPageIndex]
        let upper = max(currentChapterPageTotalForSlider - 1, 0)
        let target = min(max(ordinal, 0), upper)
        guard target != block.pageOrdinal else { return }
        guard let index = pagedBlocks.firstIndex(where: {
            $0.chapterIndex == block.chapterIndex
                && $0.pageOrdinal == target
                && !$0.isPlaceholder
        }) else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            pagedPageIndex = index
        }
        reportCoverVisibleIdentity(index)
        updatePagedVisibleParagraph(pageIndex: index)
    }

    /// 拖动进度条时的落点文案；不拖动时返回当前章（配合 opacity 隐藏）。
    private var chapterSliderLabel: String {
        let total = max(displayTotalChapters ?? chapters.count, 1)
        let raw = Int((chapterSliderTarget ?? Double(currentDisplayChapterIndex)).rounded())
        let clamped = min(max(raw, 0), total - 1)
        return "第 \(clamped + 1) / \(total) 章"
    }

    /// 拖动进度条时的「边拖边跳」：停 0.12s 就落一章。
    /// 以前只有手指抬起（onEditingChanged == false）才跳，拖到哪都看不到内容变化。
    private func scheduleLiveChapterSeek(to rawValue: Double) {
        chapterSeekTask?.cancel()
        let index = Int(rawValue.rounded())
        guard index != currentDisplayChapterIndex, (0..<max(displayTotalChapters ?? chapters.count, 1)).contains(index) else { return }
        chapterSeekTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            selectChapter(index: index, keepChrome: true)
        }
    }

    private func handleReaderTap(at location: CGPoint) {
        guard !textSelectionEnabled, !nativeMoreMenuPresentation.isActive else { return }
        // The OS owns the leading edge for interactive pop. A tap or a short
        // drag there must not fall through to the menu/page tap zones.
        guard !ReaderEdgeTapPolicy.isReserved(location) else { return }
        let now = Date()
        guard now >= tapCooldownUntil else { return }
        tapCooldownUntil = now.addingTimeInterval(0.28)
        guard !showSettings else { return }
        if showOverlay {
            let topBarHeight = readerTopSafeInset + 80
            let bottomBarHeight = readerFooterSafeInset + 150
            if location.y <= topBarHeight || location.y >= effectiveViewportSize.height - bottomBarHeight {
                // Inside toolbar bounds - let toolbar controls and Menu receive the tap
                return
            }
            toggleOverlay()
            return
        }
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
            requestAnimatedPageTurn(direction: -1)
        case .nextPage:
            requestAnimatedPageTurn(direction: 1)
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

    private func requestAnimatedPageTurn(direction: Int) {
        guard pendingWindowJump == nil, !interactionGate.isPageInteractionActive,
              pagedBlocks.indices.contains(pagedPageIndex + direction) else { return }
        tapPageTurnRequest = ReaderPageTurnRequest(direction: direction)
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
        scheduleReadingPositionPersistence()
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
        if chromeCoordinator.state.isSettingsVisible {
            chromeCoordinator.state.closeSettings()
        } else {
            chromeCoordinator.state.toggleOverlay()
        }
        nativeSession?.recordMenuState(showOverlay)
    }

    private func presentOverlay() {
        chromeCoordinator.state.setInitialOverlayVisible(true)
    }

    private func toggleSettingsPanel() {
        if chromeCoordinator.state.isSettingsVisible {
            chromeCoordinator.state.closeSettings()
        } else {
            chromeCoordinator.state.openSettings()
        }
    }

    private func closeReaderChrome() {
        chromeCoordinator.state.closeAll()
    }

    /// A delayed dismissal can close a newly reopened menu or settings panel.
    private func closeReaderChromeFromMenu() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { chromeCoordinator.state.closeAll() }
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
        let targetChapter = currentDisplayChapterIndex
        let targetTitle = currentDisplayChapterTitle
        let paragraphIndex = currentBookmarkParagraphIndex
        let paragraphs = windowSections.first(where: { $0.chapterIndex == targetChapter })?.paragraphs
            ?? (targetChapter == chapterIndex ? content.paragraphs : [])
        let snippet = paragraphs.indices.contains(paragraphIndex)
            ? paragraphs[paragraphIndex]
            : targetTitle
        appState.bookshelfStore.toggleBookmark(
            bookID: bookID,
            chapterIndex: targetChapter,
            chapterTitle: targetTitle,
            paragraphIndex: paragraphIndex,
            snippet: snippet
        )
        if openList {
            showBookmarks = true
        }
    }

    private func floatingSpeechCapsule(sleepBadgeText: String?) -> some View {
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
                        .foregroundStyle(readerThemeTextColor)
                }

                if let flat = speechFlatParagraphIndex,
                   scrollModeParagraphs.indices.contains(flat) {
                    Text(scrollModeParagraphs[flat])
                        .font(.system(size: 10))
                        .foregroundStyle(readerThemeTextColor.opacity(0.62))
                        .lineLimit(1)
                        .frame(maxWidth: 160, alignment: .leading)
                }
            }

            HStack(spacing: 8) {
                Menu {
                    Picker("语速", selection: $ttsRate) {
                        Text("0.42x 慢速").tag(0.42)
                        Text("0.48x 舒缓").tag(0.48)
                        Text("0.52x 标准").tag(0.52)
                        Text("0.58x 明快").tag(0.58)
                        Text("0.64x 快速").tag(0.64)
                    }
                } label: {
                    Text(String(format: "%.2fx", ttsRate))
                        .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(AppTheme.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(AppTheme.accent.opacity(0.12), in: Capsule())
                }

                Menu {
                    Picker("睡眠定时", selection: $sleepTimerMinutes) {
                        Text("关闭定时").tag(0)
                        Text("播完本章").tag(-1)
                        Text("15 分钟").tag(15)
                        Text("30 分钟").tag(30)
                        Text("60 分钟").tag(60)
                    }
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "timer")
                            .font(.system(size: 10, weight: .semibold))
                        if let badge = sleepBadgeText {
                            Text(badge)
                                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        }
                    }
                    .foregroundStyle(sleepTimerMinutes != 0 ? AppTheme.accent : readerThemeTextColor.opacity(0.62))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background((sleepTimerMinutes != 0 ? AppTheme.accent.opacity(0.12) : readerThemeTextColor.opacity(0.06)), in: Capsule())
                }

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
                        .foregroundStyle(readerThemeTextColor.opacity(0.62))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .modifier(ReaderChromeSurface(paper: readerThemeBackground, ink: readerThemeTextColor, cornerRadius: 999))
        .shadow(color: .black.opacity(readerIsNight ? 0.35 : 0.12), radius: 10, y: 5)
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
                        .foregroundStyle(readerThemeTextColor)
                }
                Text(String(format: "%.1f 秒/屏", autoScrollDelay))
                    .font(.system(size: 10))
                    .foregroundStyle(readerThemeTextColor.opacity(0.62))
            }

            HStack(spacing: 8) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    autoScrollDelay = min(ReaderAutomationPolicy.maxDelay, autoScrollDelay + 0.5)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 12, weight: .bold))
                        .padding(4)
                        .background(readerThemeTextColor.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    autoScrollDelay = max(ReaderAutomationPolicy.minDelay, autoScrollDelay - 0.5)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .padding(4)
                        .background(readerThemeTextColor.opacity(0.08), in: Circle())
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
                        .foregroundStyle(readerThemeTextColor.opacity(0.62))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .modifier(ReaderChromeSurface(paper: readerThemeBackground, ink: readerThemeTextColor, cornerRadius: 999))
        .shadow(color: .black.opacity(readerIsNight ? 0.35 : 0.12), radius: 10, y: 5)
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
        // Speech follows the chapter currently in the window, not the chapter
        // the owner originally opened. Using `content` here read the wrong
        // paragraph array after a cross-chapter swipe.
        let targetChapterIndex = windowCurrentChapterIndex
        let targetSection = windowSections.first {
            $0.chapterIndex == targetChapterIndex && $0.isReady
        }
        let targetTitle: String
        let targetParagraphs: [String]
        if let targetSection {
            targetTitle = targetSection.title
            targetParagraphs = targetSection.paragraphs
        } else if targetChapterIndex == chapterIndex {
            targetTitle = content.title
            targetParagraphs = content.paragraphs
        } else {
            requestChapter(targetChapterIndex)
            return
        }
        guard !targetParagraphs.isEmpty else { return }

        speechChapterIndex = targetChapterIndex
        let coordinator = playbackCoordinator
        let controller = speechController
        let progressStore = appState.bookshelfStore
        let currentBookID = bookID
        let currentChapterIndex = targetChapterIndex
        let currentChapterTitle = targetTitle
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
                let nextIndex = currentChapterIndex + 1
                guard nextIndex < windowChapterUpperBound else { return }
                let nextIsLive = windowSections.contains {
                    $0.chapterIndex == nextIndex && $0.isReady
                }
                if nextIsLive {
                    activateWindowChapter(nextIndex)
                    DispatchQueue.main.async { beginSpeechPlayback() }
                } else if currentChapterIndex == chapterIndex, let onSpeechFinished {
                    // The owner still points at this reader's opening
                    // chapter, so its handoff target is correct and it can
                    // recreate the reader at the next chapter.
                    onSpeechFinished()
                } else {
                    // The cursor moved inside the window; the owner's
                    // `effectiveChapter` is stale. Download the next chapter
                    // and resume on the same surface.
                    pendingSpeechChapterIndex = nextIndex
                    requestChapter(nextIndex)
                }
            }
        }
        speechPausedForScene = false
        // Scroll-mode visibility is updated by the native TextKit surface and
        // is throttled for performance. This is the latest known visible
        // paragraph (or the first paragraph on the current page), so speech
        // never restarts from chapter zero after a user scrolls.
        let startParagraph = min(
            max(resolvedReadingPosition(forFlatIndex: visibleParagraphIndex).paragraphIndex, 0),
            max(targetParagraphs.count - 1, 0)
        )
        let shelfBook = appState.bookshelfStore.book(id: bookID)
        let bookDisplayTitle = shelfBook?.title ?? content.title
        speechController.speak(
            title: targetTitle,
            bookTitle: bookDisplayTitle,
            paragraphs: targetParagraphs,
            startParagraphIndex: startParagraph,
            includeTitle: false,
            rate: Float(ttsRate),
            engine: TTSEngineKind(rawValue: ttsEngineRawValue) ?? .local,
            httpVoiceID: httpTTSVoiceID
        )
        if let coverStr = shelfBook?.coverURL, let coverURL = URL(string: coverStr) {
            Task { @MainActor in
                if let coverImage = await RemoteImageLoader.shared.image(for: coverURL, maxPixelSize: 512, reuseCoverBytes: true),
                   speechController.isSpeaking {
                    speechController.updateCoverArtwork(coverImage)
                }
            }
        }
    }

    /// One exit path for every manual/navigation/lifecycle stop. Keeping the
    /// AVSpeech controller and the generation coordinator in sync prevents a
    /// late completion callback from reviving a newer reader session.
    private func stopSpeechPlayback() {
        pendingSpeechChapterIndex = nil
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
                        let cursorChapter = windowCurrentChapterIndex
                        let nextIndex = cursorChapter + 1
                        guard nextIndex < windowChapterUpperBound else {
                            stopAutoScroll()
                            return
                        }
                        let nextIsLive = windowSections.contains {
                            $0.chapterIndex == nextIndex && $0.isReady
                        }
                        if nextIsLive {
                            // The window already holds the next chapter: keep
                            // the same reader/native surface alive and resume
                            // the timer at the new chapter head.
                            selectRelativeChapter(offset: 1)
                            DispatchQueue.main.async {
                                startAutoScroll()
                            }
                        } else if cursorChapter == chapterIndex, onAutoScrollFinished != nil {
                            // The owner's handoff target (opening chapter + 1)
                            // is only valid while the cursor still sits on the
                            // opening chapter.
                            stopAutoScroll()
                            onAutoScrollFinished?()
                        } else {
                            // Cursor moved inside the window; download the next
                            // chapter and resume on the same surface.
                            stopAutoScroll()
                            pendingAutoScrollChapterIndex = nextIndex
                            requestChapter(nextIndex)
                        }
                    case .stop:
                        stopAutoScroll()
                    }
                }
            }
        }
    }

    private func stopAutoScroll(clearScenePause: Bool = true) {
        pendingAutoScrollChapterIndex = nil
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
        guard sleepTimerMinutes > 0 else {
            sleepTimerCoordinator.remainingSeconds = nil
            return
        }
        sleepTimerCoordinator.remainingSeconds = sleepTimerMinutes * 60
        sleepTimerTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                if let current = sleepTimerCoordinator.remainingSeconds {
                    if current <= 1 {
                        sleepTimerCoordinator.remainingSeconds = nil
                        stopAutoScroll()
                        stopSpeechPlayback()
                        sleepTimerMinutes = 0
                        appState.record(DiagnosticEvent(level: .info, stage: "reader.sleepTimer", sourceName: content.title, message: "睡眠定时已结束"))
                        sleepTimerTask = nil
                        return
                    }
                    sleepTimerCoordinator.remainingSeconds = current - 1
                } else {
                    return
                }
            }
        }
    }

    private func handleVolumePageTurn(_ direction: Int) {
        guard direction != 0 else { return }
        if readerMode == .scroll {
            runTapAction(direction > 0 ? .nextPage : .previousPage)
            return
        }
        if pagedBlocks.indices.contains(pagedPageIndex + direction) {
            requestAnimatedPageTurn(direction: direction)
        } else if canSelectRelativeChapter(offset: direction) {
            selectRelativeChapter(offset: direction, startAtEnd: direction < 0)
        }
    }

    private func followSpeechRangeInPagedMode(_ range: NSRange?) {
        guard let range,
              range.location != NSNotFound,
              speechController.isSpeaking,
              speechController.currentParagraphIndex >= 0,
              !interactionGate.isPageInteractionActive else { return }
        guard let targetPage = pageIndex(
            containingChapter: speechChapterIndex,
            paragraphIndex: speechController.currentParagraphIndex,
            utf16Offset: range.location
        ),
              targetPage != pagedPageIndex else { return }
        pagedPageIndex = targetPage
    }

    private func pageIndex(containingChapter targetChapter: Int, paragraphIndex: Int, utf16Offset: Int) -> Int? {
        guard !pagedBlocksCache.isEmpty else { return nil }
        for (pageIdx, block) in pagedBlocksCache.enumerated() where block.chapterIndex == targetChapter && !block.isPlaceholder {
            for entry in block.paragraphs where entry.index == paragraphIndex {
                let start = entry.sourceUTF16Offset
                let length = (entry.text as NSString).length
                if utf16Offset >= start && utf16Offset < start + max(length, 1) {
                    return pageIdx
                }
            }
        }
        return nil
    }

    private func exportCurrentBookBookmarks(asMarkdown: Bool) {
        let shelfBook = appState.bookshelfStore.book(id: bookID)
        let title = shelfBook?.title ?? content.title
        let author = shelfBook?.author
        let body = asMarkdown
            ? BookmarkExporter.markdown(bookTitle: title, author: author, bookmarks: bookmarks)
            : BookmarkExporter.plainText(bookTitle: title, author: author, bookmarks: bookmarks)
        let ext = asMarkdown ? "md" : "txt"
        do {
            let url = try BookmarkExporter.writeTemporaryExport(
                content: body,
                filename: "\(title)-书签",
                fileExtension: ext
            )
            bookmarkExportURL = IdentifiableURL(url: url)
        } catch {
            bookmarkExportError = error.localizedDescription
        }
    }

    private func collectReadableChapterSources(upToChapterIndex maxIndex: Int? = nil) -> [ReaderInBookSearchChapterSource] {
        var byIndex: [Int: ReaderInBookSearchChapterSource] = [:]
        for section in windowSections where section.isReady {
            if let maxIndex, section.chapterIndex > maxIndex { continue }
            byIndex[section.chapterIndex] = ReaderInBookSearchChapterSource(
                chapterIndex: section.chapterIndex,
                title: section.title,
                paragraphs: section.paragraphs
            )
        }
        if let shelfBook = appState.bookshelfStore.book(id: bookID),
           let localChapters = shelfBook.localChapters {
            for (idx, item) in localChapters.enumerated() {
                if let maxIndex, idx > maxIndex { continue }
                if byIndex[idx] == nil {
                    byIndex[idx] = ReaderInBookSearchChapterSource(
                        chapterIndex: idx,
                        title: item.title,
                        paragraphs: item.paragraphs
                    )
                }
            }
        }
        if let sourceURL = windowSourceURL, !chapters.isEmpty {
            let purifyRules = appState.purifyRuleStore.enabledPatterns
            for chapter in chapters {
                if let maxIndex, chapter.index > maxIndex { continue }
                if byIndex[chapter.index] != nil { continue }
                if let cached = appState.chapterContentCacheStore.content(
                    sourceURL: sourceURL,
                    chapter: chapter,
                    purifyRules: purifyRules
                ) {
                    byIndex[chapter.index] = ReaderInBookSearchChapterSource(
                        chapterIndex: chapter.index,
                        title: chapter.title,
                        paragraphs: cached.paragraphs
                    )
                }
            }
        }
        return byIndex.values.sorted { $0.chapterIndex < $1.chapterIndex }
    }

    private func runInBookSearch() {
        inBookSearchTask?.cancel()
        let sources = collectReadableChapterSources()
        inBookSearchScannedCount = sources.count
        let needle = inBookSearchQuery
        guard !needle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            inBookSearchHits = []
            return
        }
        inBookSearchTask = Task {
            try? await Task.sleep(nanoseconds: 140_000_000)
            guard !Task.isCancelled else { return }
            let results = await Task.detached(priority: .userInitiated) {
                ReaderInBookSearchEngine.search(query: needle, sources: sources)
            }.value
            guard !Task.isCancelled else { return }
            await MainActor.run {
                inBookSearchHits = results
            }
        }
    }

    private func jumpToInBookSearchHit(_ hit: ReaderInBookSearchHit) {
        showChapterList = false
        closeReaderChrome()
        if windowSections.contains(where: { $0.chapterIndex == hit.chapterIndex && $0.isReady }) {
            jumpToWindowChapter(hit.chapterIndex, paragraphIndex: hit.paragraphIndex)
            return
        }
        guard hit.chapterIndex >= 0, hit.chapterIndex < windowChapterUpperBound else { return }
        beginWindowJump(to: hit.chapterIndex, paragraphIndex: hit.paragraphIndex)
    }

    private func openAISpoilerFreeRecap() {
        let currentIndex = currentDisplayChapterIndex
        let sources = collectReadableChapterSources(upToChapterIndex: currentIndex)
        var selectedSnippets: [String] = []
        var totalChars = 0
        for chapter in sources.reversed() {
            let header = "【第 \(chapter.chapterIndex + 1) 章 \(chapter.title)】"
            let body = chapter.paragraphs.joined(separator: "\n")
            let slice = String(body.prefix(4000))
            let chunk = "\(header)\n\(slice)"
            if totalChars + chunk.count > 12_000 && !selectedSnippets.isEmpty {
                break
            }
            selectedSnippets.append(chunk)
            totalChars += chunk.count
        }
        let summaryText = selectedSnippets.reversed().joined(separator: "\n\n")
        let shelfBook = appState.bookshelfStore.book(id: bookID)
        recapSeedForAI = AIChatRecapSeed(
            bookTitle: shelfBook?.title ?? content.title,
            author: shelfBook?.author ?? "未知作者",
            currentChapterIndex: currentIndex,
            currentChapterTitle: currentDisplayChapterTitle,
            readChaptersSummary: summaryText.isEmpty ? content.paragraphs.joined(separator: "\n") : summaryText
        )
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
              windowLayout.totalCount > 0 else { return }
        let flat = min(max(index, 0), windowLayout.totalCount - 1)
        guard flat != visibleParagraphIndex else { return }
        updateVisibleParagraphInScroll(flat)
    }

    private func initialAutoScrollTarget() -> (paragraph: Int, page: Int) {
        let stored = appState.bookshelfStore.book(id: bookID)
        let paragraphIndex = initialParagraphIndex
            ?? (stored?.currentChapterIndex == chapterIndex ? stored?.currentParagraphIndex : nil)
            ?? 0
        let flat = windowLayout.flatIndex(
            chapterIndex: chapterIndex,
            paragraphIndex: paragraphIndex
        ) ?? windowLayout.flatIndex(chapterIndex: chapterIndex, paragraphIndex: 0)
            ?? positionMapping.clampParagraph(paragraphIndex)
        let safeParagraph = positionMapping.clampParagraph(flat)
        visibleParagraphIndex = safeParagraph
        return (safeParagraph, positionMapping.page(containingParagraph: safeParagraph))
    }

    private func resolveOpeningPreview() {
        // A render acknowledgement may open the native gate before this callback runs.
        // Readiness is a property of the positioned content, independent of whether its cover is still visible.
        guard !hasResolvedOpeningPreview else { return }
        hasResolvedOpeningPreview = true
        nativeSession?.recordReadyReceipt()
        scheduleReadingPositionPersistence()
    }

    /// `commitsExit` marks the write that runs right before the reader is parked
    /// or closed. At that moment the surface is showing a real paragraph even if
    /// the opening wait timed out, so a stale flag must not silently drop the
    /// final position: a fresh reopen would otherwise land on an older chapter.
    private func persistReadingPosition(paragraphIndexOverride: Int? = nil,
                                        commitsExit: Bool = false) {
        guard pendingWindowJump == nil else { return }
        guard commitsExit || isWindowSeeded else { return }
        let resolved: (chapterIndex: Int, chapterTitle: String, paragraphIndex: Int)
        switch readerMode {
        case .scroll:
            resolved = resolvedReadingPosition(forFlatIndex: visibleParagraphIndex)
        case .pageTurn, .cover, .pageCurl:
            resolved = currentPagedReadingPosition()
                ?? resolvedReadingPosition(forFlatIndex: visibleParagraphIndex)
        }
        let paragraphIndex = paragraphIndexOverride ?? resolved.paragraphIndex
        if let onPreviewPosition, appState.bookshelfStore.book(id: bookID) == nil {
            guard readerMode != .scroll || didLandInitialPosition else { return }
            onPreviewPosition(ReaderPreviewPosition(bookID: bookID, chapterIndex: resolved.chapterIndex,
                chapterTitle: resolved.chapterTitle, paragraphIndex: paragraphIndex))
            return
        }
        appState.bookshelfStore.updateReadingProgress(
            bookID: bookID,
            chapterIndex: resolved.chapterIndex,
            chapterTitle: resolved.chapterTitle,
            totalChapters: totalChapters ?? 0,
            paragraphIndex: paragraphIndex
        )
    }

    private func scheduleReadingPositionPersistence() {
        // The scroll callback fires about eight times a second. Cancelling and
        // rebuilding a `@State` Task on every callback invalidated the whole
        // reader body just to schedule the same deferred write. The scheduler
        // extends a single deadline inside a reference box instead.
        positionPersistScheduler.schedule(
            debounceNanoseconds: ReaderPerformancePolicy.positionPersistenceDebounceNanoseconds
        ) {
            // Capture chapter and paragraph together after the debounce.
            // A previously captured local paragraph may belong to another chapter.
            persistReadingPosition()
            checkDailyReadingGoal()
        }
    }

    private func checkDailyReadingGoal() {
        let now = Date()
        let todayKey = now.formatted(date: .numeric, time: .omitted)
        guard dailyGoalMinutes > 0, lastGoalCelebratedDate != todayKey else { return }
        let calendar = ReadingDayActivity.calendar(in: .current)
        let books = appState.bookshelfStore.books
        let storedSeconds = ReadingDayActivity.seconds(on: now, calendar: calendar, books: books)
        let activeSeconds = foregroundReading.todaySeconds(at: now, calendar: calendar)
        guard storedSeconds + activeSeconds >= Double(dailyGoalMinutes) * 60 else { return }

        let summary = ReadingStatsSummary(books: books, referenceDate: now)
        lastGoalCelebratedDate = todayKey
        goalCelebrationCoordinator.streakDays = max(1, summary.streakDays + (storedSeconds == 0 ? 1 : 0))
        goalCelebrationCoordinator.isVisible = true
        HapticFeedback.success()
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            goalCelebrationCoordinator.isVisible = false
        }
    }

    /// Resolves the page cursor to a stable reading position. Placeholder
    /// pages intentionally report the chapter they are loading at paragraph
    /// zero; letting `positionMapping` resolve them would report the next
    /// loaded chapter and corrupt the saved progress.
    private func currentPagedReadingPosition() -> (chapterIndex: Int, chapterTitle: String, paragraphIndex: Int)? {
        guard !pagedBlocks.isEmpty, pagedBlocks.indices.contains(pagedPageIndex) else { return nil }
        let block = pagedBlocks[pagedPageIndex]
        guard block.chapterIndex >= 0 else { return nil }
        if block.isPlaceholder {
            return (block.chapterIndex, block.chapterTitle, 0)
        }
        let flat = positionMapping.paragraph(forPage: pagedPageIndex)
        return resolvedReadingPosition(forFlatIndex: flat)
    }

    private func currentParagraphIndexForPersistence() -> Int {
        guard windowLayout.totalCount > 0 else { return 0 }
        switch readerMode {
        case .scroll:
            return resolvedReadingPosition(forFlatIndex: visibleParagraphIndex).paragraphIndex
        case .pageTurn, .cover, .pageCurl:
            return currentPagedReadingPosition()?.paragraphIndex ?? 0
        }
    }

    private func updatePagedVisibleParagraph(pageIndex: Int) {
        guard pendingWindowJump == nil else { return }
        guard readerMode != .scroll, !pagedBlocks.isEmpty else { return }
        guard pagedBlocks.indices.contains(pageIndex) else { return }
        let block = pagedBlocks[pageIndex]
        if block.isPlaceholder {
            requestChapter(block.chapterIndex)
            return
        }
        guard block.chapterIndex >= 0 else { return }
        let chapterChanged = block.chapterIndex != windowCurrentChapterIndex
        if chapterChanged {
            windowCurrentChapterIndex = block.chapterIndex
            prefetchWindow(around: block.chapterIndex)
            trimWindowIfNeeded()
            touchChapterCache(block.chapterIndex)
        }
        ensurePagedContinuationBuffer(pageIndex: pageIndex)
        let flat = positionMapping.paragraph(forPage: pageIndex)
        guard flat != visibleParagraphIndex || chapterChanged else { return }
        visibleParagraphIndex = flat
        scheduleReadingPositionPersistence()
    }

    /// 读到本章倒数第 3 页时就把下一章拉进来；窗口尾部再向外多预取一章。
    /// 这是「翻页能无感续上下一章」的关键：不能等用户滑到最后一页才发请求。
    private func ensurePagedContinuationBuffer(pageIndex: Int) {
        guard readerMode != .scroll, pagedBlocks.indices.contains(pageIndex) else { return }
        let block = pagedBlocks[pageIndex]
        guard !block.isPlaceholder, block.chapterIndex >= 0 else { return }
        let chapter = block.chapterIndex
        let next = chapter + 1
        let total = chapterPageCounts[chapter] ?? Int.max
        let nearChapterEnd = block.pageOrdinal >= max(total - 3, 0)
            || (total > 0 && total != Int.max
                && Double(block.pageOrdinal) / Double(total) >= 0.7)

        if nearChapterEnd,
           next < windowChapterUpperBound,
           !windowSections.contains(where: { $0.chapterIndex == next && $0.isReady }) {
            loadWindowChapter(next)
        }

        if let maxLoaded = windowSections.map(\.chapterIndex).max(),
           chapter >= maxLoaded - 1 {
            prefetchWindow(around: chapter)
        }
    }

    private func paragraphIndex(forPage pageIndex: Int) -> Int {
        positionMapping.paragraph(forPage: pageIndex)
    }

    private func pageIndex(containingParagraph paragraphIndex: Int) -> Int {
        positionMapping.page(containingParagraph: paragraphIndex)
    }

    private func rebuildPagedBlocksCache(useCachedPageAnchor: Bool = true, anchorOverride: ReaderChapterPosition? = nil) {
        // The foreground jump owns this transaction until its target is ready.
        // Background prefetch must not restore an anchor from the old surface.
        guard pendingWindowJump == nil || anchorOverride != nil else { return }
        let anchor = anchorOverride ?? currentPageAnchor(useCachedPageAnchor: useCachedPageAnchor)
        let cacheKey = readerPageCacheKey
        let blocks = buildReaderPageBlocks()
        pagedBlocksCache = blocks
        pagedBlocksCacheKey = cacheKey
        let layout = windowLayout
        positionMappingCache = ReaderPositionMapping(
            paragraphCount: layout.totalCount,
            pageFirstParagraphs: ReaderPositionMapping.pageStarts(
                from: blocks.map { block in
                    guard !block.isPlaceholder,
                          let start = layout.paragraphStart(chapterIndex: block.chapterIndex) else { return nil }
                    return start + (block.firstParagraphIndex ?? 0)
                }
            )
        )
        pagedPageIndex = restoredPageIndex(anchor, in: blocks)
        scrollParagraphTarget = positionMappingCache.clampParagraph(scrollParagraphTarget)
        visibleParagraphIndex = positionMappingCache.clampParagraph(visibleParagraphIndex)
        syncWindowCursorToVisiblePage()
    }

    /// The page cursor is rebuilt from what the reader can actually see, not
    /// from an array index. `pageIdentityTracker` is fed by
    /// `PageCurlReaderView` on every committed page change, so a chapter that
    /// is prefetched above the reader cannot silently shift the anchor.
    private func currentPageAnchor(useCachedPageAnchor: Bool = true) -> ReaderChapterPosition? {
        if useCachedPageAnchor {
            if let key = pageIdentityTracker.key,
               let index = ReaderPageIdentity.firstIndex(of: key, in: pagedBlocksCache) {
                let block = pagedBlocksCache[index]
                if block.chapterIndex >= 0, blockIsInLiveWindow(block) {
                    return pageAnchor(for: block)
                }
            }
            if pagedBlocksCache.indices.contains(pagedPageIndex) {
                let block = pagedBlocksCache[pagedPageIndex]
                if block.chapterIndex >= 0, blockIsInLiveWindow(block) {
                    return pageAnchor(for: block)
                }
            }
        }
        let fallbackChapter: Int
        if windowSections.contains(where: { $0.chapterIndex == windowCurrentChapterIndex }) {
            fallbackChapter = windowCurrentChapterIndex
        } else {
            fallbackChapter = windowSections.first?.chapterIndex ?? chapterIndex
        }
        return ReaderChapterPosition(chapterIndex: fallbackChapter, paragraphIndex: 0)
    }

    private func pageAnchor(for block: ReaderPageBlock) -> ReaderChapterPosition {
        ReaderChapterPosition(
            chapterIndex: block.chapterIndex,
            paragraphIndex: block.isPlaceholder
                ? ReaderChapterWindowPolicy.restoreParagraphIndex(
                    chapterIndex: block.chapterIndex,
                    currentChapterIndex: windowCurrentChapterIndex,
                    placeholderDirection: block.placeholderDirection
                )
                : (block.firstParagraphIndex ?? 0),
            pageOrdinal: block.isPlaceholder ? nil : block.pageOrdinal,
            paragraphUTF16Offset: block.isPlaceholder ? 0 : block.paragraphs.first?.sourceUTF16Offset
        )
    }

    private func blockIsInLiveWindow(_ block: ReaderPageBlock) -> Bool {
        windowSections.isEmpty
            || windowSections.contains { $0.chapterIndex == block.chapterIndex }
    }

    private func restoredPageIndex(_ anchor: ReaderChapterPosition?, in blocks: [ReaderPageBlock]) -> Int {
        ReaderPageRestoration.index(
            anchor: anchor,
            in: blocks,
            fallbackIndex: pagedPageIndex
        )
    }

    private func schedulePagedBlocksCacheRebuild() {
        guard readerMode != .scroll, pendingWindowJump == nil else { return }
        pageLayoutTask?.cancel()
        // Never rebuild the page model while the finger owns a page turn:
        // swapping the hosting controllers mid-gesture drops a frame and can
        // commit a stale index (the “chapter 5 jumps back to chapter 2”
        // report). The rebuild is re-issued by `handlePageInteraction(false)`.
        if interactionGate.isPageInteractionActive {
            interactionGate.rebuildDeferred = true
            return
        }
        let expectedKey = readerPageCacheKey
        pageLayoutTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: ReaderPerformancePolicy.pageLayoutDebounceNanoseconds)
            guard !Task.isCancelled, readerPageCacheKey == expectedKey else { return }
            if interactionGate.isPageInteractionActive {
                interactionGate.rebuildDeferred = true
                pageLayoutTask = nil
                return
            }
            rebuildPagedBlocksCacheAsync {
                pagedPageIndex = min(max(pagedPageIndex, 0), positionMapping.maximumPageIndex)
                scheduleReadingPositionPersistence()
            }
            pageLayoutTask = nil
        }
    }

    private var activePaginationSections: [ReaderChapterSection] {
        if windowSections.isEmpty {
            return [
                ReaderChapterSection(
                    chapterIndex: chapterIndex,
                    title: content.title,
                    paragraphs: content.paragraphs
                )
            ]
        }
        return windowSections
    }

    private func rebuildPagedBlocksCacheAsync(
        useCachedPageAnchor: Bool = true,
        anchorOverride: ReaderChapterPosition? = nil,
        forceAsync: Bool = false,
        onApplied: (@MainActor () -> Void)? = nil
    ) {
        guard readerMode != .scroll else { return }
        guard pendingWindowJump == nil || anchorOverride != nil else { return }

        let sections = activePaginationSections
        let layoutSignature = chapterPageLayoutSignature
        let activeSection = sections.first(where: { $0.chapterIndex == windowCurrentChapterIndex }) ?? sections.first
        let activeContentSignature = activeSection.map { chapterPageContentSignature($0) }
        let activeCached: Bool = {
            guard let section = activeSection else { return true }
            guard section.isReady,
                  let contentSig = activeContentSignature,
                  let entry = chapterPageCache[section.chapterIndex] else { return false }
            return entry.layoutSignature == layoutSignature && entry.contentSignature == contentSig
        }()

        let activeCharCount = activeSection.map {
            ReaderPaginationSchedulingPolicy.characterCount(of: $0.paragraphs, title: $0.title)
        } ?? 0

        if activeCached || !ReaderPaginationSchedulingPolicy.shouldPaginateOffMainActor(
            hasExistingPages: !pagedBlocksCache.isEmpty,
            activeChapterCharacterCount: activeCharCount,
            forceAsync: forceAsync
        ) {
            asyncPaginationTask?.cancel()
            asyncPaginationTask = nil
            asyncPaginationGeneration &+= 1
            rebuildPagedBlocksCache(useCachedPageAnchor: useCachedPageAnchor, anchorOverride: anchorOverride)
            onApplied?()
            return
        }

        guard let targetSection = activeSection,
              targetSection.isReady,
              let contentSignature = activeContentSignature else {
            rebuildPagedBlocksCache(useCachedPageAnchor: useCachedPageAnchor, anchorOverride: anchorOverride)
            onApplied?()
            return
        }

        asyncPaginationTask?.cancel()
        asyncPaginationGeneration &+= 1
        let generation = asyncPaginationGeneration
        let (typography, titleTypography) = chapterPaginationTypography()
        let context = chapterPaginationContext(typography: typography, titleTypography: titleTypography)
        let capturedAnchor = anchorOverride
            ?? (pagedBlocksCache.isEmpty ? nil : currentPageAnchor(useCachedPageAnchor: useCachedPageAnchor))
        let input = ReaderOffMainActorPaginator.ChapterInput(
            chapterIndex: targetSection.chapterIndex,
            title: targetSection.title,
            paragraphs: targetSection.paragraphs,
            contentSignature: contentSignature
        )

        asyncPaginationTask = Task { @MainActor in
            let outputs = await ReaderOffMainActorPaginator.paginateChapters([input], context: context)
            guard !Task.isCancelled,
                  !readerSessionEnded,
                  asyncPaginationGeneration == generation,
                  chapterPageLayoutSignature == layoutSignature else { return }

            for output in outputs {
                if let currentSection = windowSections.first(where: { $0.chapterIndex == output.chapterIndex && $0.isReady }),
                   chapterPageContentSignature(currentSection) != output.contentSignature {
                    continue
                }
                chapterPageCache[output.chapterIndex] = ReaderChapterPageCacheEntry(
                    layoutSignature: layoutSignature,
                    contentSignature: output.contentSignature,
                    blocks: output.blocks
                )
            }
            asyncPaginationTask = nil

            if interactionGate.isPageInteractionActive {
                paginationRebuildPending = true
                return
            }
            rebuildPagedBlocksCache(
                useCachedPageAnchor: capturedAnchor != nil ? true : useCachedPageAnchor,
                anchorOverride: capturedAnchor
            )
            onApplied?()
        }
    }

    /// Shared typography for the synchronous first-page pass and the warmup
    /// pass. Both must produce identical metrics, otherwise the chapter cache
    /// signatures stop matching and every rebuild re-measures the chapter.
    private func chapterPaginationTypography() -> (
        typography: ReaderPageTypography,
        titleTypography: ReaderPageTypography
    ) {
        let geometry = pagedPageGeometry
        let typography = ReaderPageTypography(
            font: fontFamily.uiFont(ofSize: CGFloat(fontSize), weight: fontWeight.uiWeight, customPostScriptName: customFontPostScriptName),
            titleFont: chapterTitleFamily.uiFont(ofSize: CGFloat(resolvedTitleSize), weight: chapterTitleBold ? .bold : .regular, customPostScriptName: customFontPostScriptName),
            lineSpacing: CGFloat(lineSpacing),
            letterSpacing: CGFloat(letterSpacing),
            paragraphSpacing: CGFloat(paragraphSpacing),
            firstLineIndent: CGFloat(paragraphIndent),
            titleSpacing: CGFloat(titleSpacing),
            contentWidth: geometry.contentWidth,
            // Text pages use final attributed-document TextKit containers.
            // The body rect already excludes header/footer; do not hide layout
            // disagreements behind a fixed subtraction.
            contentHeight: geometry.contentHeight,
            chapterDecoration: chapterDecoration,
            chapterAlignment: chapterAlignment,
            textAlignment: textAlignment
        )
        var titleTypography = typography
        titleTypography.lineSpacing = 0
        titleTypography.letterSpacing = 0
        return (typography, titleTypography)
    }

    /// Immutable snapshot of every setting the paginator reads. Captured on
    /// the main actor so the warmup can cut chapters on the cooperative pool
    /// without touching `@AppStorage` or any other view state.
    private func chapterPaginationContext(
        typography: ReaderPageTypography,
        titleTypography: ReaderPageTypography
    ) -> ReaderChapterPaginationContext {
        ReaderChapterPaginationContext(
            typography: typography,
            titleTypography: titleTypography,
            chromeLayout: chapterHeadingStyle,
            imageStyle: currentImageStyle,
            viewportHeight: pagedLayoutViewportSize.height,
            pagePadding: pagePadding,
            footerHeight: footerHeight,
            traditionalChinese: traditionalChineseEnabled,
            smartLineCleanup: smartLineCleanup
        )
    }

    /// Builds one continuous page model for the whole live window. Every
    /// chapter starts with its own title page and carries its chapter number,
    /// so the page cursor can walk from one chapter into the next without an
    /// index reset. Unloaded neighbours become a real placeholder page, which
    /// is what lets cover/page-curl swipe through the boundary instead of
    /// bouncing at `count - 1`.
    private func buildReaderPageBlocks() -> [ReaderPageBlock] {
        let signpost = PerformanceSignpost.begin("reader.layout")
        defer { PerformanceSignpost.end("reader.layout", id: signpost) }

        let sections: [ReaderChapterSection]
        if windowSections.isEmpty {
            sections = [
                ReaderChapterSection(
                    chapterIndex: chapterIndex,
                    title: content.title,
                    paragraphs: content.paragraphs
                )
            ]
        } else {
            sections = windowSections
        }
        guard !sections.isEmpty else { return [] }

        // Chapter-local pagination cache. Only a typography change invalidates
        // the measured page *content*; a geometry change fails the per-entry
        // signature check by itself, so chapters measured with the previous
        // container are kept until the pruner evicts them.
        let layoutSignature = chapterPageLayoutSignature
        if chapterPageCacheSignature != layoutSignature {
            chapterPageCacheSignature = layoutSignature
        }

        // 分页与页面渲染共用同一份几何：ReaderPageGeometry 已经把安全区、页眉带、
        // 正文带和页脚带算成确定坐标，这里不再重复扣 safeArea / padding。
        let (typography, titleTypography) = chapterPaginationTypography()

        var pages: [ReaderPageBlock] = []

        func placeholder(chapterIndex: Int, title: String, direction: Int) -> ReaderPageBlock {
            ReaderPageBlock(
                id: pages.count,
                includesTitle: true,
                paragraphs: [],
                chapterIndex: chapterIndex,
                chapterTitle: title,
                isPlaceholder: true,
                placeholderDirection: direction
            )
        }

        if let first = sections.first, first.chapterIndex > 0 {
            pages.append(placeholder(
                chapterIndex: first.chapterIndex - 1,
                title: chapterTitle(for: first.chapterIndex - 1),
                direction: -1
            ))
        }

        var expectedChapterIndex = sections.first?.chapterIndex ?? chapterIndex
        for section in sections {
            // A failed/missing chapter in the middle of the window used to
            // become a silent jump in the page stream. Keep every chapter
            // position explicit so the cursor always advances one chapter at
            // a time and the placeholder can be retried.
            while expectedChapterIndex < section.chapterIndex {
                pages.append(placeholder(
                    chapterIndex: expectedChapterIndex,
                    title: chapterTitle(for: expectedChapterIndex),
                    direction: 0
                ))
                expectedChapterIndex += 1
            }
            guard section.isReady else {
                pages.append(placeholder(
                    chapterIndex: section.chapterIndex,
                    title: section.title,
                    direction: 0
                ))
                chapterPageCounts.removeValue(forKey: section.chapterIndex)
                expectedChapterIndex = section.chapterIndex + 1
                continue
            }
            let contentSignature = chapterPageContentSignature(section)
            let cached = chapterPageCache[section.chapterIndex]
            let cacheIsValid = cached.map {
                $0.layoutSignature == layoutSignature && $0.contentSignature == contentSignature
            } ?? false
            // Pagination warmup owns every chapter outside the cursor's
            // immediate neighbours. Measuring them here would block the first
            // frame after a local import opens. Only cache-missing chapters
            // become placeholders: replacing an already cached chapter would
            // blank pages that the warmup then skips as a cache hit.
            // While the container is still settling the synchronous radius is
            // the current chapter plus its two neighbours; anything wider
            // would be measured against a viewport that is about to change.
            let synchronousRadius = 0
            if !cacheIsValid,
               abs(section.chapterIndex - windowCurrentChapterIndex) > synchronousRadius {
                pages.append(placeholder(
                    chapterIndex: section.chapterIndex,
                    title: section.title,
                    direction: 0
                ))
                chapterPageCounts.removeValue(forKey: section.chapterIndex)
                expectedChapterIndex = section.chapterIndex + 1
                continue
            }
            let chapterPages: [ReaderPageBlock]
            if cacheIsValid, let cached {
                chapterPages = cached.blocks
            } else {
                chapterPages = appendPages(
                    for: section,
                    typography: typography,
                    titleTypography: titleTypography
                )
                chapterPageCache[section.chapterIndex] = ReaderChapterPageCacheEntry(
                    layoutSignature: layoutSignature,
                    contentSignature: contentSignature,
                    blocks: chapterPages
                )
            }
            chapterPageCounts[section.chapterIndex] = chapterPages.count
            pages.append(contentsOf: chapterPages)
            expectedChapterIndex = section.chapterIndex + 1
        }

        if let last = sections.last, last.chapterIndex + 1 < windowChapterUpperBound {
            pages.append(placeholder(
                chapterIndex: last.chapterIndex + 1,
                title: chapterTitle(for: last.chapterIndex + 1),
                direction: 1
            ))
        }

        if pages.isEmpty {
            pages.append(ReaderPageBlock(
                id: 0,
                includesTitle: true,
                paragraphs: [],
                chapterIndex: chapterIndex,
                chapterTitle: content.title
            ))
        }
        let windowIndices = Set(sections.map(\.chapterIndex))
        chapterPageCounts = chapterPageCounts.filter { windowIndices.contains($0.key) }
        pruneChapterPageCache(keeping: windowIndices)

        // Every chapter paginates into its own array, so the local ids repeat.
        // Renumber globally: TabView selection and the page-curl controller
        // both rely on `page.id == page index`.
        return pages.enumerated().map { offset, page in
            ReaderPageBlock(
                id: offset,
                includesTitle: page.includesTitle,
                paragraphs: page.paragraphs,
                chapterIndex: page.chapterIndex,
                chapterTitle: page.chapterTitle,
                pageOrdinal: page.pageOrdinal,
                isPlaceholder: page.isPlaceholder,
                placeholderDirection: page.placeholderDirection,
                inlineTitleText: page.inlineTitleText
            )
        }
    }

    private func appendPages(
        for section: ReaderChapterSection,
        typography: ReaderPageTypography,
        titleTypography: ReaderPageTypography
    ) -> [ReaderPageBlock] {
        paginateChapter(
            chapterIndex: section.chapterIndex,
            title: section.title,
            paragraphs: section.paragraphs,
            typography: typography,
            titleTypography: titleTypography
        )
    }

    /// Cuts one chapter into pages from a single geometry snapshot. Shared by
    /// the synchronous first pass and the background warmup so both produce
    /// identical metrics and the cache signatures keep matching.
    private func paginateChapter(
        chapterIndex: Int,
        title: String,
        paragraphs: [String],
        typography: ReaderPageTypography,
        titleTypography: ReaderPageTypography
    ) -> [ReaderPageBlock] {
        ReaderChapterPaginator.paginate(
            chapterIndex: chapterIndex,
            title: title,
            paragraphs: paragraphs,
            context: chapterPaginationContext(
                typography: typography,
                titleTypography: titleTypography
            )
        )
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

/// Result of one window chapter fetch. The message travels to the placeholder
/// and the scroll banner so a source timeout is visible instead of looking
/// like an empty chapter.
private enum ReaderWindowChapterOutcome {
    case success(ReaderChapterSection)
    case failure(String)
}

private struct ScrollChapterStatus: Equatable {
    let chapterIndex: Int
    let message: String
    let isFailure: Bool
}

private struct ParagraphJumpRequest: Equatable {
    let id = UUID()
    let index: Int
    var utf16Offset: Int = 0
}

struct ReaderPreviewPosition: Equatable {
    let bookID: String
    let chapterIndex: Int
    let chapterTitle: String
    let paragraphIndex: Int
    var comicPosition: ComicReadingPosition? = nil
}

private final class ReaderScrollPositionTracker {
    var visibleIndex: Int?
    var flatIndex = -1
    var utf16Offset = 0
}

struct ReaderPageEntry: Equatable, Identifiable, Sendable {
    let index: Int
    let text: String
    /// Non-zero when a long paragraph was split across page boundaries.
    var chunkIndex: Int = 0
    /// Owning chapter. The window merges several chapters into one page model;
    /// paragraph 3 of chapter 8 must not collide with paragraph 3 of chapter 9
    /// in SwiftUI's identity diff.
    var chapterIndex: Int = -1
    var sourceUTF16Offset: Int = 0
    var isContinuation: Bool { chunkIndex > 0 }
    var id: String { "\(chapterIndex)-\(index)-\(chunkIndex)" }
}

struct ReaderPageBlock: Identifiable, Equatable, Sendable {
    let id: Int
    let includesTitle: Bool
    let paragraphs: [ReaderPageEntry]
    /// Chapter that owns the first paragraph on this page. -1 keeps the
    /// legacy single-chapter call sites source compatible.
    var chapterIndex: Int = -1
    var chapterTitle: String = ""
    /// Zero-based page number inside its chapter. Used as a stable anchor
    /// when chapters are inserted above the current page.
    var pageOrdinal: Int = 0
    /// A synthetic page shown while a neighbouring chapter downloads. Its
    /// chapterIndex points at the chapter being loaded so the reader can jump
    /// to that chapter's first real page as soon as it arrives.
    var isPlaceholder: Bool = false
    /// -1 = previous chapter, +1 = next chapter, 0 = current chapter loading.
    var placeholderDirection: Int = 0
    var inlineTitleText: String? = nil

    var firstParagraphIndex: Int? {
        paragraphs.first?.index
    }

    var lastParagraphIndex: Int? {
        paragraphs.last?.index
    }
}

/// The page-curl controller reports the page that is actually on screen. The
/// tracker is a reference box, not `@State`, so updating it from a UIKit
/// callback never invalidates the SwiftUI reader tree mid-gesture.
final class ReaderVisiblePageTracker {
    var key: String?
}

/// Reference-boxed prefetch bookkeeping. These values are never rendered, so
/// putting them in `@State` only made each prefetch pass rebuild the reader.
final class ReaderPrefetchState {
    var queue: [Int] = []
    var task: Task<Void, Never>?
    var generation = 0
}

/// Debounces reading-position writes without touching SwiftUI state on every
/// scroll callback. A single task extends its deadline while the finger is
/// moving, then writes once the reader settles.
final class ReaderPositionPersistScheduler {
    private var task: Task<Void, Never>?
    private var revision = 0

    func schedule(debounceNanoseconds: UInt64, action: @escaping @MainActor () -> Void) {
        revision &+= 1
        guard task == nil else { return }
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let expected = revision
                try? await Task.sleep(nanoseconds: debounceNanoseconds)
                guard !Task.isCancelled else { break }
                if expected != revision { continue }
                action()
                task = nil
                return
            }
            task = nil
        }
    }

    func cancel() {
        revision &+= 1
        task?.cancel()
        task = nil
    }
}

/// Mutable gesture state that must not invalidate the SwiftUI reader tree.
/// `PageCurlReaderView` reports the start and end of a page turn from a UIKit
/// delegate callback; storing that in `@State` re-evaluates the entire reader
/// body on the first frame of every swipe.
final class ReaderInteractionGate {
    var isPageInteractionActive = false
    var rebuildDeferred = false
    var isScrollInteractionActive = false
    var scrollTrimDeferred = false
    /// The chapter under the reading line while a fling is in flight. Holding
    /// it here instead of `@State` keeps the chapter transition from
    /// re-evaluating the whole reader body in the middle of a scroll frame.
    var pendingScrollChapterIndex: Int?
    /// Chapters that finished downloading while a fling was in flight. Applied
    /// in one batch when the interaction ends.
    var deferredWindowSections: [ReaderChapterSection] = []
}

/// Bounded attributed-string cache keyed by stable page identity. Mutated
/// from `body` through a reference type, which keeps SwiftUI from treating a
/// cache fill as a state change.
final class ReaderPageTextCache {
    private var storage: [String: NSAttributedString] = [:]
    private var order: [String] = []
    private var signature = ""
    private var inFlight: Set<String> = []
    /// `text` runs on the main thread, `storeIfAbsent` on a prewarm queue.
    private let lock = NSLock()
    /// A whole-cache flush every 16 pages forced TextKit to rebuild the
    /// attributed strings of pages the reader was about to swipe back to.
    /// Keep a wide window and evict the oldest entry one at a time instead.
    private let capacity = 96

    func contains(key: String, signature: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return signature == self.signature && storage[key] != nil
    }

    func text(key: String, signature: String, build: () -> NSAttributedString) -> NSAttributedString {
        lock.lock()
        if signature != self.signature {
            storage.removeAll(keepingCapacity: true)
            order.removeAll(keepingCapacity: true)
            self.signature = signature
        }
        if let cached = storage[key] {
            touch(key)
            lock.unlock()
            return cached
        }
        lock.unlock()

        // Build outside the lock: one page build is milliseconds long and a
        // prewarm pass must not block the visible page behind it.
        let value = build()

        lock.lock()
        if signature == self.signature {
            insert(key, value)
        }
        lock.unlock()
        return value
    }

    /// Fills one entry from the background prewarm pass. A value built for an
    /// older typography revision is dropped instead of shadowing a live page.
    func storeIfAbsent(key: String, signature: String, build: () -> NSAttributedString) {
        lock.lock()
        if self.signature.isEmpty { self.signature = signature }
        if signature != self.signature || storage[key] != nil || inFlight.contains(key) {
            lock.unlock()
            return
        }
        inFlight.insert(key)
        lock.unlock()

        let value = build()

        lock.lock()
        inFlight.remove(key)
        if signature == self.signature, storage[key] == nil {
            insert(key, value)
        }
        lock.unlock()
    }

    private func touch(_ key: String) {
        if let position = order.firstIndex(of: key) {
            order.remove(at: position)
        }
        order.append(key)
    }

    private func insert(_ key: String, _ value: NSAttributedString) {
        if storage.count >= capacity, let evicted = order.first {
            order.removeFirst()
            storage.removeValue(forKey: evicted)
        }
        storage[key] = value
        order.append(key)
    }
}

/// Memoised TOC filtering. `filteredChapters` and
/// `filteredNavigationEntries` were recomputed from scratch on every body
/// pass (filter + optional reverse over the full chapter array), which showed
/// up as dropped frames while scrolling a long table of contents.
final class ReaderTocFilterCache {
    private var chapterKey = ""
    private var chapterResult: [BookChapter] = []
    private var chapterReversedResult: [BookChapter]?
    private var navigationKey = ""
    private var navigationResult: [LocalTextNavigationEntry] = []
    private var navigationReversedResult: [LocalTextNavigationEntry]?
    // Retain the actual COW buffers, not just first/last/count. A TOC refresh
    // can change a middle chapter while those three values remain identical.
    private var chapterSource: [BookChapter] = []
    private var navigationSource: [LocalTextNavigationEntry] = []
    private(set) var chapterBuildCount = 0

    func chapters(query: String, reversed: Bool, chapters: [BookChapter]) -> [BookChapter] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized != chapterKey || !sharesStorage(chapters, chapterSource) {
            chapterSource = chapters
            chapterBuildCount += 1
            chapterResult = normalized.isEmpty ? chapters : chapters.filter { chapter in
                chapter.title.lowercased().contains(normalized) || "\(chapter.index + 1)".contains(normalized)
            }
            chapterReversedResult = nil
            chapterKey = normalized
        }
        guard reversed else { return chapterResult }
        if chapterReversedResult == nil { chapterReversedResult = Array(chapterResult.reversed()) }
        return chapterReversedResult ?? []
    }

    func navigationEntries(
        query: String,
        reversed: Bool,
        entries: [LocalTextNavigationEntry]
    ) -> [LocalTextNavigationEntry] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized != navigationKey || !sharesStorage(entries, navigationSource) {
            navigationSource = entries
            navigationResult = normalized.isEmpty ? entries : entries.filter { entry in
                entry.title.lowercased().contains(normalized)
                    || entry.chapterIndex.map { String($0 + 1).contains(normalized) } == true
            }
            navigationReversedResult = nil
            navigationKey = normalized
        }
        guard reversed else { return navigationResult }
        if navigationReversedResult == nil { navigationReversedResult = Array(navigationResult.reversed()) }
        return navigationReversedResult ?? []
    }

    private func sharesStorage<Element>(_ lhs: [Element], _ rhs: [Element]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return lhs.withUnsafeBufferPointer { left in
            rhs.withUnsafeBufferPointer { right in left.baseAddress == right.baseAddress }
        }
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

/// 目录行独立成 Equatable 视图：滚动时只有真正变化的行会重新求值，
/// 而不是每个滚动帧重建整排 HStack（章节多时这就是掉帧的来源）。
private struct TocChapterRow: View, Equatable {
    let index: Int
    let title: String
    let isCurrent: Bool
    let textColor: Color

    var body: some View {
        HStack(spacing: 12) {
            Text("\(index + 1)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(isCurrent ? AppTheme.accent : textColor.opacity(0.55))
                .frame(width: 48, alignment: .leading)
            Text(title)
                .foregroundStyle(isCurrent ? AppTheme.accent : textColor)
                .fontWeight(isCurrent ? .semibold : .regular)
                .lineLimit(1)
            Spacer(minLength: 0)
            if isCurrent {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppTheme.accent)
            }
        }
    }
}

private struct ReaderAmbientControlsSection: View {
    @Binding var enabled: Bool
    @Binding var presetRaw: String
    @Binding var volume: Double
    @Binding var timerMinutes: Int
    let textColor: Color

    @AppStorage(AppVisualTheme.selectionKey) private var visualThemeRaw = AppVisualTheme.initialSelection.rawValue
    @ObservedObject private var engine = ReaderAmbientSoundscapeEngine.shared

    private var selectedPreset: ReaderAmbientPreset {
        ReaderAmbientPreset(rawValue: presetRaw) ?? .auto
    }

    private var visualTheme: AppVisualTheme {
        AppVisualTheme(rawValue: visualThemeRaw) ?? .classic
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("沉浸白噪音 / 氛围声场", isOn: Binding(
                get: { enabled && engine.isPlaying },
                set: { next in
                    enabled = next
                    if next {
                        engine.start(
                            preset: selectedPreset,
                            visualTheme: visualTheme,
                            volume: volume,
                            timerMinutes: timerMinutes
                        )
                    } else {
                        engine.stop()
                    }
                }
            ))
            .font(.subheadline.weight(.semibold))

            if enabled || engine.isPlaying {
                BrandSegmentedControl(
                    "声场预设",
                    selection: Binding(
                        get: { selectedPreset.rawValue },
                        set: { nextRaw in
                            presetRaw = nextRaw
                            if engine.isPlaying, let preset = ReaderAmbientPreset(rawValue: nextRaw) {
                                engine.start(
                                    preset: preset,
                                    visualTheme: visualTheme,
                                    volume: volume,
                                    timerMinutes: timerMinutes
                                )
                            }
                        }
                    ),
                    options: ReaderAmbientPreset.allCases.map { ($0.rawValue, $0.title) }
                )

                HStack(spacing: 10) {
                    Image(systemName: "speaker.wave.1")
                        .font(.caption)
                        .foregroundStyle(textColor.opacity(0.62))
                    Slider(value: Binding(
                        get: { volume },
                        set: { nextVolume in
                            volume = nextVolume
                            engine.updateVolume(nextVolume)
                        }
                    ), in: 0.05...0.85, step: 0.05)
                    Text("\(Int((volume * 100).rounded()))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(textColor.opacity(0.62))
                        .frame(width: 36, alignment: .trailing)
                }

                HStack(spacing: 8) {
                    Text("声场定时")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(textColor.opacity(0.62))
                    BrandSegmentedControl(
                        "声场定时",
                        selection: Binding(
                            get: { timerMinutes },
                            set: { nextMinutes in
                                timerMinutes = nextMinutes
                                if engine.isPlaying {
                                    engine.configureTimer(minutes: nextMinutes)
                                }
                            }
                        ),
                        options: [(0, "不限时"), (15, "15分"), (30, "30分"), (60, "60分")]
                    )
                }

                if let rem = engine.timerRemainingSeconds, rem > 0 {
                    let m = rem / 60
                    let s = rem % 60
                    Text("当前正在播放：\(engine.activePreset.title) · 剩余 \(m):\(String(format: "%02d", s))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(AppTheme.accent)
                }
            }
        }
    }
}

final class ReaderSpeechController: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var isSpeaking = false
    @Published var isPaused = false
    @Published var currentParagraphIndex = -1
    @Published var currentSpeechRange: NSRange? = nil
    /// Last non-title paragraph whose utterance completed. The owner uses it
    /// to persist the final reading position before handing off chapters.
    @Published private(set) var lastFinishedParagraphIndex = -1

    private let synthesizer = AVSpeechSynthesizer()
    private var queue = ReaderSpeechQueue()
    private var rate: Float = 0.52
    private var activeUtterance: AVSpeechUtterance?
    private var currentTitle: String = ""
    private var currentBookTitle: String = ""
    private var coverArtwork: MPMediaItemArtwork?
    private var remoteCommandsConfigured = false
    private var remoteCommandTargets: [(MPRemoteCommand, Any)] = []
    private let cloudCredentialsStore = CloudTTSCredentialsStore()
    private let cloudClient = CloudTTSClient()
    private let cloudPlayer = CloudTTSPlayer()
    private let httpClient = HttpTTSClient()
    private var httpVoice: HttpTTSVoice = HttpTTSVoice.defaultVoices.first
        ?? HttpTTSVoice(id: HttpTTSVoice.defaultVoiceID, name: "默认语音", url: "")
    private var cloudTask: Task<Void, Never>?
    private var cloudGeneration = 0
    private var prebufferedAudio: [String: Data] = [:]
    private var prebufferOrder: [String] = []
    private var prebufferTasks: [String: Task<Data, Error>] = [:]
    private var engineKind: TTSEngineKind = .local
    private var activeSegment: (index: Int, text: String)?
    private var usesRemoteAudioPlayback: Bool {
        engineKind == .cloud || engineKind == .http || engineKind == .file
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
        bookTitle: String = "",
        coverImage: UIImage? = nil,
        paragraphs: [String],
        startParagraphIndex: Int = 0,
        includeTitle: Bool = true,
        rate: Float,
        engine: TTSEngineKind = .local,
        httpVoiceID: Int? = nil
    ) {
        stop(clearCompletion: false)
        if let httpVoiceID,
           let selected = HttpTTSVoiceStore.voice(id: httpVoiceID) {
            httpVoice = selected
        } else if let selected = HttpTTSVoiceStore.allVoices().first {
            httpVoice = selected
        }
        var resolvedEngine = engine
        if resolvedEngine == .cloud && !cloudCredentialsStore.isConfigured {
            lastErrorMessage = "未配置讯飞云端语音凭据，已回退系统语音"
            resolvedEngine = .local
        }
        if resolvedEngine == .file && LocalVoiceLibrary.isEmpty {
            lastErrorMessage = "还没导入本地声音，已回退系统语音（设置 → 语音朗读 → 本地声音）"
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
        self.currentBookTitle = bookTitle
        if let coverImage {
            self.coverArtwork = MPMediaItemArtwork(boundsSize: coverImage.size) { _ in coverImage }
        } else {
            self.coverArtwork = nil
        }
        setupRemoteCommands()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true, options: [])
        isSpeaking = true
        isPaused = false
        currentSpeechRange = nil
        lastFinishedParagraphIndex = -1
        speakNext()
    }

    func updateRate(_ newRate: Float) {
        rate = newRate
    }

    func updateCoverArtwork(_ image: UIImage?) {
        guard isSpeaking else { return }
        if let image {
            coverArtwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        } else {
            coverArtwork = nil
        }
        updateNowPlayingInfo()
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
        currentSpeechRange = nil
        lastFinishedParagraphIndex = -1
        queue.clear()
        coverArtwork = nil
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
            currentSpeechRange = nil
            queue.clear()
            coverArtwork = nil
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
        currentSpeechRange = nil
        activeSegment = segment
        if engineKind == .cloud {
            playCloudSegment(segment)
            return
        }
        if engineKind == .http {
            playHTTPVoiceSegment(segment)
            return
        }
        if engineKind == .file {
            playLocalVoiceSegment(segment)
            return
        }
        let utterance = AVSpeechUtterance(string: segment.text)
        let preferredID = UserDefaults.standard.string(forKey: "reader.localVoiceIdentifier") ?? ""
        if !preferredID.isEmpty, let customVoice = AVSpeechSynthesisVoice(identifier: preferredID) {
            utterance.voice = customVoice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        }
        utterance.rate = rate
        activeUtterance = utterance
        synthesizer.speak(utterance)
        updateNowPlayingInfo()
    }

    private func cancelCloudPlayback() {
        cloudGeneration += 1
        cloudTask?.cancel()
        cloudTask = nil
        for (_, task) in prebufferTasks {
            task.cancel()
        }
        prebufferTasks.removeAll()
        prebufferedAudio.removeAll()
        prebufferOrder.removeAll()
        cloudPlayer.stop()
    }

    private func prebufferKey(for segment: (index: Int, text: String)) -> String {
        "\(engineKind.rawValue)|\(segment.index)|\(segment.text.hashValue)"
    }

    private func storePrebufferedAudio(_ data: Data, forKey key: String) {
        prebufferedAudio[key] = data
        prebufferOrder.removeAll { $0 == key }
        prebufferOrder.append(key)
        while prebufferOrder.count > 4 {
            let oldest = prebufferOrder.removeFirst()
            prebufferedAudio.removeValue(forKey: oldest)
        }
    }

    private func schedulePrebuffer(generation: Int) {
        guard isSpeaking, cloudGeneration == generation else { return }
        guard engineKind == .http || engineKind == .cloud else { return }
        let upcoming = queue.lookaheadSegments(count: 2).filter {
            !($0.text.hasPrefix("[img]") && $0.text.hasSuffix("[/img]"))
        }
        for candidate in upcoming {
            let key = prebufferKey(for: candidate)
            if prebufferedAudio[key] != nil || prebufferTasks[key] != nil {
                continue
            }
            if engineKind == .http {
                let voice = httpVoice
                let speed = min(max(Int((rate * 10).rounded()), 0), 10)
                let text = candidate.text
                let task = Task<Data, Error> {
                    let client = HttpTTSClient()
                    return try await client.synthesize(voice: voice, text: text, speed: speed)
                }
                prebufferTasks[key] = task
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let data = try? await task.value,
                       self.cloudGeneration == generation,
                       self.isSpeaking {
                        self.storePrebufferedAudio(data, forKey: key)
                    }
                    self.prebufferTasks.removeValue(forKey: key)
                }
            } else if engineKind == .cloud,
                      let credentials = cloudCredentialsStore.load(),
                      credentials.isConfigured {
                let text = candidate.text
                let task = Task<Data, Error> {
                    let client = CloudTTSClient()
                    return try await client.synthesize(text: text, credentials: credentials)
                }
                prebufferTasks[key] = task
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let data = try? await task.value,
                       self.cloudGeneration == generation,
                       self.isSpeaking {
                        self.storePrebufferedAudio(data, forKey: key)
                    }
                    self.prebufferTasks.removeValue(forKey: key)
                }
            }
        }
    }

    /// 本地音频通道：第 N 段直接播 `N.mp3`（也接受 `pN.mp3` / `N - 标题.mp3`）。
    /// 缺哪个段落就跳过那一段（和图片段落同样处理），不合成、不联网；
    /// 播放失败时把引擎退回系统语音并重念这一段，不让整章哑掉。
    private func playLocalVoiceSegment(_ segment: (index: Int, text: String)) {
        guard let url = LocalVoiceLibrary.fileURL(forParagraph: segment.index) else {
            speakNext()
            return
        }
        cancelCloudPlayback()
        updateNowPlayingInfo()
        do {
            try cloudPlayer.play(fileURL: url)
            if isPaused {
                cloudPlayer.pause()
            }
        } catch {
            lastErrorMessage = "本地音频播放失败：\(error.localizedDescription)，已回退系统语音"
            engineKind = .local
            playSegment(segment)
        }
    }

    private func playCloudSegment(_ segment: (index: Int, text: String)) {
        guard let credentials = cloudCredentialsStore.load(), credentials.isConfigured else {
            lastErrorMessage = "未配置讯飞云端语音凭据，已回退系统语音"
            engineKind = .local
            playSegment(segment)
            return
        }
        let cacheKey = prebufferKey(for: segment)
        let cachedAudio = prebufferedAudio.removeValue(forKey: cacheKey)
        let inflightPrebuffer = prebufferTasks.removeValue(forKey: cacheKey)
        let preservedPrebuffered = prebufferedAudio
        let preservedOrder = prebufferOrder
        let preservedTasks = prebufferTasks

        cloudGeneration += 1
        cloudTask?.cancel()
        cloudTask = nil
        cloudPlayer.stop()
        prebufferedAudio = preservedPrebuffered
        prebufferOrder = preservedOrder
        prebufferTasks = preservedTasks

        let generation = cloudGeneration
        updateNowPlayingInfo()
        if let cachedAudio {
            do {
                try cloudPlayer.play(data: cachedAudio)
                if isPaused { cloudPlayer.pause() }
                schedulePrebuffer(generation: generation)
                return
            } catch {
                // Fall through to fresh synthesis on corrupt cached bytes.
            }
        }
        cloudTask = Task { [weak self] in
            guard let self else { return }
            do {
                let audio: Data
                if let inflightPrebuffer {
                    audio = try await inflightPrebuffer.value
                } else {
                    audio = try await self.cloudClient.synthesize(text: segment.text, credentials: credentials)
                }
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard self.cloudGeneration == generation, self.isSpeaking else { return }
                    do {
                        try self.cloudPlayer.play(data: audio)
                        if self.isPaused {
                            self.cloudPlayer.pause()
                        }
                        self.schedulePrebuffer(generation: generation)
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
        let cacheKey = prebufferKey(for: segment)
        let cachedAudio = prebufferedAudio.removeValue(forKey: cacheKey)
        let inflightPrebuffer = prebufferTasks.removeValue(forKey: cacheKey)
        let preservedPrebuffered = prebufferedAudio
        let preservedOrder = prebufferOrder
        let preservedTasks = prebufferTasks

        cloudGeneration += 1
        cloudTask?.cancel()
        cloudTask = nil
        cloudPlayer.stop()
        prebufferedAudio = preservedPrebuffered
        prebufferOrder = preservedOrder
        prebufferTasks = preservedTasks

        let generation = cloudGeneration
        updateNowPlayingInfo()
        if let cachedAudio {
            do {
                try cloudPlayer.play(data: cachedAudio)
                if isPaused { cloudPlayer.pause() }
                schedulePrebuffer(generation: generation)
                return
            } catch {
                // Fall through to fresh synthesis on corrupt cached bytes.
            }
        }
        let voice = httpVoice
        let speed = min(max(Int((rate * 10).rounded()), 0), 10)
        cloudTask = Task { [weak self] in
            guard let self else { return }
            do {
                let audio: Data
                if let inflightPrebuffer {
                    audio = try await inflightPrebuffer.value
                } else {
                    audio = try await self.httpClient.synthesize(
                        voice: voice,
                        text: segment.text,
                        speed: speed
                    )
                }
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard self.cloudGeneration == generation, self.isSpeaking else { return }
                    do {
                        try self.cloudPlayer.play(data: audio)
                        if self.isPaused {
                            self.cloudPlayer.pause()
                        }
                        self.schedulePrebuffer(generation: generation)
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
        // 同一套回退逻辑也服务 `.file` 通道，文案不能一律写「云端」。
        let label = engineKind == .file ? "本地音频不可用" : "云端语音不可用"
        lastErrorMessage = "\(label)，已回退系统语音：\(message)"
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
        info[MPMediaItemPropertyArtist] = currentBookTitle.isEmpty ? "纸间语音朗读" : currentBookTitle
        info[MPMediaItemPropertyAlbumTitle] = currentBookTitle.isEmpty ? "纸间 (SourceRead)" : "\(currentBookTitle) · 纸间"
        if let coverArtwork {
            info[MPMediaItemPropertyArtwork] = coverArtwork
        }
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
        let playTarget = commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.resume()
            }
            return .success
        }

        commandCenter.pauseCommand.isEnabled = true
        let pauseTarget = commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pause()
            }
            return .success
        }

        commandCenter.togglePlayPauseCommand.isEnabled = true
        let toggleTarget = commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
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
        let nextTarget = commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.skipNext()
            }
            return .success
        }

        commandCenter.previousTrackCommand.isEnabled = true
        let prevTarget = commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.skipPrevious()
            }
            return .success
        }

        remoteCommandTargets = [
            (commandCenter.playCommand, playTarget),
            (commandCenter.pauseCommand, pauseTarget),
            (commandCenter.togglePlayPauseCommand, toggleTarget),
            (commandCenter.nextTrackCommand, nextTarget),
            (commandCenter.previousTrackCommand, prevTarget)
        ]
    }

    private func teardownRemoteCommands() {
        guard remoteCommandsConfigured else { return }
        for (command, target) in remoteCommandTargets {
            command.removeTarget(target)
        }
        remoteCommandTargets.removeAll()
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

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        let text = utterance.speechString
        let resolved = ReaderSpeechSentenceLocator.sentenceRange(in: text, around: characterRange)
            ?? characterRange
        Task { @MainActor [weak self] in
            guard let self, self.isSpeaking, self.activeUtterance === utterance else { return }
            if self.currentSpeechRange != resolved {
                self.currentSpeechRange = resolved
            }
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self, self.isSpeaking, self.activeUtterance === utterance else { return }
            self.lastFinishedParagraphIndex = self.currentParagraphIndex
            self.currentSpeechRange = nil
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
            self.currentSpeechRange = nil
            self.coverArtwork = nil
            self.queue.clear()
            self.onFinished = nil
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        }
    }
}

/// 滚动模式段落数组的指纹缓存。
/// `ReaderView.body` 在滚动期间会被反复求值（可见段落回调、进度落地、页脚刷新），
/// 每次都把窗口内全部段落拼成新数组是稳定的浪费；这里按「书 + 内容指纹」只留一份。
/// 单例只在主线程访问（SwiftUI body 与 Coordinator 回调都在主线程）。
private final class ReaderScrollParagraphCache {
    static let shared = ReaderScrollParagraphCache()
    private var key = ""
    private var value: [String] = []

    func paragraphs(for newKey: String, build: () -> [String]) -> [String] {
        if newKey == key, !value.isEmpty {
            return value
        }
        let built = build()
        key = newKey
        value = built
        return built
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

/// Locks `UINavigationController`'s interactive pop gestures while the reader
/// is on screen so horizontal page swipes in `.pageTurn`, `.cover`, and
/// `.pageCurl` never pop the reader back to the root TabView ("书架/发现/设置").
struct ReaderNavigationPopLock: UIViewControllerRepresentable {
    let allowSystemReturn: Bool

    func makeUIViewController(context: Context) -> LockViewController {
        let controller = LockViewController()
        controller.allowSystemReturn = allowSystemReturn
        return controller
    }

    func updateUIViewController(_ uiViewController: LockViewController, context: Context) {
        uiViewController.allowSystemReturn = allowSystemReturn
        uiViewController.applyPopLock()
    }

    static func dismantleUIViewController(_ uiViewController: LockViewController, coordinator: ()) {
        uiViewController.restorePopLock()
    }

    final class LockViewController: UIViewController {
        var allowSystemReturn = false
        private weak var lockedNavigationController: UINavigationController?
        private var popWasEnabled: Bool?
        private var contentPopWasEnabled: Bool?

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            applyPopLock()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            applyPopLock()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            applyPopLock()
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            if parent != nil {
                applyPopLock()
            } else {
                restorePopLock()
            }
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            // 不在转场开始时恢复：pop 一旦开始，重新打开
            // `interactiveContentPopGestureRecognizer` 会在同一帧里再造出第二个
            // 返回识别器，手指还在屏幕上时就会和正在跑的 pop 抢手势。
            // 等 viewDidDisappear，转场已经结束，再还原本来的状态。
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            restorePopLock()
        }

        func applyPopLock() {
            guard let nav = navigationController else { return }
            // 转场进行中绝不改写识别器状态：写入会打断已经开始的
            // interactive pop，表现出来就是「轻推一下没退出，阅读菜单闪一下」。
            guard transitionCoordinator == nil else { return }
            lockedNavigationController = nav
            popWasEnabled = applied(nav.interactivePopGestureRecognizer, allowSystemReturn, recorded: popWasEnabled)
            #if compiler(>=6.2)
            if #available(iOS 26.0, *) {
                // iOS 26 exposes a full-content pop next to the leading-edge
                // pop. Only the edge belongs to the reader exit: two live
                // recognizers compete with the WebView pan and make a light
                // edge touch flash the reader menu.
                contentPopWasEnabled = applied(nav.interactiveContentPopGestureRecognizer, false,
                                               recorded: contentPopWasEnabled)
            }
            #endif
        }

        /// 只在值真的变化时写 `isEnabled`，并记住改写前的原值。
        private func applied(_ gesture: UIGestureRecognizer?, _ enabled: Bool, recorded: Bool?) -> Bool? {
            guard let gesture else { return recorded }
            let original = recorded ?? gesture.isEnabled
            if gesture.isEnabled != enabled { gesture.isEnabled = enabled }
            return original
        }

        func restorePopLock() {
            guard let nav = lockedNavigationController ?? navigationController else { return }
            // 只在值真的变了才写。pop 收尾那一帧无条件重写 isEnabled，
            // 会让 UIKit 认为手势被外部改动过，从而把正在收尾的转场判为需要
            // 重新协商——这是「滑出去又弹回来」的第三个来源。
            if let wasEnabled = popWasEnabled,
               nav.interactivePopGestureRecognizer?.isEnabled != wasEnabled {
                nav.interactivePopGestureRecognizer?.isEnabled = wasEnabled
            }
            #if compiler(>=6.2)
            if #available(iOS 26.0, *) {
                if let wasEnabled = contentPopWasEnabled,
                   nav.interactiveContentPopGestureRecognizer?.isEnabled != wasEnabled {
                    nav.interactiveContentPopGestureRecognizer?.isEnabled = wasEnabled
                }
            }
            #endif
            popWasEnabled = nil
            contentPopWasEnabled = nil
            lockedNavigationController = nil
        }
    }
}
