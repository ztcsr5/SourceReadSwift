import AVFoundation
import MediaPlayer
import PhotosUI
import SwiftUI
import UIKit

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

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var chromeState = ReaderChromeStateMachine()
    @State private var tabChromeOwner = UUID()
    @State private var showChapterList = false
    @State private var showBookmarks = false
    @State private var showBookDetailSheet = false
    @State private var showChapterWebPage = false
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
    /// Chapters wait in this queue instead of all hitting the source at once.
    /// Nearest-first, one at a time: a distant prefetch can never finish ahead
    /// of the chapter the reader is about to cross into.
    @State private var prefetchQueue: [Int] = []
    @State private var prefetchTask: Task<Void, Never>?
    @State private var prefetchGeneration = 0
    @State private var paragraphJumpRequest: ParagraphJumpRequest?
    @State private var pagedBlocksCache: [ReaderPageBlock] = []
    @State private var pagedBlocksCacheKey = ""
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
    @State private var sessionStartedAt = Date()
    @State private var previousIdleTimerDisabled = false
    @State private var visibleParagraphIndex = 0
    @State private var readerContentFingerprint = ""
    @State private var windowSections: [ReaderChapterSection] = []
    @State private var windowCurrentChapterIndex = 0
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
    @State private var coverDragTranslation: CGFloat = 0
    @State private var coverIsAnimating = false
    @State private var scrollJumpGeneration = 0
    @State private var chapterSliderTarget: Double? = nil
    /// 拖动章节进度条时的实时跳章任务。手指还在滑就不停重排，
    /// 停住 0.12s 才真正跳，避免一次拖动里塞进十几个章节加载。
    @State private var chapterSeekTask: Task<Void, Never>? = nil
    /// 首帧是否已经落到「上次读到的那一段」。为 false 时文字层先透明，
    /// 避免用户先看到第 1 章章首、随后被切成恢复位置的那一下闪跳。
    @State private var didLandInitialPosition = false
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
    @StateObject private var speechController = ReaderSpeechController()
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
    @AppStorage("reader.titleSpacing") private var titleSpacing: Double = ReaderTypographyDefaults.titleSpacing
    /// One-shot migration for the 1.0.64 defaults (`paragraphSpacing = 0`,
    /// `titleSpacing = 8`). A value the reader already customised is kept.
    @AppStorage("reader.typographyMigrated.v65") private var typographyMigratedV65 = false
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
    @AppStorage("reader.background") private var backgroundRawValue: String = ReaderBackground.paper.rawValue
    /// 壁纸填充方式：填充 / 适应 / 拉伸。对齐开元 BoxFit 与栖阅 UIImageView contentMode。
    @AppStorage("reader.customWallpaperFillMode") private var customWallpaperFillModeRaw = ReaderWallpaperFillMode.fill.rawValue
    @State private var isPerBookOverride: Bool = false
    @AppStorage("reader.mode") private var readerModeRawValue: String = ReaderMode.scroll.rawValue
    @AppStorage("reader.tapZones") private var tapZonesRawValue: String = ReaderTapAction.defaultRawValue
    @AppStorage("reader.keepScreenAwake") private var keepScreenAwake = true
    /// -1 follows the system; 0.05...1 overrides while the reader is open.
    @AppStorage("reader.brightness") private var readerBrightness: Double = -1
    @AppStorage("reader.preloadChapterCount") private var preloadChapterCount = ReaderPreloadPolicy.defaultCount
    @AppStorage("reader.textSelectionEnabled") private var textSelectionEnabled = false
    @AppStorage("reader.imageStyle") private var globalImageStyleRaw: String = ReaderImageStyle.default.rawValue
    @AppStorage("reader.traditionalChineseEnabled") private var traditionalChineseEnabled = false
    @AppStorage("reader.bionicReadingEnabled") private var bionicReadingEnabled = false
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
            parts.append("第 \(displayIndex + 1) / \(displayTotal) 章")
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
        let count = max(chapterPageCounts[block.chapterIndex] ?? ordinal, ordinal)
        return "页 \(ordinal)/\(count)"
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
        // 连续阅读要「章尾之前下一章已经在文档里」，但窗口不能无限大：
        // 至少预取 3 章，结合提前 3.5 屏的触发点与纯尾部 DOM 追加，实现无感跨章连读。
        return max(ReaderChapterWindowPolicy.radius(forPreloadCount: preloadChapterCount), 3)
    }

    /// 本地导入的书（localChapters 在书架模型里），章节读取不经过书源。
    private var isLocalChapterBook: Bool {
        appState.bookshelfStore.book(id: bookID)?.localChapters?.isEmpty == false
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
                contentExtendsIntoChrome: contentExtendsIntoChrome
            )
        }
        return ReaderPageGeometry(
            viewportSize: effectiveViewportSize,
            safeTop: readerTopSafeInset,
            safeBottom: readerFooterSafeInset,
            horizontalMargin: margin,
            chromeLayout: chapterHeadingStyle,
            contentExtendsIntoChrome: contentExtendsIntoChrome
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
                "\(section.chapterIndex):\(section.title.hashValue):\(section.paragraphs.count):\(section.paragraphs.first?.hashValue ?? 0):\(section.paragraphs.last?.hashValue ?? 0):\(section.isReady ? 1 : 0)"
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
            colorScheme == .dark ? "dark" : "light"
        ].joined(separator: "|")
    }

    private var readerLayoutKey: String {
        [
            readerModeRawValue,
            fontFamilyRawValue,
            customFontPostScriptName,
            String(format: "%.1f", fontSize),
            String(format: "%.1f", lineSpacing),
            String(format: "%.1f", pagePadding),
            String(format: "%.1f", letterSpacing),
            String(format: "%.1f", paragraphSpacing),
            String(format: "%.1f", paragraphIndent),
            String(format: "%.1f", titleSpacing),
            String(format: "%.1f", footerHeight),
            chapterHeadingStyleRaw,
            contentExtendsIntoChrome ? "extend" : "inset",
            statusPosition,
            showSystemStatusBar ? "sysbar" : "immersive",
            currentImageStyle.rawValue,
            traditionalChineseEnabled ? "tc" : "sc",
            bionicReadingEnabled ? "br" : "plain"
        ].joined(separator: "|")
    }

    /// Signature for chapter-local pagination. Unlike `readerLayoutKey` it
    /// ignores the reading mode: page-turn, cover and page-curl share one page
    /// model, so switching between them must not re-measure every chapter.
    private var chapterPageLayoutSignature: String {
        let viewport = pagedLayoutViewportSize
        let geometry = pagedPageGeometry
        return [
            fontFamilyRawValue,
            customFontPostScriptName,
            String(format: "%.1f", fontSize),
            String(format: "%.1f", lineSpacing),
            String(format: "%.1f", pagePadding),
            String(format: "%.1f", letterSpacing),
            String(format: "%.1f", paragraphSpacing),
            String(format: "%.1f", paragraphIndent),
            String(format: "%.1f", titleSpacing),
            String(format: "%.1f", footerHeight),
            chapterHeadingStyleRaw,
            contentExtendsIntoChrome ? "extend" : "inset",
            statusPosition,
            showSystemStatusBar ? "sysbar" : "immersive",
            currentImageStyle.rawValue,
            traditionalChineseEnabled ? "tc" : "sc",
            bionicReadingEnabled ? "br" : "plain",
            String(format: "%.1fx%.1f", viewport.width, viewport.height),
            String(format: "%.1f", geometry.safeTop),
            String(format: "%.1f", geometry.safeBottom),
            String(format: "%.1f", geometry.bodyTop),
            String(format: "%.1f", geometry.bodyBottom)
        ].joined(separator: "|")
    }

    private func chapterPageContentSignature(_ section: ReaderChapterSection) -> String {
        "\(section.chapterIndex)|\(section.title)|\(section.paragraphs.count)|\(section.paragraphs.first?.hashValue ?? 0)|\(section.paragraphs.last?.hashValue ?? 0)"
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
            .id(readerMode == .scroll ? "web-scroll-reader" : "reader-paged-surface")
            .onPreferenceChange(ReaderPageContainerMetricsKey.self) { metrics in
                if let metrics {
                    adoptPageContainerMetrics(metrics)
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(
                // 仅针对非滚动分页模式使用轻触手势，绝不在距离为0时拦截拖拽，
                // 彻底释放 iOS 16 及全机型在 WKWebView 与 UIPageViewController 的原生滑动与翻页响应。
                SpatialTapGesture()
                    .onEnded { value in
                        guard readerMode != .scroll else { return }
                        handleReaderTap(at: value.location)
                    }
            )

            if showSettings && settingsTab == 2 {
                tapZoneOverlay
                    .allowsHitTesting(false)
                }

            // 分页模式的页眉页脚画在每一页内部（见 pageSurface），
            // 这样 page-curl 的每一张纸都自带页码和章节名，也不会出现
            // 「全局页眉压在页面上、位置又跟安全区打架」的问题。
            if readerMode == .scroll,
               !showOverlay, !speechController.isSpeaking, !autoScrollEnabled {
                if statusPosition == "top" || statusPosition == "both" {
                    readerHeader
                        .transition(.opacity)
                        .zIndex(1)
                }
                if statusPosition == "bottom" || statusPosition == "both" {
                    readerFooter
                        .ignoresSafeArea(.container, edges: .bottom)
                        .transition(.opacity)
                        .zIndex(1)
                }
            }

            if !showOverlay, readerMode == .scroll, let status = scrollChapterStatus {
                scrollChapterStatusBanner(status)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(2)
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
                    .padding(.top, readerTopSafeInset + 12)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .preference(key: ReaderViewportSizePreferenceKey.self, value: proxy.size)
            }
            .ignoresSafeArea()
        }
        .background(ReaderNavigationPopLock())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(!showOverlay && !showSystemStatusBar)
        // 全屏阅读时连 home indicator 一起淡出；打开菜单或强制系统状态栏时恢复。
        .persistentSystemOverlays(showOverlay || showSystemStatusBar ? .automatic : .hidden)
        .preferredColorScheme(background.isDark ? .dark : .light)
        .highRefreshRateSurface()
        .ignoresSafeArea()
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
        .sheet(isPresented: $showFontManagementSheet) {
            NavigationStack {
                CustomFontManagementView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("完成") {
                                showFontManagementSheet = false
                                rebuildPagedBlocksCache()
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
        .sheet(isPresented: $showChapterWebPage) {
            SmartWebReaderView(initialURL: currentChapterWebURL)
        }
        .onAppear {
            migrateTypographyDefaultsIfNeeded()
            if let ov = ReaderOverrideStore.shared.override(for: bookID) {
                isPerBookOverride = true
                if let mode = ov.readerMode { readerModeRawValue = mode.rawValue }
                if let font = ov.fontFamily { fontFamilyRawValue = font.rawValue }
                if let size = ov.fontSize { fontSize = size }
                if let spacing = ov.lineSpacing { lineSpacing = spacing }
                if let bg = ov.background { backgroundRawValue = bg.rawValue }
            }
            if background == .custom {
                customBackgroundIsDark = ReaderCustomWallpaperStore.isWallpaperDark
            }
            appState.acquireTabChromeHidden(owner: tabChromeOwner)
            // 阅读器存活期间采样真实出帧情况，退出时落盘；
            // 用户在设置里能直接读到平均帧率与掉帧率，不必连 Xcode。
            ReaderFrameRateSampler.shared.begin()
            chromeState.setInitialOverlayVisible(initialOverlayVisible)
            sessionStartedAt = Date()
            seedWindow()
            rebuildPagedBlocksCache()
            readerContentFingerprint = makeContentFingerprint(content)
            let initial = initialAutoScrollTarget()
            scrollParagraphTarget = initial.paragraph
            pagedPageIndex = initial.page
            if initial.paragraph > 0 {
                didLandInitialPosition = false
                scrollJumpGeneration &+= 1
                paragraphJumpRequest = ParagraphJumpRequest(index: initial.paragraph)
            } else {
                didLandInitialPosition = true
            }
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
            cancelPrefetch()
            cancelWindowRetries()
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
            ReaderFrameRateSampler.shared.end()
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
            ensurePagedContinuationBuffer(pageIndex: pagedPageIndex)
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
            scrollParagraphTarget = 0
            pagedPageIndex = 0
            visibleParagraphIndex = 0
            paragraphJumpRequest = nil
            closeSettingsPanel()
            showChapterList = false
            showBookmarks = false
            chromeState.setInitialOverlayVisible(initialOverlayVisible)
            // The window owns the chapter list now. Rebuild it from the new
            // content and rebuild pages synchronously so the reader never
            // flashes an empty page surface during an in-place refresh.
            resetWindow()
            // The old page model belongs to the previous chapter. Rebuild it
            // from the freshly reset reading position instead of restoring a
            // stale page ordinal from the replaced content.
            rebuildPagedBlocksCache(useCachedPageAnchor: false)
        }
        .onChange(of: preloadChapterCount) { _ in
            // Apply a preload change to the live window immediately: grow
            // both sides, then evict chapters that fell outside the new
            // radius. Disk-cached chapters remain available for back-reads.
            prefetchWindow(around: windowCurrentChapterIndex)
            trimWindowIfNeeded()
        }
        .onChange(of: readerModeRawValue) { _ in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            // A mode switch changes the page model itself. Rebuild now so the
            // first paged frame has a valid mapping; slider/rotation changes
            // use the debounced path below.
            pageLayoutTask?.cancel()
            pageLayoutTask = nil
            rebuildPagedBlocksCache(useCachedPageAnchor: false)
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
        ZStack {
            if background == .custom, let image = ReaderCustomWallpaperStore.loadWallpaper() {
                ReaderWallpaperView(
                    image: image,
                    fillMode: ReaderWallpaperFillMode(rawValue: customWallpaperFillModeRaw) ?? .fill
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(backgroundWallpaperRevision)
                if customBackgroundIsDark {
                    Color.black.opacity(colorScheme == .dark ? 0.60 : 0.35)
                } else {
                    Color.white.opacity(colorScheme == .dark ? 0.15 : 0.20)
                }
            } else {
                readerThemeBackground
            }
        }
        .ignoresSafeArea()
    }

    private var chromeForeground: Color {
        background.isDark ? .white.opacity(0.94) : .primary
    }

    private var chromeSecondaryForeground: Color {
        background.isDark ? .white.opacity(0.62) : .secondary
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
            "\(section.chapterIndex):\(section.title.hashValue):\(section.paragraphs.count):\(section.isReady ? "r" : "l")"
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
                isReady: section.isReady
            )
        }
    }

    private func resolvedReadingPosition(forFlatIndex index: Int) -> (chapterIndex: Int, chapterTitle: String, paragraphIndex: Int) {
        guard let position = ReaderChapterWindowPolicy.resolvedPosition(
            flatIndex: index,
            layout: windowLayout
        ) else {
            let fallback = max(min(index, max(content.paragraphs.count - 1, 0)), 0)
            return (chapterIndex, content.title, fallback)
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
        if statusPosition == "top" || statusPosition == "both" {
            // 22pt 页眉行 + 6pt 呼吸间距；与 readerHeader 使用同一个常量。
            return Double(
                readerTopSafeInset
                    + ReaderPageChrome.headerTopGap
                    + ReaderPageChrome.scrollHeaderBandHeight
                    + 6
            )
        }
        return Double(
            ReaderPageLayoutEngine.minimumTopInset(
                pagePadding: CGFloat(pagePadding),
                safeTop: readerTopSafeInset
            )
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
            fontSize: fontSize,
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
            textColor: background.uiTextColor(isNight: colorScheme == .dark),
            surfaceColor: background == .custom ? .clear : background.uiColor(isNight: colorScheme == .dark),
            highlightColor: AppTheme.accentUIColor.withAlphaComponent(background.isDark ? 0.22 : 0.12),
            currentParagraphIndex: speechFlatParagraphIndex ?? -1,
            scrollTarget: activeScrollTarget,
            scrollRequestKey: nativeScrollRequestKey,
            animatedScrollDuration: autoScrollEnabled ? max(ReaderAutomationPolicy.clampedDelay(autoScrollDelay) * 0.9, 0.25) : (speechController.isSpeaking ? 0.35 : 0),
            textSelectionEnabled: textSelectionEnabled,
            showChapterEndBadge: false,
            traditionalChineseEnabled: traditionalChineseEnabled,
            bionicReadingEnabled: bionicReadingEnabled,
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
            }
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
        .onAppear {
            if scrollParagraphTarget > 0 {
                didLandInitialPosition = false
                scrollJumpGeneration &+= 1
                DispatchQueue.main.async {
                    paragraphJumpRequest = ParagraphJumpRequest(index: scrollParagraphTarget)
                }
            }
        }
        .onChange(of: chapterIndex) { _ in
            resetWindow()
        }
        .onChange(of: speechController.currentParagraphIndex) { target in
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
        cancelWindowRetries()
        windowFailures.removeAll()
        windowRetryAttempts.removeAll()
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
        rebuildWindowPositionMapping()
        prefetchWindow(around: chapterIndex)
        touchChapterCache(chapterIndex)
    }

    private func resetWindow() {
        windowGeneration &+= 1
        cancelPrefetch()
        cancelWindowRetries()
        windowFailures.removeAll()
        windowRetryAttempts.removeAll()
        layoutAnchorOldParagraph = visibleParagraphIndex
        windowLoadingIndices.removeAll()
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
        rebuildWindowPositionMapping()
        prefetchWindow(around: chapterIndex)
        touchChapterCache(chapterIndex)
    }

    /// Warms both sides of the cursor. Forward chapters are requested first
    /// because reading is overwhelmingly forward, but the previous chapter is
    /// loaded with the same priority as the next one so a backward swipe never
    /// waits for a network round trip.
    private func prefetchWindow(around chapter: Int) {
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
        prefetchQueue = indices.filter { index in
            !windowSections.contains { $0.chapterIndex == index && $0.isReady }
                && !windowLoadingIndices.contains(index)
        }
        guard !prefetchQueue.isEmpty else { return }
        guard prefetchTask == nil else { return }
        let generation = windowGeneration
        prefetchGeneration &+= 1
        let token = prefetchGeneration
        prefetchTask = Task { @MainActor in
            while !prefetchQueue.isEmpty,
                  !Task.isCancelled,
                  prefetchGeneration == token,
                  windowGeneration == generation {
                let index = prefetchQueue.removeFirst()
                if windowSections.contains(where: { $0.chapterIndex == index && $0.isReady }) { continue }
                if windowLoadingIndices.contains(index) { continue }
                await loadWindowChapterNow(index, generation: generation)
            }
            if prefetchGeneration == token {
                prefetchTask = nil
            }
        }
    }

    private func cancelPrefetch() {
        prefetchGeneration &+= 1
        prefetchTask?.cancel()
        prefetchTask = nil
        prefetchQueue.removeAll()
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
                ReaderChapterSection(
                    chapterIndex: index,
                    title: local.title,
                    paragraphs: local.paragraphs
                )
            )
        }

        guard let chapter = chapters.first(where: { $0.index == index }) else {
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
                ReaderChapterSection(
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
                ReaderChapterSection(
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
        let anchor = scrollAnchorPosition()
        let oldMax = windowSections.map(\.chapterIndex).max() ?? windowCurrentChapterIndex
        insertWindowSection(section)
        let appended = section.chapterIndex > oldMax
        applyWindowChange(anchor: anchor, appended: appended)
        rebuildWindowPositionMapping()
        scheduleWindowRebuild()
        trimWindowIfNeeded()
        resumePendingContinuation(for: section.chapterIndex)
    }

    /// Resumes a speech or auto-scroll handoff that was waiting for this
    /// chapter. The reader stays on the same window and native surface.
    private func resumePendingContinuation(for chapter: Int) {
        guard windowSections.contains(where: { $0.chapterIndex == chapter && $0.isReady }) else { return }
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
            paragraphIndex: position.paragraphIndex
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
        visibleParagraphIndex = newFlat
        scrollParagraphTarget = newFlat
        if let jump = paragraphJumpRequest {
            paragraphJumpRequest = ParagraphJumpRequest(index: max(jump.index + delta, 0))
        }
        layoutAnchorRevision &+= 1
    }

    /// Keeps the live window bounded. Chapters dropped from memory are still on
    /// disk: opening one again is a synchronous cache hit, not a new request.
    /// In-flight chapters and the cursor chapter are never evicted.
    private func trimWindowIfNeeded() {
        var keep = ReaderChapterWindowPolicy.retainedIndices(
            around: windowCurrentChapterIndex,
            radius: windowRadius,
            lowerBound: 0,
            upperBound: windowChapterUpperBound,
            loading: windowLoadingIndices
        )
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

    private func scheduleWindowRebuild() {
        guard readerMode != .scroll else { return }
        pageLayoutTask?.cancel()
        pageLayoutTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 30_000_000)
            guard !Task.isCancelled else { return }
            rebuildPagedBlocksCache()
            pageLayoutTask = nil
        }
    }

    private func updateVisibleParagraphInScroll(_ index: Int) {
        let total = windowLayout.totalCount
        guard total > 0 else { return }
        let safeIndex = min(max(index, 0), total - 1)
        guard visibleParagraphIndex != safeIndex else { return }
        visibleParagraphIndex = safeIndex
        let resolved = resolvedReadingPosition(forFlatIndex: safeIndex)
        if resolved.chapterIndex != windowCurrentChapterIndex {
            windowCurrentChapterIndex = resolved.chapterIndex
            prefetchWindow(around: resolved.chapterIndex)
            trimWindowIfNeeded()
            touchChapterCache(resolved.chapterIndex)
        }
        let final = resolvedReadingPosition(forFlatIndex: visibleParagraphIndex)
        scheduleReadingPositionPersistence(paragraphIndex: final.paragraphIndex)
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
            case .cover:
                coverPagedReaderContent
            case .pageCurl:
                pageCurlReaderContent
            default:
                horizontalPagedReaderContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var pageCurlReaderContent: some View {
        PageCurlReaderView(
            pages: pagedBlocks,
            contentRevision: pagedBlocksCacheKey,
            currentPageIndex: $pagedPageIndex,
            onPageChanged: { target in
                updatePagedVisibleParagraph(pageIndex: target)
            },
            onPageContainerLayout: pageContainerLayoutHandler,
            pageBuilder: { page in
                readerPage(for: page)
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .onChange(of: speechController.currentParagraphIndex) { target in
            guard target >= 0, let flat = speechFlatParagraphIndex else { return }
            pagedPageIndex = pageIndex(containingParagraph: flat)
        }
    }

    private var horizontalPagedReaderContent: some View {
        PageCurlReaderView(
            pages: pagedBlocks,
            contentRevision: pagedBlocksCacheKey,
            transitionStyle: .scroll,
            currentPageIndex: $pagedPageIndex,
            onPageChanged: { target in
                updatePagedVisibleParagraph(pageIndex: target)
            },
            onPageContainerLayout: pageContainerLayoutHandler,
            pageBuilder: { page in
                readerPage(for: page)
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .onChange(of: speechController.currentParagraphIndex) { target in
            guard target >= 0, let flat = speechFlatParagraphIndex else { return }
            pagedPageIndex = pageIndex(containingParagraph: flat)
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
                        .frame(width: width, height: proxy.size.height)
                        .clipped()
                        .offset(x: drag * 0.22)
                        .zIndex(1)
                }

                if drag < 0, pagedBlocks.indices.contains(safeIndex + 1) {
                    readerPage(for: pagedBlocks[safeIndex + 1])
                        .id("cover-page-\(pagedBlocks[safeIndex + 1].id)")
                        .frame(width: width, height: proxy.size.height)
                        .clipped()
                        .offset(x: width + drag)
                        .shadow(color: .black.opacity(0.25), radius: 10, x: -6, y: 0)
                        .allowsHitTesting(false)
                        .zIndex(2)
                }

                if drag > 0, safeIndex > 0 {
                    readerPage(for: pagedBlocks[safeIndex - 1])
                        .id("cover-page-\(pagedBlocks[safeIndex - 1].id)")
                        .frame(width: width, height: proxy.size.height)
                        .clipped()
                        .offset(x: -width + drag)
                        .shadow(color: .black.opacity(0.25), radius: 10, x: 6, y: 0)
                        .allowsHitTesting(false)
                        .zIndex(2)
                }
            }
            .frame(width: width, height: proxy.size.height)
            .clipped()
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 8, coordinateSpace: .local)
                    .onChanged { value in
                        if coverIsAnimating {
                            coverIsAnimating = false
                            coverDragTranslation = 0
                        }
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
                guard target >= 0, let flat = speechFlatParagraphIndex,
                      !coverIsAnimating, coverDragTranslation == 0 else { return }
                pagedPageIndex = pageIndex(containingParagraph: flat)
            }
        }
    }

    private func finishCoverGesture(_ decision: ReaderCoverSwipeDecision, width: CGFloat) {
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
                coverIsAnimating = false
            }
            return
        }

        coverIsAnimating = true
        let exitOffset = target > pagedPageIndex ? -width : width
        withAnimation(.interactiveSpring(response: 0.30, dampingFraction: 0.86)) {
            coverDragTranslation = exitOffset
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 320_000_000)
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
                    attributedText: pageAttributedText(for: page),
                    isSelectable: textSelectionEnabled
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private func legacyTextStack(for page: ReaderPageBlock) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if page.includesTitle {
                Text(ReaderTextTransform.displayText(page.chapterTitle.isEmpty ? chapterTitle(for: page.chapterIndex) : page.chapterTitle, traditionalChinese: traditionalChineseEnabled))
                    .font(fontFamily.swiftUIFont(size: CGFloat(ReaderTypographyDefaults.titleFontSize(for: fontSize)), weight: .bold, customPostScriptName: customFontPostScriptName))
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
    }

    private func pageAttributedText(for page: ReaderPageBlock) -> NSAttributedString {
        let bodyFont = fontFamily.uiFont(
            ofSize: CGFloat(fontSize),
            weight: .regular,
            customPostScriptName: customFontPostScriptName
        )
        let titleFont = fontFamily.uiFont(
            ofSize: CGFloat(ReaderTypographyDefaults.titleFontSize(for: fontSize)),
            weight: .bold,
            customPostScriptName: customFontPostScriptName
        )
        let rawTitle = page.chapterTitle.isEmpty ? chapterTitle(for: page.chapterIndex) : page.chapterTitle
        let title = page.includesTitle
            ? ReaderTextTransform.displayText(rawTitle, traditionalChinese: traditionalChineseEnabled)
            : nil
        let paragraphs = page.paragraphs.map { entry -> ReaderPageTextBuilder.Paragraph in
            let ownerChapter = entry.chapterIndex >= 0 ? entry.chapterIndex : windowCurrentChapterIndex
            let highlighted = speechChapterIndex == ownerChapter
                && speechController.currentParagraphIndex == entry.index
            return ReaderPageTextBuilder.Paragraph(
                text: entry.text,
                isContinuation: entry.isContinuation,
                isHighlighted: highlighted
            )
        }
        return ReaderPageTextBuilder.make(
            title: title,
            paragraphs: paragraphs,
            style: ReaderPageTextBuilder.Style(
                bodyFont: bodyFont,
                titleFont: titleFont,
                textColor: background.uiTextColor(isNight: colorScheme == .dark),
                highlightColor: AppTheme.accentUIColor.withAlphaComponent(background.isDark ? 0.22 : 0.12),
                lineSpacing: CGFloat(lineSpacing),
                letterSpacing: CGFloat(letterSpacing),
                paragraphSpacing: CGFloat(paragraphSpacing),
                titleSpacing: CGFloat(titleSpacing)
            )
        )
    }

    /// The page shown while the neighbouring chapter is still downloading, or
    /// after the source rejected it. Without a real failure state a timeout
    /// looked like the end of the book and forced the reader back to the TOC.
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
        GeometryReader { proxy in
            let globalFrame = proxy.frame(in: .global)
            let metrics = ReaderPageContainerMetrics(
                size: proxy.size,
                globalMinY: globalFrame.minY,
                rootViewportHeight: effectiveViewportSize.height,
                rootSafeTop: readerTopSafeInset,
                rootSafeBottom: readerFooterSafeInset
            )
            let geometry = metrics.geometry(
                horizontalMargin: CGFloat(pagePadding),
                chromeLayout: chapterHeadingStyle,
                contentExtendsIntoChrome: contentExtendsIntoChrome
            )

            ZStack(alignment: .topLeading) {
                content()
                    .frame(
                        width: geometry.contentWidth,
                        height: geometry.contentHeight,
                        alignment: .topLeading
                    )
                    .clipped()
                    .offset(x: geometry.horizontalMargin, y: geometry.bodyTop)

                if geometry.showsHeader {
                    pagedPageHeader(page: page, geometry: geometry)
                }
                pagedPageFooter(page: page, geometry: geometry)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .preference(key: ReaderPageContainerMetricsKey.self, value: metrics)
        }
        .background(pageBackground.ignoresSafeArea())
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var pageBackground: some View {
        if background == .custom, let image = ReaderCustomWallpaperStore.loadWallpaper() {
            ZStack {
                ReaderWallpaperView(
                    image: image,
                    fillMode: ReaderWallpaperFillMode(rawValue: customWallpaperFillModeRaw) ?? .fill
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if customBackgroundIsDark {
                    Color.black.opacity(colorScheme == .dark ? 0.60 : 0.35)
                } else {
                    Color.white.opacity(colorScheme == .dark ? 0.15 : 0.20)
                }
            }
            .clipped()
        } else {
            readerThemeBackground
        }
    }

    /// 页眉：12pt 章节名 +（可选）时间 / 电量。位置由 geometry 决定，永远在安全区内。
    private func pagedPageHeader(page: ReaderPageBlock, geometry: ReaderPageGeometry) -> some View {
        TimelineView(.everyMinute) { context in
            HStack(spacing: 10) {
                // In inline mode the first page already carries the large
                // chapter title in the body; repeating it in the 12pt page
                // header is what users reported as a duplicated heading.
                if !(page.includesTitle && chapterHeadingStyle == .inline) {
                    Text(page.chapterTitle.isEmpty ? chapterTitle(for: page.chapterIndex) : page.chapterTitle)
                        .font(.system(size: ReaderPageChrome.headerFontSize, weight: .regular))
                        .foregroundStyle(readerThemeTextColor.opacity(0.55))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                Spacer(minLength: 8)

                if statusPosition == "top" || statusPosition == "both" {
                    if footerShowTime {
                        Text(context.date, format: .dateTime.hour().minute())
                            .font(.system(size: ReaderPageChrome.headerFontSize, weight: .medium).monospacedDigit())
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
                        .font(.system(size: ReaderPageChrome.headerFontSize - 1, weight: .medium).monospacedDigit())
                        .foregroundStyle(readerThemeTextColor.opacity(0.50))
                    }
                }
            }
            .padding(.horizontal, geometry.contentExtendsIntoChrome ? 6 : 0)
            .frame(
                width: geometry.contentExtendsIntoChrome
                    ? geometry.contentWidth + 12
                    : geometry.contentWidth,
                height: ReaderPageChrome.headerHeight,
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
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// 页脚：右下角 `当前页/本章总页`（竞品格式 3/35），时间与电量按开关排列。
    private func pagedPageFooter(page: ReaderPageBlock, geometry: ReaderPageGeometry) -> some View {
        TimelineView(.everyMinute) { context in
            HStack(spacing: 10) {
                if statusPosition == "bottom" || statusPosition == "both" {
                    if footerShowTime {
                        Text(context.date, format: .dateTime.hour().minute())
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
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func pageNumberText(for page: ReaderPageBlock) -> String {
        guard !page.isPlaceholder,
              page.chapterIndex >= 0,
              let total = chapterPageCounts[page.chapterIndex],
              total > 0 else { return "" }
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
        let textView: Text = bionicReadingEnabled
            ? Text(
                ReaderTextTransform.bionicAttributedString(
                    for: paragraph,
                    regularFont: fontFamily.swiftUIFont(size: CGFloat(fontSize), weight: .regular, customPostScriptName: customFontPostScriptName),
                    boldFont: fontFamily.swiftUIFont(size: CGFloat(fontSize), weight: .bold, customPostScriptName: customFontPostScriptName)
                )
            )
            : Text(paragraph)
        return textView
            .font(fontFamily.swiftUIFont(size: CGFloat(fontSize), weight: .regular, customPostScriptName: customFontPostScriptName))
            .foregroundStyle(readerThemeTextColor)
            .kerning(letterSpacing)
            .lineSpacing(lineSpacing)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, highlighted ? 6 : 0)
            .background {
                if highlighted {
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

    /// The reader already reserves `footerHeight` below the last line in every
    /// mode, but the band stayed empty, so a full-screen page showed no clock,
    /// battery or progress once the chrome auto-hid.  This fills that reserved
    /// band and never intercepts taps.
    private var readerHeader: some View {
        TimelineView(.everyMinute) { context in
            VStack {
                HStack(spacing: 12) {
                    Text(currentDisplayChapterTitle)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(readerThemeTextColor.opacity(0.55))

                    Spacer(minLength: 8)

                    if footerShowTime {
                        Text(context.date, format: .dateTime.hour().minute())
                            .font(.system(size: 11, weight: .medium).monospacedDigit())
                            .foregroundStyle(readerThemeTextColor.opacity(0.55))
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
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(readerThemeTextColor.opacity(0.55))
                    }
                }
                .padding(.horizontal, max(CGFloat(pagePadding), 18))
                .frame(height: ReaderPageChrome.scrollHeaderBandHeight)
                // 页眉必须整体落在安全区内：旧版 0.45×safeTop 会把时间/电量
                // 塞进刘海或系统状态栏里，视觉上就是「状态栏位置不对」。
                // 顺序必须是 frame → padding：先固定行高再加安全区偏移，
                // 否则 padding 会先吃掉整个行高，文字被压扁或裁切。
                .padding(.top, readerTopSafeInset + ReaderPageChrome.headerTopGap)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var readerFooter: some View {
        TimelineView(.everyMinute) { context in
            VStack {
                Spacer(minLength: 0)
                HStack(spacing: 12) {
                    if footerShowTime {
                        Text(context.date, format: .dateTime.hour().minute())
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
        }
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
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(readerThemeTextColor.opacity(0.12), lineWidth: 0.5))
            .padding(.horizontal, 24)
            .padding(.bottom, max(CGFloat(footerHeight), 24) + 8)
        }
        .allowsHitTesting(status.isFailure)
        .animation(.easeInOut(duration: 0.2), value: status)
    }

    /// 全屏阅读忽略了安全区，页眉页脚必须自己让开刘海与 home indicator。
    /// 所有窗口取最大安全区：key window 可能是容器窗口（安全区为 0），
    /// 只取 key window 会让页眉直接压到状态栏下面。
    private var readerResolvedSafeInsets: ReaderSafeAreaResolver.Insets {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        var windowTop: CGFloat = 0
        var windowBottom: CGFloat = 0
        var statusBarHeight: CGFloat = 0
        for scene in scenes {
            for window in scene.windows {
                windowTop = max(windowTop, window.safeAreaInsets.top)
                windowBottom = max(windowBottom, window.safeAreaInsets.bottom)
            }
            if let frame = scene.statusBarManager?.statusBarFrame {
                statusBarHeight = max(statusBarHeight, frame.height)
            }
        }
        return ReaderSafeAreaResolver.resolve(
            windowTop: windowTop,
            windowBottom: windowBottom,
            statusBarHeight: statusBarHeight,
            screenSize: UIScreen.main.bounds.size
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

                if background == .custom {
                    chromeIconButton(systemName: customBackgroundIsDark ? "sun.max" : "moon.stars") {
                        customBackgroundIsDark.toggle()
                        UserDefaults.standard.set(true, forKey: "reader.customBackgroundIsDarkManual")
                        UserDefaults.standard.set(customBackgroundIsDark, forKey: "reader.customBackgroundIsDark")
                        backgroundWallpaperRevision = UUID()
                        rebuildPagedBlocksCache()
                        HapticFeedback.light()
                    }
                    .accessibilityLabel("切换壁纸文字黑白色")
                }

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
                            onCacheNextChapters(windowCurrentChapterIndex)
                        } label: {
                            Label("缓存前后章节", systemImage: "square.and.arrow.down")
                        }
                    }

                    if currentChapterWebURL != nil {
                        Button {
                            closeReaderChrome()
                            showChapterWebPage = true
                        } label: {
                            Label("网页打开本章", systemImage: "safari")
                        }
                    }

                    Divider()

                    Button {
                        closeReaderChrome()
                        toggleSpeech()
                    } label: {
                        Label(
                            speechController.isPaused
                                ? "继续朗读"
                                : (speechController.isSpeaking ? "暂停朗读" : "开始朗读"),
                            systemImage: speechController.isSpeaking ? "pause.fill" : "speaker.wave.2"
                        )
                    }

                    if speechController.isSpeaking {
                        Button(role: .destructive) {
                            closeReaderChrome()
                            stopSpeechPlayback()
                        } label: {
                            Label("停止朗读", systemImage: "stop.fill")
                        }
                    }

                    Button {
                        closeReaderChrome()
                        toggleAutoScroll()
                    } label: {
                        Label(
                            autoScrollEnabled ? "暂停自动翻页" : "开始自动翻页",
                            systemImage: autoScrollEnabled ? "pause.fill" : "play.fill"
                        )
                    }

                    Divider()

                    Button {
                        closeReaderChrome()
                        // 二选一，不能两个都做：以前同时置位 sheet 和回调，
                        // 本地书那条回调是 dismiss()，于是「详情」弹在正在销毁的阅读器上，直接崩。
                        if let onRequestBookDetail {
                            onRequestBookDetail()
                        } else {
                            showBookDetailSheet = true
                        }
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
            // A material-only bar let the body text show through the title
            // and progress line (especially on iOS 16). The reader chrome
            // needs an opaque base; the theme colour keeps it consistent.
            .background(readerThemeBackground.opacity(0.97))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.top, readerTopSafeInset + 4)

            Spacer()

            VStack(spacing: 12) {
                // 拖动时实时显示落点章节，松手前就知道要跳到哪一章。
                Text(chapterSliderLabel)
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(readerThemeTextColor.opacity(chapterSliderTarget == nil ? 0 : 0.5))
                    .frame(height: 13)
                    .animation(.easeOut(duration: 0.12), value: chapterSliderTarget == nil)

                HStack(spacing: 10) {
                    navChapterButton(icon: "chevron.left", title: "上一章") {
                        selectRelativeChapter(offset: -1)
                    }
                    .disabled(!canSelectRelativeChapter(offset: -1))

                    Slider(
                        value: Binding(
                            get: { chapterSliderTarget ?? Double(currentDisplayChapterIndex) },
                            set: { newValue in
                                chapterSliderTarget = newValue
                            }
                        ),
                        in: 0...Double(max((displayTotalChapters ?? chapters.count) - 1, 0)),
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
                        .tint(AppTheme.accent)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(.thinMaterial, in: Capsule())
                        .clipShape(Capsule())
                        .accessibilityLabel("章节进度")

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
                        showChapterList = true
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
            // Same reason as the top bar: five buttons over a translucent
            // panel made the text underneath legible through the controls.
            .background(
                readerThemeBackground.opacity(0.96),
                in: RoundedRectangle(cornerRadius: 26, style: .continuous)
            )
            .glassPanel(cornerRadius: 26, material: .ultraThinMaterial, strokeOpacity: background.isDark ? 0.09 : 0.12, shadowOpacity: background.isDark ? 0.42 : 0.14)
            .padding(.horizontal, 14)
            .padding(.bottom, max(readerFooterSafeInset, 10) + 10)
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
            let bottomPadding = max(readerFooterSafeInset, 14)
            let maxHeight = ReaderSettingsLayoutPolicy.maxPanelHeight(
                viewportHeight: proxy.size.height,
                bottomInset: readerFooterSafeInset
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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                }
                .frame(maxWidth: .infinity)
                .frame(height: maxHeight)
                // 先铺一层不透明主题底色，再叠玻璃：只靠 ultraThinMaterial 会透出下面正文，
                // 视觉上就是「东西穿过这个框」。底色跟着阅读主题走，不破坏整体风格。
                .background(
                    readerThemeBackground.opacity(0.97),
                    in: RoundedRectangle(cornerRadius: 28, style: .continuous)
                )
                .glassPanel(cornerRadius: 28, material: .ultraThinMaterial, strokeOpacity: colorScheme == .dark ? 0.08 : 0.12, shadowOpacity: colorScheme == .dark ? 0.35 : 0.18)
                .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
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
            readerModeSection
            perBookOverrideToggle
            backgroundPickerSection
            if background == .custom {
                customWallpaperSection
            }
            readerBrightnessSection
        }
    }

    private var readerModeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("翻页模式")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(readerModeHint)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Picker("翻页模式", selection: $readerModeRawValue) {
                ForEach(ReaderMode.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
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
            Text("背景颜色")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
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
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await MainActor.run {
                            ReaderCustomWallpaperStore.saveWallpaper(image)
                            customBackgroundIsDark = ReaderCustomWallpaperStore.isWallpaperDark
                            backgroundRawValue = ReaderBackground.custom.rawValue
                            backgroundWallpaperRevision = UUID()
                            rebuildPagedBlocksCache()
                            syncPerBookOverrideIfNeeded()
                            HapticFeedback.success()
                        }
                    }
                }
            }

            Picker("壁纸基底与文字风格", selection: $customBackgroundIsDark) {
                Text("浅色壁纸 (深色字)").tag(false)
                Text("深色壁纸 (浅色字)").tag(true)
            }
            .pickerStyle(.segmented)
            .padding(.top, 2)
            .onChange(of: customBackgroundIsDark) { newValue in
                UserDefaults.standard.set(true, forKey: "reader.customBackgroundIsDarkManual")
                UserDefaults.standard.set(newValue, forKey: "reader.customBackgroundIsDark")
                backgroundWallpaperRevision = UUID()
                rebuildPagedBlocksCache()
            }

            Picker("壁纸填充方式", selection: $customWallpaperFillModeRaw) {
                ForEach(ReaderWallpaperFillMode.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .padding(.top, 2)

            if ReaderCustomWallpaperStore.hasCustomWallpaper {
                Button(role: .destructive) {
                    ReaderCustomWallpaperStore.clearWallpaper()
                    backgroundRawValue = ReaderBackground.paper.rawValue
                    backgroundWallpaperRevision = UUID()
                    rebuildPagedBlocksCache()
                    HapticFeedback.light()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text("清除自定义壁纸，恢复预设羊皮纸主题")
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                }
                .padding(.top, 2)
            }

            Text(ReaderCustomWallpaperStore.hasCustomWallpaper
                 ? "壁纸已生效，支持自主切换浅色/深色文字样式以保证最佳对比度。"
                 : "可从相册选择壁纸，支持自由搭配浅色或深色文字。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var readerBrightnessSection: some View {
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
                .stroke(Color.primary.opacity(background.isDark ? 0.12 : 0.06), lineWidth: 0.8)
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
            .padding(.top, readerTopSafeInset + (statusMessage == nil ? 12 : 58))

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
            readerValueSlider("段落差（段间距）", value: $paragraphSpacing, range: 0...28, step: 1, unit: "pt", help: "调整上下两段文字之间的垂直留白。段间距应大于行距，正文才不会糊成一片（推荐 10~14pt）")

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

            // 7. 章节标题
            VStack(alignment: .leading, spacing: 8) {
                Text("章节标题位置")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("章节标题位置", selection: $chapterHeadingStyleRaw) {
                    ForEach(ReaderPageChromeLayout.allCases) { layout in
                        Text(layout.title).tag(layout.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                Text(chapterHeadingStyle.help)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            readerValueSlider("章节标题间距", value: $titleSpacing, range: 0...36, step: 2, unit: "pt", help: "仅「正文大标题」模式生效：大章节标题与正文第一行之间的垂直留白（推荐 8~16pt）。页眉模式不占用正文高度。")

            Toggle("内容延伸至页眉页脚区域", isOn: $contentExtendsIntoChrome)
                .font(.subheadline.weight(.semibold))

            Button {
                applyCompetitiveReaderPreset()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "wand.and.stars")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("一键对齐成熟阅读器排版").font(.subheadline.weight(.semibold))
                        Text("字号 20 / 行距 12 / 段距 10 / 边距 21 / 首行缩进 2 字 / 页眉小标题 / 页码右下角")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(12)
                .background(AppTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)

            // 8. 底部安全留白
            readerValueSlider("底部安全留白", value: $footerHeight, range: 40...180, step: 8, unit: "pt", help: "屏幕最底部向上预留的安全空隙，防止手势遮挡最后一行正文（推荐 80~100pt）")

            // 9. 页脚内容开关。对照同类阅读器（香色闺阁的 tr_showTime / tr_showBatView /
            // tr_showBatLabel 就是三个独立开关），把「时间 / 电量图标 / 电量百分比」拆开，
            // 全屏时不想看就不显示，也就不存在「位置奇怪」这件事。
            VStack(alignment: .leading, spacing: 10) {
                Text("页眉与页脚状态栏")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                HStack {
                    Text("状态栏位置")
                    Spacer()
                    Picker("位置", selection: $statusPosition) {
                        Text("仅页脚").tag("bottom")
                        Text("仅页眉").tag("top")
                        Text("页眉+页脚").tag("both")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }

                Toggle("始终保留系统原生状态栏", isOn: $showSystemStatusBar)
                Toggle("显示时间", isOn: $footerShowTime)
                Toggle("显示电量图标", isOn: $footerShowBatteryIcon)
                Toggle("显示电量百分比", isOn: $footerShowBatteryPercent)
            }
            .font(.subheadline)
        }
    }

    /// 1.0.64 shipped `paragraphSpacing = 0`, which made every paragraph touch
    /// the previous one. Raise only the untouched legacy defaults so a reader
    /// who deliberately picked a tighter value keeps it.
    private func migrateTypographyDefaultsIfNeeded() {
        guard !typographyMigratedV65 else { return }
        if paragraphSpacing == 0 {
            paragraphSpacing = ReaderTypographyDefaults.paragraphSpacing
        }
        if titleSpacing == 8 {
            titleSpacing = ReaderTypographyDefaults.titleSpacing
        }
        typographyMigratedV65 = true
    }

    /// 一档对标栖阅 / 开元阅读截图的排版参数。用户随时可以再微调。
    private func applyCompetitiveReaderPreset() {
        fontSize = 20
        lineSpacing = 12
        pagePadding = 21
        paragraphIndent = 40
        paragraphSpacing = ReaderTypographyDefaults.paragraphSpacing
        titleSpacing = ReaderTypographyDefaults.titleSpacing
        chapterHeadingStyleRaw = ReaderPageChromeLayout.header.rawValue
        contentExtendsIntoChrome = false
        statusPosition = "bottom"
        footerShowTime = true
        footerShowBatteryIcon = true
        footerShowBatteryPercent = true
        HapticFeedback.medium()
        schedulePagedBlocksCacheRebuild()
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

            Toggle("繁体中文显示（简转繁）", isOn: $traditionalChineseEnabled)
                .font(.subheadline.weight(.semibold))

            Toggle("仿生阅读（Bionic Reading 词首加粗）", isOn: $bionicReadingEnabled)
                .font(.subheadline.weight(.semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text("插图排版样式")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("插图排版样式", selection: $globalImageStyleRaw) {
                    ForEach(ReaderImageStyle.allCases) { style in
                        Text(style.title).tag(style.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }

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
            // List 自带 systemBackground，叠在主题背景上就是「章节 (N)」下面那条白带。
            // 把滚动内容背景设为透明，让 readerBackdrop 透上来；行背景已经是 clear。
            .scrollContentBackground(.hidden)
            .background(readerThemeBackground.ignoresSafeArea())
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
            .toolbarColorScheme(background.isDark ? .dark : .light, for: .navigationBar)
        }
        .readerSheetPresentation(color: readerThemeBackground)
        .presentationDetents([.medium, .large])
        .tint(AppTheme.accent)
        .preferredColorScheme(background.isDark ? .dark : .light)
    }

    private var customTocSegmentedPicker: some View {
        HStack(spacing: 0) {
            tocTabButton(title: "目录", tag: 0)
            tocTabButton(title: "书签", tag: 1)
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
                                    selectChapter(index: chapter.index)
                                } label: {
                                    chapterRow(chapter)
                                }
                                .disabled(chapter.index == currentDisplayChapterIndex || !canJump(to: chapter.index))
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
            .toolbarColorScheme(background.isDark ? .dark : .light, for: .navigationBar)
        }
        .readerSheetPresentation(color: readerThemeBackground)
        .presentationDetents([.medium, .large])
        .tint(AppTheme.accent)
        .preferredColorScheme(background.isDark ? .dark : .light)
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

    private func activateWindowChapter(_ index: Int, startAtEnd: Bool = false) {
        guard let section = windowSections.first(where: { $0.chapterIndex == index && $0.isReady }) else { return }
        let paragraph = startAtEnd ? max(section.paragraphs.count - 1, 0) : 0
        jumpToWindowChapter(index, paragraphIndex: paragraph)
    }

    /// Jumps inside the already-loaded window without asking the owner to
    /// rebuild the reader. This is what makes TOC and bookmark navigation
    /// instant while the user has prefetched neighbours in memory.
    private func jumpToWindowChapter(_ index: Int, paragraphIndex: Int) {
        guard let section = windowSections.first(where: { $0.chapterIndex == index && $0.isReady }) else { return }
        closeReaderChrome()
        stopAutoScroll()
        stopSpeechPlayback()
        windowCurrentChapterIndex = index
        prefetchWindow(around: index)
        trimWindowIfNeeded()
        let paragraph = min(max(paragraphIndex, 0), max(section.paragraphs.count - 1, 0))
        guard let flat = windowLayout.flatIndex(chapterIndex: index, paragraphIndex: paragraph) else { return }
        jumpToWindowFlat(flat, paragraphIndex: paragraph)
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
        return onSelectChapter != nil || onSelectChapterWithPosition != nil
    }

    private func canSelectRelativeChapter(offset: Int) -> Bool {
        let target = windowCurrentChapterIndex + offset
        if windowSections.contains(where: { $0.chapterIndex == target && $0.isReady }) {
            return true
        }
        guard onSelectChapter != nil || onSelectChapterWithPosition != nil else { return false }
        return chapters.contains { $0.index == target }
    }

    private func selectRelativeChapter(offset: Int, startAtEnd: Bool = false) {
        let targetIndex = windowCurrentChapterIndex + offset
        if windowSections.contains(where: { $0.chapterIndex == targetIndex && $0.isReady }) {
            activateWindowChapter(targetIndex, startAtEnd: startAtEnd)
            return
        }
        guard let target = chapters.first(where: { $0.index == targetIndex }) else { return }
        closeReaderChrome()
        stopAutoScroll()
        stopSpeechPlayback()
        if let onSelectChapterWithPosition {
            onSelectChapterWithPosition(target, startAtEnd ? Int.max : 0)
        } else {
            onSelectChapter?(target)
        }
    }

    private func selectChapter(index: Int, keepChrome: Bool = false) {
        if windowSections.contains(where: { $0.chapterIndex == index && $0.isReady }) {
            activateWindowChapter(index)
            return
        }
        guard let target = chapters.first(where: { $0.index == index }) ?? (chapters.indices.contains(index) ? chapters[index] : nil) else { return }
        // 拖动进度条时不能顺手把控制面板关掉，否则滑到一半面板就消失了。
        if !keepChrome { closeReaderChrome() }
        stopAutoScroll()
        stopSpeechPlayback()
        if let onSelectChapterWithPosition {
            onSelectChapterWithPosition(target, 0)
        } else {
            onSelectChapter?(target)
        }
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
        let now = Date()
        guard now >= tapCooldownUntil else { return }
        tapCooldownUntil = now.addingTimeInterval(0.28)
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

                if let flat = speechFlatParagraphIndex,
                   scrollModeParagraphs.indices.contains(flat) {
                    Text(scrollModeParagraphs[flat])
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
        speechController.speak(
            title: targetTitle,
            paragraphs: targetParagraphs,
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
              windowLayout.totalCount > 0 else { return }
        let flat = min(max(index, 0), windowLayout.totalCount - 1)
        guard flat != visibleParagraphIndex else { return }
        updateVisibleParagraphInScroll(flat)
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
        let flat = windowLayout.flatIndex(
            chapterIndex: chapterIndex,
            paragraphIndex: paragraphIndex
        ) ?? positionMapping.clampParagraph(paragraphIndex)
        let safeParagraph = positionMapping.clampParagraph(flat)
        visibleParagraphIndex = safeParagraph
        return (safeParagraph, positionMapping.page(containingParagraph: safeParagraph))
    }

    private func persistReadingPosition(paragraphIndexOverride: Int? = nil) {
        let resolved: (chapterIndex: Int, chapterTitle: String, paragraphIndex: Int)
        switch readerMode {
        case .scroll:
            resolved = resolvedReadingPosition(forFlatIndex: visibleParagraphIndex)
        case .pageTurn, .cover, .pageCurl:
            resolved = currentPagedReadingPosition()
                ?? resolvedReadingPosition(forFlatIndex: visibleParagraphIndex)
        }
        let paragraphIndex = paragraphIndexOverride ?? resolved.paragraphIndex
        appState.bookshelfStore.updateReadingProgress(
            bookID: bookID,
            chapterIndex: resolved.chapterIndex,
            chapterTitle: resolved.chapterTitle,
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
        let resolved = resolvedReadingPosition(forFlatIndex: flat)
        scheduleReadingPositionPersistence(paragraphIndex: resolved.paragraphIndex)
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

    private func rebuildPagedBlocksCache(useCachedPageAnchor: Bool = true) {
        let anchor = currentPageAnchor(useCachedPageAnchor: useCachedPageAnchor)
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

    private func currentPageAnchor(useCachedPageAnchor: Bool = true) -> ReaderChapterPosition? {
        if useCachedPageAnchor, pagedBlocksCache.indices.contains(pagedPageIndex) {
            let block = pagedBlocksCache[pagedPageIndex]
            if block.chapterIndex >= 0 {
                return ReaderChapterPosition(
                    chapterIndex: block.chapterIndex,
                    paragraphIndex: block.isPlaceholder
                        ? ReaderChapterWindowPolicy.restoreParagraphIndex(
                            chapterIndex: block.chapterIndex,
                            currentChapterIndex: windowCurrentChapterIndex,
                            placeholderDirection: block.placeholderDirection
                        )
                        : (block.firstParagraphIndex ?? 0),
                    pageOrdinal: block.isPlaceholder ? nil : block.pageOrdinal
                )
            }
        }
        let fallback = resolvedReadingPosition(forFlatIndex: visibleParagraphIndex)
        return ReaderChapterPosition(
            chapterIndex: fallback.chapterIndex,
            paragraphIndex: fallback.paragraphIndex
        )
    }

    private func restoredPageIndex(_ anchor: ReaderChapterPosition?, in blocks: [ReaderPageBlock]) -> Int {
        guard let anchor else {
            return min(max(pagedPageIndex, 0), max(blocks.count - 1, 0))
        }
        // A long paragraph can span several pages. Preserve the exact
        // continuation page while the chapter itself is unchanged; the
        // paragraph check also rejects a stale ordinal after a typography
        // change has repaginated the chapter.
        if let ordinal = anchor.pageOrdinal,
           let exact = blocks.firstIndex(where: {
               !$0.isPlaceholder
                   && $0.chapterIndex == anchor.chapterIndex
                   && $0.pageOrdinal == ordinal
                   && $0.firstParagraphIndex == anchor.paragraphIndex
           }) {
            return exact
        }
        if let exact = pageIndex(forChapter: anchor.chapterIndex, paragraph: anchor.paragraphIndex, in: blocks) {
            return exact
        }
        return min(max(pagedPageIndex, 0), max(blocks.count - 1, 0))
    }

    private func pageIndex(forChapter chapter: Int, paragraph: Int, in blocks: [ReaderPageBlock]) -> Int? {
        var lastInChapter: Int?
        for (index, block) in blocks.enumerated() {
            guard !block.isPlaceholder, block.chapterIndex == chapter else { continue }
            let first = block.firstParagraphIndex ?? 0
            if first >= paragraph { return index }
            lastInChapter = index
        }
        if let lastInChapter { return lastInChapter }
        if let placeholder = blocks.firstIndex(where: { $0.isPlaceholder && $0.chapterIndex == chapter }) {
            return placeholder
        }
        return blocks.firstIndex { !$0.isPlaceholder && $0.chapterIndex >= chapter }
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

        // Chapter-local pagination cache. A signature change (typography,
        // viewport, image style) invalidates every chapter at once.
        let layoutSignature = chapterPageLayoutSignature
        if chapterPageCacheSignature != layoutSignature {
            chapterPageCache.removeAll()
            chapterPageCacheSignature = layoutSignature
        }

        // 分页与页面渲染共用同一份几何：ReaderPageGeometry 已经把安全区、页眉带、
        // 正文带和页脚带算成确定坐标，这里不再重复扣 safeArea / padding。
        let geometry = pagedPageGeometry
        let typography = ReaderPageTypography(
            font: fontFamily.uiFont(ofSize: CGFloat(fontSize), customPostScriptName: customFontPostScriptName),
            titleFont: fontFamily.uiFont(ofSize: CGFloat(ReaderTypographyDefaults.titleFontSize(for: fontSize)), weight: .bold, customPostScriptName: customFontPostScriptName),
            lineSpacing: CGFloat(lineSpacing),
            letterSpacing: CGFloat(letterSpacing),
            paragraphSpacing: CGFloat(paragraphSpacing),
            firstLineIndent: CGFloat(paragraphIndent),
            titleSpacing: CGFloat(titleSpacing),
            contentWidth: geometry.contentWidth,
            // 2pt 缓冲只吸收 TextKit 行框与 SwiftUI Text 渲染之间的亚像素差，
            // 不再承担「安全区 / 页眉 / 页脚」的二次扣减。
            contentHeight: max(geometry.contentHeight - 4, 240)
        )
        var titleTypography = typography
        titleTypography.lineSpacing = 0
        titleTypography.letterSpacing = 0

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
            let chapterPages: [ReaderPageBlock]
            if let cached,
               cached.layoutSignature == layoutSignature,
               cached.contentSignature == contentSignature {
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
                placeholderDirection: page.placeholderDirection
            )
        }
    }

    private func appendPages(
        for section: ReaderChapterSection,
        typography: ReaderPageTypography,
        titleTypography: ReaderPageTypography
    ) -> [ReaderPageBlock] {
        var pages: [ReaderPageBlock] = []
        var currentEntries: [ReaderPageEntry] = []
        var pageOrdinal = 0
        let transformedTitle = ReaderTextTransform.displayText(section.title, traditionalChinese: traditionalChineseEnabled)
        // 页眉模式：章节名画在页眉带，正文第一页从与后续页完全相同的位置开始，
        // 不再给标题预留 40~50pt 的正文高度。只有「正文大标题」模式保留旧行为。
        var currentHeight: CGFloat = 0
        var currentIncludesTitle = false
        if chapterHeadingStyle == .inline {
            currentHeight = ReaderPageLayoutEngine.measureHeight(
                transformedTitle,
                typography: titleTypography,
                font: typography.titleFont
            ) + typography.titleSpacing
            currentIncludesTitle = true
        }

        func flush() {
            pages.append(
                ReaderPageBlock(
                    id: pages.count,
                    includesTitle: currentIncludesTitle,
                    paragraphs: currentEntries,
                    chapterIndex: section.chapterIndex,
                    chapterTitle: transformedTitle,
                    pageOrdinal: pageOrdinal
                )
            )
            pageOrdinal += 1
            currentEntries = []
            currentHeight = 0
            currentIncludesTitle = false
        }

        for (index, paragraph) in section.paragraphs.enumerated() {
            let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            if ReaderImageSizingPolicy.imageURL(in: trimmed) != nil {
                // `ReaderIllustrationView` also draws the caption row and its
                // vertical padding. Reserving only the bitmap height let a
                // text-plus-image page overflow and clip the last line.
                let captionBudget = ReaderImageSizingPolicy.pagedCaptionHeight
                let imageHeight = min(
                    ReaderImageSizingPolicy.maximumHeight(
                        for: currentImageStyle,
                        viewportHeight: pagedLayoutViewportSize.height,
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
                    currentEntries.append(ReaderPageEntry(
                        index: index,
                        text: paragraph,
                        chapterIndex: section.chapterIndex
                    ))
                    currentHeight = cardHeight
                    flush()
                } else {
                    let spacing = currentEntries.isEmpty ? 0 : typography.paragraphSpacing
                    if !currentEntries.isEmpty && currentHeight + spacing + cardHeight > typography.contentHeight {
                        flush()
                    }
                    let spacingAfterFlush = currentEntries.isEmpty ? 0 : typography.paragraphSpacing
                    currentEntries.append(ReaderPageEntry(
                        index: index,
                        text: paragraph,
                        chapterIndex: section.chapterIndex
                    ))
                    currentHeight += spacingAfterFlush + cardHeight
                    if currentHeight >= typography.contentHeight {
                        flush()
                    }
                }
                continue
            }

            // The stored page text includes the first-line indent so the paged
            // surface and TextKit measure exactly the same string. Continuation
            // chunks start at a line boundary and therefore carry no indent.
            let transformedParagraph = ReaderTextTransform.displayText(paragraph, traditionalChinese: traditionalChineseEnabled)
            let display = ReaderPageLayoutEngine.displayText(
                transformedParagraph,
                fontSize: CGFloat(fontSize),
                indent: typography.firstLineIndent
            )
            let wholeHeight = ReaderPageLayoutEngine.measureHeight(display, typography: typography)
            let spacing = currentEntries.isEmpty ? 0 : typography.paragraphSpacing

            if currentHeight + spacing + wholeHeight <= typography.contentHeight + 0.5 {
                currentEntries.append(ReaderPageEntry(
                    index: index,
                    text: display,
                    chapterIndex: section.chapterIndex
                ))
                currentHeight += spacing + wholeHeight
                continue
            }

            let minLineHeight = ceil(typography.font.lineHeight) + 2
            let remaining = typography.contentHeight - currentHeight - spacing
            if !currentEntries.isEmpty, remaining < minLineHeight {
                flush()
            } else if currentEntries.isEmpty, currentIncludesTitle,
                      remaining < minLineHeight {
                flush()
            }

            let available: CGFloat
            if currentEntries.isEmpty {
                available = max(typography.contentHeight - currentHeight, minLineHeight)
            } else {
                available = max(
                    typography.contentHeight - currentHeight - typography.paragraphSpacing,
                    minLineHeight
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
                    ReaderPageEntry(
                        index: index,
                        text: chunk.text,
                        chunkIndex: chunkIndex,
                        chapterIndex: section.chapterIndex
                    )
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
}

struct ReaderPageEntry: Equatable, Identifiable {
    let index: Int
    let text: String
    /// Non-zero when a long paragraph was split across page boundaries.
    var chunkIndex: Int = 0
    /// Owning chapter. The window merges several chapters into one page model;
    /// paragraph 3 of chapter 8 must not collide with paragraph 3 of chapter 9
    /// in SwiftUI's identity diff.
    var chapterIndex: Int = -1
    var isContinuation: Bool { chunkIndex > 0 }
    var id: String { "\(chapterIndex)-\(index)-\(chunkIndex)" }
}

struct ReaderPageBlock: Identifiable, Equatable {
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
    private var remoteCommandTargets: [(MPRemoteCommand, Any)] = []
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
        if engineKind == .file {
            playLocalVoiceSegment(segment)
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
private struct ReaderNavigationPopLock: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> LockViewController {
        LockViewController()
    }

    func updateUIViewController(_ uiViewController: LockViewController, context: Context) {
        uiViewController.applyPopLock()
    }

    static func dismantleUIViewController(_ uiViewController: LockViewController, coordinator: ()) {
        uiViewController.restorePopLock()
    }

    final class LockViewController: UIViewController {
        private weak var lockedNavigationController: UINavigationController?

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
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
            restorePopLock()
        }

        func applyPopLock() {
            guard let nav = navigationController else { return }
            lockedNavigationController = nav
            nav.interactivePopGestureRecognizer?.isEnabled = false
            let selector = Selector(("interactiveContentPopGestureRecognizer"))
            if nav.responds(to: selector),
               let contentPop = nav.value(forKey: "interactiveContentPopGestureRecognizer") as? UIGestureRecognizer {
                contentPop.isEnabled = false
            }
        }

        func restorePopLock() {
            guard let nav = lockedNavigationController ?? navigationController else { return }
            nav.interactivePopGestureRecognizer?.isEnabled = true
            let selector = Selector(("interactiveContentPopGestureRecognizer"))
            if nav.responds(to: selector),
               let contentPop = nav.value(forKey: "interactiveContentPopGestureRecognizer") as? UIGestureRecognizer {
                contentPop.isEnabled = true
            }
            lockedNavigationController = nil
        }
    }
}
