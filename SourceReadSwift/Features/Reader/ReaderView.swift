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
    @State private var hasResolvedOpeningPreview = false
    @State private var chromeState = ReaderChromeStateMachine()
    @State private var nativeMoreMenuPresentation = ReaderMenuPresentation()
    @State private var tabChromeOwner = UUID()
    @State private var readerSessionEnded = false
    @State private var showChapterList = false
    @State private var showBookmarks = false
    @State private var showBookDetailSheet = false
    @State private var showContentFilter = false
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
    @State private var settingsTab = 0
    @AppStorage("reader.atelierEnabled") private var usesAtelier = true
    @AppStorage("reader.bindingRevision") private var bindingRevision = ""
    @AppStorage("reader.chapterDecoration") private var chapterDecorationRaw = ReaderChapterDecoration.none.rawValue
    @AppStorage("reader.chapterAlignment") private var chapterAlignmentRaw = ReaderChapterAlignment.leading.rawValue
    @AppStorage("reader.menuPaperOpacity") private var menuPaperOpacity = 0.97
    @AppStorage("reader.menuUsesWallpaper") private var menuUsesWallpaper = false
    @AppStorage("reader.menuSurfaceStyle") private var menuSurfaceStyle = "system"

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
    @State private var tapPageTurnRequest: ReaderPageTurnRequest?
    @State private var autoScrollTask: Task<Void, Never>?
    @State private var sleepTimerTask: Task<Void, Never>?
    @State private var positionPersistTask: Task<Void, Never>?
    @State private var pageLayoutTask: Task<Void, Never>?
    /// Chapters wait in this queue instead of all hitting the source at once.
    /// Nearest-first, one at a time: a distant prefetch can never finish ahead
    /// of the chapter the reader is about to cross into.
    @State private var prefetchQueue: [Int] = []
    @State private var prefetchTask: Task<Void, Never>?
    @State private var backgroundChapterPrecache = ReaderBackgroundChapterPrecache()
    @State private var paginationWarmupTask: Task<Void, Never>?
    @State private var paginationWarmupGeneration = 0
    @State private var prefetchGeneration = 0
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
    /// 椤甸潰瀹瑰櫒鐨勭湡瀹炲嚑浣曪紙UIPageViewController 瀛愭帶鍒跺櫒鍙兘姣旀牴瑙嗗浘灏忎竴鍦堬級銆?
    /// 鍒嗛〉寮曟搸浣跨敤杩欎竴浠斤紝鑰屼笉鏄洸鐩浉淇℃牴瑙嗗浘鐨?viewport銆?
    @State private var pagedPageContainerMetrics: ReaderPageContainerMetrics?
    /// Page-to-paragraph mapping is immutable between layout-cache revisions.
    /// Keep it in state instead of rebuilding an array with `compactMap` every
    /// time SwiftUI reevaluates the reader body or a speech callback arrives.
    @State private var positionMappingCache = ReaderPositionMapping(paragraphCount: 0)
    /// The reader may live in a split view or Stage Manager window. Keep the
    /// actual container size instead of using UIScreen.main, which describes
    /// the physical display and can be stale for the current scene.
    @State private var viewportSize: CGSize = .zero
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
    /// "姝ｅ湪鍔犺浇涓嬩竴绔? for chapters the local book already had in memory.
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
    /// 鎷栧姩绔犺妭杩涘害鏉℃椂鐨勫疄鏃惰烦绔犱换鍔°€傛墜鎸囪繕鍦ㄦ粦灏变笉鍋滈噸鎺掞紝
    /// 鍋滀綇 0.12s 鎵嶇湡姝ｈ烦锛岄伩鍏嶄竴娆℃嫋鍔ㄩ噷濉炶繘鍗佸嚑涓珷鑺傚姞杞姐€?
    @State private var chapterSeekTask: Task<Void, Never>? = nil
    /// 棣栧抚鏄惁宸茬粡钀藉埌銆屼笂娆¤鍒扮殑閭ｄ竴娈点€嶃€備负 false 鏃舵枃瀛楀眰鍏堥€忔槑锛?
    /// 閬垮厤鐢ㄦ埛鍏堢湅鍒扮 1 绔犵珷棣栥€侀殢鍚庤鍒囨垚鎭㈠浣嶇疆鐨勯偅涓€涓嬮棯璺炽€?
    @State private var hasOpeningPositionTimedOut = false
    @State private var openingPositionAttempt = 0
    @State private var isRetryingOpeningPosition = false
    @State private var didLandInitialPosition = false
    private final class ReaderTapGestureTracker {
        var startedAt: Date?
    }
    @State private var tapGestureTracker = ReaderTapGestureTracker()
    /// 涓€娆＄偣鍑诲彧澶勭悊涓€娆°€俻aged 妯″紡閲屽揩鐓ч〉瀹瑰櫒涓?SwiftUI 鎵嬪娍鍙兘鍦ㄥ悓涓€甯?
    /// 鍚勬姤涓€娆★紝鐢ㄦ埛鐪嬪埌鐨勫氨鏄€岀偣涓€涓嬭烦浜嗕袱椤点€嶃€?
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
    // 椤佃剼涓変欢濂楀悇鑷彲鍏筹紙瀵圭収棣欒壊闂洪榿 tr_showTime / tr_showBatView / tr_showBatLabel锛夈€?
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
    /// 绔犺妭鏍囬鍛堢幇鏂瑰紡銆傞粯璁ゃ€岄〉鐪夊皬鏍囬銆嶏細姣忛〉椤堕儴 12pt 绔犺妭鍚嶏紝姝ｆ枃浠庨〉鐪変笅寮€濮嬶紝
    /// 涓庢爾闃?/ 寮€鍏冮槄璇荤殑闃呰椤典竴鑷淬€?
    @AppStorage("reader.chapterHeadingStyle") private var chapterHeadingStyleRaw = ReaderPageChromeLayout.header.rawValue
    /// 鏍栭槄鐨勩€屽唴瀹瑰欢浼歌嚦椤电湁椤佃剼鍖哄煙銆嶏細寮€鍚悗姝ｆ枃璺ㄨ繃椤电湁椤佃剼甯︼紝椤电湁椤佃剼娴湪姝ｆ枃涓娿€?
    @AppStorage("reader.contentExtendsIntoChrome") private var contentExtendsIntoChrome = false
    @AppStorage("reader.ttsRate") private var ttsRate: Double = 0.52
    @AppStorage("reader.ttsEngine") private var ttsEngineRawValue: String = TTSEngineKind.local.rawValue
    @AppStorage("reader.httpTTSVoiceID") private var httpTTSVoiceID: Int = HttpTTSVoice.defaultVoiceID
    @AppStorage("reader.autoScrollDelay") private var autoScrollDelay: Double = 2.0
    @AppStorage("reader.sleepTimerMinutes") private var sleepTimerMinutes: Int = 0
    @AppStorage("reader.background") private var backgroundRawValue: String = ReaderBackground.white.rawValue
    /// 澹佺焊濉厖鏂瑰紡锛氬～鍏?/ 閫傚簲 / 鎷変几銆傚榻愬紑鍏?BoxFit 涓庢爾闃?UIImageView contentMode銆?
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
            let chapterNumber = min(
                max(declaredChapterNumber(in: currentDisplayChapterTitle) ?? (displayIndex + 1), 1),
                displayTotal
            )
            parts.append("绗?\(chapterNumber) / \(displayTotal) 绔?)
            parts.append("\(percentage)%")
        } else {
            parts.append("绗?\(displayIndex + 1) 绔?)
        }
        if readerMode != .scroll {
            if let chapterPages = currentChapterPageStatus {
                parts.append(chapterPages)
            } else {
                let pageCount = max(pagedBlocks.count, 1)
                let page = min(max(pagedPageIndex + 1, 1), pageCount)
                parts.append("椤?\(page)/\(pageCount)")
            }
        }
        return parts.joined(separator: " 路 ")
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
        return "椤?\(min(ordinal, count))/\(count)"
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

    /// The chapter number printed in the TOC title ("绗?5绔?鍦板鍏ㄥ浘"), which
    /// can differ from the array index when a source ships extra volumes.
    private func declaredChapterNumber(in title: String) -> Int? {
        guard let range = title.range(of: #"绗琝s*[0-9]+\s*绔?#, options: .regularExpression) else { return nil }
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
                        message: "绗?\(next + 1) 绔犲姞杞藉け璐ワ細\(failure)",
                        isFailure: true
                    )
                }
                if windowLoadingIndices.contains(next) {
                    return ScrollChapterStatus(
                        chapterIndex: next,
                        message: "姝ｅ湪鍔犺浇绗?\(next + 1) 绔犫€?,
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
                        message: "绗?\(previous + 1) 绔犲姞杞藉け璐ワ細\(failure)",
                        isFailure: true
                    )
                }
                if windowLoadingIndices.contains(previous) {
                    return ScrollChapterStatus(
                        chapterIndex: previous,
                        message: "姝ｅ湪鍔犺浇绗?\(previous + 1) 绔犫€?,
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
        if sleepTimerMinutes == -1 { return "鎾畬褰撶珷" }
        if sleepTimerMinutes > 0 { return "\(sleepTimerMinutes)鍒? }
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
        // Keep the window bounded, but local imports are cheap to widen: the
        // paragraphs already live in the bookshelf model, so the only cost is
        // pagination. Force five chapters on each side so an old AppStorage
        // value of 2 still gets ten chapters of instant back/forward reading.
        let base = ReaderChapterWindowPolicy.radius(forPreloadCount: preloadChapterCount)
        return isLocalChapterBook ? max(base, ReaderPreloadPolicy.maximumCount) : max(base, 5)
    }

    /// 鏈湴瀵煎叆鐨勪功锛坙ocalChapters 鍦ㄤ功鏋舵ā鍨嬮噷锛夛紝绔犺妭璇诲彇涓嶇粡杩囦功婧愩€?
    /// `localChapters` 鏄悗鍔犵殑鍙€夊瓧娈碉紝鏃т功鏋跺彲鑳借В鐮佹垚 nil锛涙湰鍦板鍏ョ殑
    /// 韬唤鏍囪杩樺湪锛屼笉鑳借鏁存潯鏈湴蹇矾寰勶紙瀹界獥鍙?+ 鍚屾 seed锛夊洜姝ゅけ鏁堛€?
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
        return "绗?\(index + 1) 绔?
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

    /// 鍒嗛〉鐪熷疄鍙敤鐨勮鍙ｃ€傞娆℃覆鏌撳墠鍥為€€鍒版牴瑙嗗彛锛岄〉闈㈤娆″竷灞€鍚庣珛鍗虫崲鎴愬疄娴嬪€笺€?
    /// 杩欒В鍐充簡銆屽垎椤垫寜 852pt 鎺掋€乁IPageViewController 鍙粰 793pt銆嶅鑷寸殑椤靛熬鎴柇銆?
    private var pagedLayoutViewportSize: CGSize {
        if let metrics = pagedPageContainerMetrics, metrics.isValid {
            return metrics.size
        }
        return effectiveViewportSize
    }

    /// 鍒嗛〉涓庢覆鏌撳叡鐢ㄧ殑鍞竴鍑犱綍鏉ユ簮銆?
    private var pagedPageGeometry: ReaderPageGeometry {
        let margin = CGFloat(pagePadding)
        if let metrics = pagedPageContainerMetrics, metrics.isValid {
            return metrics.geometry(
                horizontalMargin: margin,
                chromeLayout: chapterHeadingStyle,
                contentExtendsIntoChrome: contentExtendsIntoChrome,
                headerFontSize: CGFloat(headerFontSize), headerTopGap: CGFloat(headerTopGap)
            )
        }
        return ReaderPageGeometry(
            viewportSize: effectiveViewportSize,
            safeTop: readerTopSafeInset,
            safeBottom: readerFooterSafeInset,
            horizontalMargin: margin,
            chromeLayout: chapterHeadingStyle,
            contentExtendsIntoChrome: contentExtendsIntoChrome,
                headerFontSize: CGFloat(headerFontSize), headerTopGap: CGFloat(headerTopGap)
        )
    }

    /// cover 妯″紡鐨勯〉闈㈠湪鍚屼竴妫?SwiftUI 鏍戦噷锛岀敤 PreferenceKey 鍥炰紶锛沺age-curl /
    /// 婊戝姩妯″紡鐨勯〉闈㈠湪鐙珛 UIHostingController 閲岋紝preference 鍑轰笉鏉ワ紝鏀圭敱
    /// PageCurlReaderView 鐨勫竷灞€鍥炶皟鎶婄湡瀹?bounds 浼犲洖鏉ャ€備袱鏉¤矾閮芥眹鍒拌繖閲屻€?
    private func adoptPageContainerMetrics(_ metrics: ReaderPageContainerMetrics) {
        guard metrics.isValid else { return }
        // 0.5pt 鍚搁檮锛岄伩鍏嶅儚绱犵骇鎶栧姩瑙﹀彂鏃犱紤姝㈢殑閲嶆柊鍒嗛〉銆?
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
    /// one throws the first result away 鈥?the reason a freshly opened local
    /// book paused on "姝ｅ湪鍔犺浇涓嬩竴绔? for chapters it already had in memory.
    private func endReaderSession() {
        guard !readerSessionEnded else { return }
        readerSessionEnded = true
        windowGeneration &+= 1
        cancelChapterJumpPreparation()
        geometrySettleTask?.cancel()
        geometrySettleTask = nil
        paginationWarmupRestartTask?.cancel()
        paginationWarmupRestartTask = nil
        chapterSeekTask?.cancel()
        chapterSeekTask = nil
        tocScrollTask?.cancel()
        tocScrollTask = nil
        positionPersistTask?.cancel()
        pageLayoutTask?.cancel()
        cancelPrefetch()
        cancelPaginationWarmup()
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
        pauseReadingActivity()
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
            // 涓婚/澶栬涔熸槸椤甸潰娓叉煋鐨勪竴閮ㄥ垎锛歱age-curl 鐨勯〉闈㈡槸鍒涘缓鏃跺揩鐓х殑
            // hosting controller锛屼笉鎹?key 灏变笉浼氶噸鐢?鈥斺€?杩欐鏄€屾崲涓婚瑕佺炕椤?
            // 鎵嶇敓鏁堛€嶇殑鎴愬洜銆?
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
            readerIsNight ? "dark" : "light"
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
            .readerOpeningContentReady(hasResolvedOpeningPreview || hasOpeningPositionTimedOut)
            .task(id: openingPositionAttempt) {
                guard readerOpeningManaged || hasOpeningPositionTimedOut else { return }
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                guard !Task.isCancelled, !hasResolvedOpeningPreview else { return }
                // A stalled restore is an actionable error, not permission to
                // reveal or persist the unpositioned first page.
                hasOpeningPositionTimedOut = true
                isRetryingOpeningPosition = false
            }
            .onPreferenceChange(ReaderPageContainerMetricsKey.self) { metrics in
                if let metrics {
                    adoptPageContainerMetrics(metrics)
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(
                // 浠呴拡瀵归潪婊氬姩鍒嗛〉妯″紡浣跨敤杞昏Е鎵嬪娍锛岀粷涓嶅湪璺濈涓?鏃舵嫤鎴嫋鎷斤紝
                // 褰诲簳閲婃斁 iOS 16 鍙婂叏鏈哄瀷鍦?WKWebView 涓?UIPageViewController 鐨勫師鐢熸粦鍔ㄤ笌缈婚〉鍝嶅簲銆?
                SpatialTapGesture()
                    .onEnded { value in
                        guard readerMode != .scroll, !textSelectionEnabled else { return }
                        handleReaderTap(at: value.location)
                    }
                , including: readerMode == .scroll ? .subviews : (textSelectionEnabled ? .none : .all)
            )

            if showSettings && settingsTab == 2 {
                tapZoneOverlay
                    .allowsHitTesting(false)
                }

            if hasOpeningPositionTimedOut {
                openingPositionRecovery
                    .zIndex(25)
            }

            // Menus change system-bar visibility, not the document inset.
            // Keep ink out of the status strip without moving the reading anchor.
            readerStatusBarBackdrop
                .zIndex(1)

            // A fixed, opaque chapter band also protects immersive reading;
            // it must not depend on whether the system clock is visible.
            if readerMode == .scroll {
                readerHeader
                    .zIndex(1)
            }

            // 鍒嗛〉妯″紡鐨勯〉鐪夐〉鑴氱敾鍦ㄦ瘡涓€椤靛唴閮紙瑙?pageSurface锛夛紝
            // 杩欐牱 page-curl 鐨勬瘡涓€寮犵焊閮借嚜甯﹂〉鐮佸拰绔犺妭鍚嶏紝涔熶笉浼氬嚭鐜?
            // 銆屽叏灞€椤电湁鍘嬪湪椤甸潰涓娿€佷綅缃張璺熷畨鍏ㄥ尯鎵撴灦銆嶇殑闂銆?
            if readerMode == .scroll,
               !showOverlay, !speechController.isSpeaking, !autoScrollEnabled {
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

            if showOverlay && !showSettings {
                readerOverlay
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.98, anchor: .center)),
                            removal: .opacity
                        )
                    )
                    .zIndex(10)
            }

            if textSelectionEnabled && !showSettings {
                VStack {
                    HStack {
                        Spacer()
                        Button("瀹屾垚閫夋嫨") {
                            textSelectionEnabled = false
                            presentOverlay()
                        }
                        .font(.caption.weight(.semibold)).buttonStyle(.borderedProminent)
                    }
                    Spacer()
                }
                .padding(.top, readerTopSafeInset + 8).padding(.trailing, 16).zIndex(11)
            }

            if let statusMessage {
                readerStatusBanner(message: statusMessage)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if let jump = pendingWindowJump, !showChapterList {
                VStack {
                    HStack(spacing: 10) {
                        ProgressView().tint(readerThemeTextColor)
                        Text("姝ｅ湪鎵撳紑 路 \(chapterTitle(for: jump.chapterIndex))")
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

            // Cloud TTS failures fall back to the system voice. Keep the
            // reason on screen (instead of a transient toast) so a silent
            // keychain/network failure never looks like the app ignored the
            // user's engine selection.
            if let speechErrorMessage = speechController.lastErrorMessage {
                readerSpeechErrorBanner(message: speechErrorMessage)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(4)
            }

            ZStack {
                if showSettings {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            closeSettingsPanel()
                        }
                        .transition(.opacity)

                    settingsPanel
                        .transition(motion.reducesMotion ? .opacity : .offset(y: ReaderSettingsLayoutPolicy.maxPanelHeight(
                            viewportHeight: effectiveViewportSize.height, bottomInset: readerFooterSafeInset) + readerFooterSafeInset + 16))
                }
            }
            // The outgoing scrim remains drawn during its transition, but it
            // must release touches as soon as the reader controls reappear.
            .allowsHitTesting(showSettings)
            .zIndex(20)

            if showGoalCelebrationToast {
                VStack {
                    HStack(spacing: 8) {
                        Text("馃帀")
                            .font(.system(size: 16))
                        Text("浠婃棩闃呰鐩爣杈炬垚锛佸凡杩炵画闃呰 \(streakDaysCount) 澶?)
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
        .background(ReaderNavigationPopLock(allowSystemReturn: allowsNativeBookReturn))
        .background(ReaderTabChromeExitBridge(owner: tabChromeOwner))
        .background(ReaderExitSwipeBridge(
            enabled: ReaderExitSwipePolicy.isProseFallbackEnabled(
                reducesMotion: motion.reducesMotion, allowsBookReturn: allowsNativeBookReturn
            ) || ReaderExitSwipePolicy.isEnabled(
                menuVisible: showOverlay, settingsVisible: showSettings,
                coverPresented: showChapterList || temporaryCoverPresented,
                scrollMode: readerMode == .scroll
            ),
            onExit: requestReaderExit, prefersSystemReturn: readerUsesBookReturn
        ))
        .overlay(alignment: .topLeading) { ReaderFrameHUD() }
        .navigationBarBackButtonHidden(!allowsNativeBookReturn)
        .toolbar(.hidden, for: .navigationBar, .tabBar)
        .statusBarHidden(!showOverlay && !showSystemStatusBar)
        // 鍏ㄥ睆闃呰鏃惰繛 home indicator 涓€璧锋贰鍑猴紱鎵撳紑鑿滃崟鎴栧己鍒剁郴缁熺姸鎬佹爮鏃舵仮澶嶃€?
        .persistentSystemOverlays(showOverlay || showSystemStatusBar ? .automatic : .hidden)
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
                rebuildPagedBlocksCache()
                return
            }
            guard let name = background.wallpaperAssetName else { return }
            let loaded = await ReaderIllustratedBackgroundStore.load(name)
            guard loaded != nil, !Task.isCancelled else { return }
            // Warm before versioning UIKit snapshots; otherwise a cached page
            // could keep its pre-decode blank background forever.
            backgroundWallpaperRevision = UUID()
            rebuildPagedBlocksCache()
        }
        .preferredColorScheme(background.isDark ? .dark : .light)
        // `preferredColorScheme` only drives the window. The paged reader
        // builds `UIHostingController`s outside the SwiftUI environment, and
        // system controls inside the chrome read `colorScheme` directly, so
        // the reader theme is also pushed into the environment here.
        .environment(\.colorScheme, readerIsNight ? .dark : .light)
        .highRefreshRateSurface()
        .ignoresSafeArea()
        .confirmationDialog("璐拱鏈珷", isPresented: $showPayActionConfirmation, titleVisibility: .visible) {
            Button("缁х画璐拱") {
                Task { await performPayAction() }
            }
            Button("鍙栨秷", role: .cancel) {}
        } message: {
            Text(content.title)
        }
        .alert("璐拱鎻愮ず", isPresented: $showPayActionResult) {
            Button("濂?, role: .cancel) {}
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
                backgroundWallpaperRevision = UUID()
                rebuildPagedBlocksCache(); syncPerBookOverrideIfNeeded(); HapticFeedback.success()
            }
        }
        .onDisappear { wallpaperImportTask?.cancel(); wallpaperImportRevision = UUID() }
        .sheet(isPresented: $showFontManagementSheet) {
            NavigationStack {
                CustomFontManagementView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("瀹屾垚") {
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
        .sheet(isPresented: $showContentFilter) {
            NavigationStack {
                PurifyRulesView()
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("瀹屾垚") { showContentFilter = false } } }
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
                        sourceName: "褰撳墠涔︽簮",
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
        .onAppear {
            appState.acquireTabChromeHidden(owner: tabChromeOwner)
            // Dismissing the full-screen TOC must not replay initial position,
            // markReaderOpened or the initial synchronous pagination pass.
            isReaderVisible = true
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
            appState.acquireTabChromeHidden(owner: tabChromeOwner)
            chromeState.setInitialOverlayVisible(initialOverlayVisible)
            seedWindow()
            if readerMode != .scroll { rebuildPagedBlocksCache() }
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
        .onDisappear {
            isReaderVisible = false
            pauseReadingActivity()
            // Ownership is visibility-scoped even for temporary covers.
            appState.releaseTabChromeHidden(owner: tabChromeOwner)
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
                positionPersistTask?.cancel()
                positionPersistTask = nil
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
            rebuildPagedBlocksCache(anchorOverride: anchor)
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
            positionPersistTask?.cancel()
            positionPersistTask = nil
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
            // Geometry only. Cached chapters stay around 鈥?they are simply not
            // reusable for the new container 鈥?and the warmup restarts after
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
        ZStack {
            if background == .custom, let image = ReaderCustomWallpaperStore.cachedWallpaper {
                ReaderWallpaperView(
                    image: image,
                    fillMode: ReaderWallpaperFillMode(rawValue: customWallpaperFillModeRaw) ?? .fill,
                    adjustment: ReaderCustomWallpaperStore.adjustment
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(backgroundWallpaperRevision)
                if customBackgroundIsDark {
                    Color.black.opacity(readerIsNight ? 0.60 : 0.35)
                } else {
                    Color.white.opacity(readerIsNight ? 0.15 : 0.20)
                }
            } else if background.hasTexture {
                ReaderPaperTextureView(background: background, night: readerIsNight)
            } else {
                readerThemeBackground
            }
        }
        .ignoresSafeArea()
    }

    // 椤舵爮鏂囧瓧涔熷睘浜庝富棰橈細绯荤粺娣辫壊 + 娴呰壊涓婚鏃?.primary/.secondary
    // 浼氳В鏋愭垚鐧借壊锛屽帇鍦ㄧ背鑹叉爮涓婄洿鎺ョ湅涓嶈銆?
    private var chromeForeground: Color {
        readerThemeTextColor.opacity(0.94)
    }

    private var chromeSecondaryForeground: Color {
        readerThemeTextColor.opacity(0.62)
    }

    /// 闃呰鍣ㄦ槑鏆楀畬鍏ㄧ敱鎵€閫変富棰樺喅瀹氾紝涓嶅啀璺熼殢绯荤粺 colorScheme銆?
    /// 涔嬪墠杩欓噷璇?readerIsNight锛岀郴缁熸繁鑹叉椂姣忎釜涓婚閮藉彇澶滈厤鑹诧紝
    /// 鐢ㄦ埛鎬庝箞鎹富棰橀兘鏄粦鐨勩€?
    private var readerIsNight: Bool { background.isDark }

    private var readerThemeTextColor: Color {
        background.textColor(isNight: readerIsNight)
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
        // 姣忔 body 姹傚€奸兘閲嶅缓杩欎釜鏁扮粍锛堝嚑鐧惧埌涓婂崈娈碉級鏄粴鍔ㄦ湡鏈€绋冲畾鐨勪竴绗旀氮璐癸細
        // 鎸囩汗娌″彉灏卞鐢ㄤ笂娆＄殑缁撴灉锛屽彧鏈夌珷鑺傜獥鍙ｆ垨姝ｆ枃鐪熺殑鍙樹簡鎵嶉噸寤恒€?
        let key = "\(bookID)|\(scrollContentFingerprint)"
        return ReaderScrollParagraphCache.shared.paragraphs(for: key) {
            guard !windowSections.isEmpty else { return content.paragraphs }
            var result: [String] = []
            for (offset, section) in windowSections.enumerated() {
                if offset > 0 {
                    // 绔犺妭鏍囬涓嶅啀鍔犵牬鎶樺彿锛氶槄璇诲櫒閲屾爣棰樺簲褰撳乏瀵归綈銆佸共鍑€涓€琛屻€?
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

    /// 缁撴瀯鍖栫珷鑺傜獥鍙ｏ紝婊氬姩闈㈢敤瀹冪敓鎴愮珷鑺傛爣棰樹笌娈佃惤鍏冪礌銆?
    ///
    /// 鏃у疄鐜版妸绐楀彛鍘嬫垚涓€缁?`[String]`锛氬垎闅旂敤鐨勭珷鑺傛爣棰樺拰姝ｆ枃娈佃惤闀垮緱涓€妯′竴鏍凤紝
    /// 浜庢槸鏍囬鍙兘缁ф壙姝ｆ枃瀛楀彿涓庨鑹层€傜幇鍦ㄦ爣棰樻湁鐙珛鍏冪礌锛屾牱寮忚〃閲屾敼涓€澶勫氨澶熴€?
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

    /// Legado `ReadBookActivity.payAction()`锛氱‘璁ゅ悗鎵ц涔︽簮鐨勮喘涔拌鍒欍€?
    /// 寮曟搸璐熻矗 JS銆乧ookie 涓庢寔涔呯姸鎬侊紱瑙嗗浘鍙鐞嗕笁绉嶇粨鏋溿€?
    private func performPayAction() async {
        guard let payAction = content.payAction?.trimmingCharacters(in: .whitespacesAndNewlines),
              !payAction.isEmpty else { return }
        guard let source = currentBookSource else {
            payActionResultMessage = "鎵句笉鍒颁功婧愶紝鏃犳硶鎵ц璐拱鎿嶄綔"
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
                payActionResultMessage = "鏃犳硶鎵撳紑璐拱椤甸潰"
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
            payActionResultMessage = "璐拱鎴愬姛锛屾鍦ㄥ埛鏂版湰绔?
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

    /// 棣栫珷鍔犺浇涓殑鍗犱綅锛氫富棰樿壊搴?+ 杩涘害鎸囩ず锛岄伩鍏嶃€岀偣杩涗功鍏堢櫧涓€浼氬効銆嶃€?
    private var readerLoadingPlaceholder: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(readerThemeTextColor.opacity(0.55))
            Text("姝ｅ湪鍔犺浇绔犺妭鈥?)
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

    /// 婊氬姩妯″紡鐨勬鏂囬《閮ㄥ唴杈硅窛锛氭樉绀洪〉鐪夋椂璁╁嚭椤电湁甯︼紝鍚﹀垯鍙伩璁╁垬娴枫€?
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

    /// 婊氬姩妯″紡搴曢儴鐘舵€佸甫锛氱粰椤佃剼鐙珛楂樺害锛屾鏂囪鍙ｅ湪椤佃剼涓婃柟鎴銆?
    private var scrollFooterReservedHeight: CGFloat {
        ReaderPageChrome.scrollFooterReservedHeight(statusPosition: statusPosition)
    }

    private var scrollReaderContent: some View {
        // 婊氬姩妯″紡鏀圭敱 WKWebView 娓叉煋銆傜珷鑺傜獥鍙ｇ殑澧炲垹鍦ㄦ枃妗ｅ唴鍋?DOM 琛ヤ竵锛?
        // 涓嶅啀鏁翠覆閲嶅缓 attributed string 鈥斺€?璺崇珷/璺ㄧ珷婊戝姩涓嶅啀鏈夈€屽厛娓呯┖鍐嶆帓鐗堛€?
        // 鐨勯偅涓€甯э紝涔熷氨涓嶄細鏁村睆绌虹櫧锛涙爣棰樻垚涓虹嫭绔嬬殑 h1/h2锛屽彲浠ュ拰姝ｆ枃鍒嗗紑閫犲瀷銆?
        WebScrollReaderView(
            sections: scrollSections,
            contentFingerprint: scrollContentFingerprint,
            resetToken: bookID,
            fontFamily: fontFamily,
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
            // 宸ュ叿鏍忔槸娴眰锛氭鏂囩殑椤堕儴鍐呰竟璺濆繀椤讳笌鑿滃崟寮€鍚堟棤鍏筹紝
            // 鍚﹀垯姣忔鍛煎嚭鑿滃崟鏁撮〉鏂囧瓧閮戒細寰€涓嬫帀涓€鏍硷紙鍏虫帀鍐嶅脊鍥炴潵锛夈€?
            topInset: scrollContentTopInset,
            textColor: background.uiTextColor(isNight: readerIsNight),
            surfaceColor: background == .custom || background.hasTexture ? .clear : background.uiColor(isNight: readerIsNight),
            highlightColor: AppTheme.accentUIColor.withAlphaComponent(background.isDark ? 0.22 : 0.12),
            currentParagraphIndex: speechFlatParagraphIndex ?? -1,
            scrollTarget: activeScrollTarget,
            scrollRequestKey: nativeScrollRequestKey,
            scrollTargetUTF16Offset: speechController.isSpeaking ? 0 : (paragraphJumpRequest?.utf16Offset ?? 0),
            animatedScrollDuration: autoScrollEnabled ? max(ReaderAutomationPolicy.clampedDelay(autoScrollDelay) * 0.9, 0.25) : (speechController.isSpeaking ? 0.35 : 0),
            textSelectionEnabled: textSelectionEnabled,
            showChapterEndBadge: false,
            traditionalChineseEnabled: traditionalChineseEnabled,
            bionicReadingEnabled: bionicReadingEnabled,
            imageStyle: currentImageStyle,
            imageHeaders: imageRequestHeaders,
            imageColumnWidth: illustrationColumnWidth,
            prioritizesSystemEdgeReturn: readerUsesBookReturn && motion.reducesMotion,
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
                resolveOpeningPreview()
            },
            onScrollInteractionChanged: { active in
                interactionGate.isScrollInteractionActive = active
                guard !active, !readerSessionEnded, interactionGate.scrollTrimDeferred else { return }
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
                // 鏂囨。鍐呴儴宸茬粡鍋氳繃浣嶇Щ / 鏃堕暱 / 鎯€т笁閲嶅垽瀹氾紝杩欓噷鍙妸鍧愭爣
                // 鎹㈡垚 3x3 鐐瑰嚮鍖猴紝閰嶇疆涓庝笁绉嶇炕椤垫ā寮忓叡鐢ㄥ悓涓€濂椼€?
                handleReaderTap(at: point)
            }
        )
        .ignoresSafeArea(.container, edges: .bottom)
        // 鍏堥摵婊＄墿鐞嗗睆锛屽啀浠庡簳閮ㄨ鍑虹姸鎬佸甫锛氶〉鑴氫笉鍐嶅拰姝ｆ枃閲嶅彔銆?
        .padding(.bottom, scrollFooterReservedHeight)
        .overlay {
            // 鍙湁銆岃繖涓€娈电獥鍙ｉ噷纭疄娌℃湁浠讳綍娈佃惤銆嶆墠鐩栧崰浣嶅眰銆?
            // 涔嬪墠鍙垽 scrollModeParagraphs 鏄惁涓虹┖锛氭粦鍔ㄨ法绔犳椂瀹冧細琚噸绠楁垚绌烘暟缁勶紝
            // 浜庢槸鏁村睆琚笉閫忔槑鍗犱綅鐩栦綇 鈥斺€?灏辨槸銆屽線涓婃粦涓€鐐圭獊鐒跺叏鐧姐€嶃€?
            if scrollSections.allSatisfy({ $0.paragraphs.isEmpty }) {
                readerLoadingPlaceholder
            }
        }
        .onAppear {
            if scrollParagraphTarget > 0, paragraphJumpRequest == nil {
                didLandInitialPosition = false
                scrollJumpGeneration &+= 1
                DispatchQueue.main.async {
                    paragraphJumpRequest = ParagraphJumpRequest(index: scrollParagraphTarget)
                }
            }
        }
        .onChange(of: chapterIndex) { newValue in
            // 鐖跺眰鍙兘鍏堝彂甯冩柊绔犲彿銆佸悗鎷垮埌姝ｆ枃锛涙鏃堕噸缃細鎶婁笂涓€绔犵殑
            // 娈佃惤鎸傚埌鏂扮珷鍙蜂笂銆傜瓑 content 杩戒笂鍐嶉噸缃€?
            guard content.chapter.index == newValue else { return }
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
            // Let the first document/page commit before neighbouring chapters
            // start patching it. Cancellation still takes effect immediately.
            try? await Task.sleep(nanoseconds: 180_000_000)
            while !prefetchQueue.isEmpty,
                  !Task.isCancelled,
                  prefetchGeneration == token,
                  windowGeneration == generation {
                // One runloop between chapters: DOM patches and page
                // rebuilds are main-actor work, and a back-to-back burst is
                // what made neighbour prefetch stutter.
                await Task.yield()
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
        backgroundChapterPrecache.cancel()
        prefetchGeneration &+= 1
        prefetchTask?.cancel()
        prefetchTask = nil
        prefetchQueue.removeAll()
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
            return .failure("鐩綍涓病鏈夌 \(index + 1) 绔狅紝鍙兘宸茶涔︽簮绉婚櫎")
        }
        guard let sourceURL = windowSourceURL,
              let source = appState.sourceStore.source(for: sourceURL) else {
            return .failure("涔︽簮涓嶅瓨鍦ㄦ垨宸茶鍒犻櫎")
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
    /// dropped frame plus the 鈥減age jumps back鈥?symptom. Defer the rebuild
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
            rebuildPagedBlocksCache()
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
        let resolved = resolvedReadingPosition(forFlatIndex: safeIndex)
        if resolved.chapterIndex != windowCurrentChapterIndex {
            windowCurrentChapterIndex = resolved.chapterIndex
            prefetchWindow(around: resolved.chapterIndex)
            trimWindowIfNeeded()
            touchChapterCache(resolved.chapterIndex)
        }
        scheduleReadingPositionPersistence()
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
        .onChange(of: speechController.currentParagraphIndex) { target in
            guard target >= 0, let flat = speechFlatParagraphIndex else { return }
            pagedPageIndex = pageIndex(containingParagraph: flat)
        }
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
        .onChange(of: speechController.currentParagraphIndex) { target in
            guard target >= 0, let flat = speechFlatParagraphIndex else { return }
            pagedPageIndex = pageIndex(containingParagraph: flat)
        }
    }

    /// Opaque paper colour handed to the UIKit paging hosts. `nil` for a
    /// custom wallpaper, which must stay transparent so the image shows
    /// through; every other theme paints the paper itself, which is what stops
    /// the white flash while a chapter is swapped.
    private var pagedPageBackgroundColor: UIColor? {
        background == .custom ? nil : background.uiColor(isNight: readerIsNight)
    }

    /// `preferredColorScheme` on the SwiftUI root does not reach the
    /// `UIHostingController`s inside the paging surfaces, so the reader theme
    /// is pushed into them explicitly. Without this a system-dark device made
    /// every paper black regardless of the selected appearance.
    private var pagedUserInterfaceStyle: UIUserInterfaceStyle {
        background.isDark ? .dark : .light
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
        .onChange(of: speechController.currentParagraphIndex) { target in
            guard target >= 0, let flat = speechFlatParagraphIndex,
                  !interactionGate.isPageInteractionActive else { return }
            pagedPageIndex = pageIndex(containingParagraph: flat)
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
        guard readerOpeningManaged || hasOpeningPositionTimedOut,
              !hasResolvedOpeningPreview, pagedBlocksCache.indices.contains(pagedPageIndex) else { return }
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
        let highlightKey = "\(speechChapterIndex)-\(speechController.currentParagraphIndex)"
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
            weight: .regular,
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
        return ReaderPageTextSpec(
            title: title,
            paragraphs: paragraphs,
            style: ReaderPageTextBuilder.Style(
                bodyFont: bodyFont,
                titleFont: titleFont,
                textColor: background.uiTextColor(isNight: readerIsNight),
                highlightColor: AppTheme.accentUIColor.withAlphaComponent(background.isDark ? 0.22 : 0.12),
                lineSpacing: CGFloat(lineSpacing),
                letterSpacing: CGFloat(letterSpacing),
                paragraphSpacing: CGFloat(paragraphSpacing),
                titleSpacing: CGFloat(titleSpacing),
                firstLineIndent: CGFloat(paragraphIndent),
                chapterDecoration: page.pageOrdinal == 0 && pagedPageGeometry.contentHeight >= chapterDecoration.height + titleFont.lineHeight + CGFloat(titleSpacing) + 8 ? chapterDecoration : .none,
                chapterAlignment: chapterAlignment
            )
        )
    }

    /// 棰勫缓鍓嶅悗鍚?radius 椤电殑瀵屾枃鏈紙鍓?5 鍚?5锛夈€?
    /// 缈婚〉棣栧抚鍙繚鐣?TextKit 鎺掑瓧锛岄€愬瓧绗︾殑鏍囩偣鍘嬬缉鍦ㄦ姮鎵嬪墠灏卞凡绠楀畬銆?
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
            items.append((pageTextCacheKey(for: page), pageTextSpec(for: page)))
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
            || text.contains("鐧诲綍") || text.contains("鐧婚檰")
            || text.contains("vip") || text.contains("鏉冮檺")
            || text.contains("璁㈤槄") || text.contains("璐拱")
    }

    private func chapterPlaceholderPage(_ page: ReaderPageBlock) -> some View {
        pageSurface(for: page) {
            VStack(spacing: 12) {
                if let failure = windowFailures[page.chapterIndex] {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.orange)
                    Text(page.placeholderDirection < 0 ? "涓婁竴绔犲姞杞藉け璐? : "绔犺妭鍔犺浇澶辫触")
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
                    Button("閲嶈瘯") {
                        retryChapterManually(page.chapterIndex)
                    }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
                    if let source = currentBookSource,
                       SourceLoginURLResolver.resolve(source: source) != nil,
                       chapterFailureSuggestsLogin(failure) {
                        Button("鐧诲綍涔︽簮") {
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
                            ? "姝ｅ湪鍔犺浇涓婁竴绔?
                            : (page.placeholderDirection > 0 ? "姝ｅ湪鍔犺浇涓嬩竴绔? : "姝ｅ湪鍔犺浇绔犺妭")
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
                    Button("閲嶆柊鍔犺浇") {
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

    /// 闃呰椤靛敮涓€鐢诲竷銆?
    ///
    /// 鍑犱綍鏉ユ簮鍙湁 `ReaderPageGeometry`锛氶〉鐪夊甫銆佹鏂囩煩褰€侀〉鑴氬甫鍚勮嚜鏈夌‘瀹氬潗鏍囷紝
    /// 涓嶅啀閫氳繃涓夊眰 padding / frame / safeArea 鍙犲姞鍘汇€岀寽銆嶃€傞〉闈㈠鍣ㄥ昂瀵镐細鍥炰紶缁?
    /// 鍒嗛〉寮曟搸锛圧eaderPageContainerMetricsKey锛夛紝鎵€浠ュ垎椤甸珮搴︿笌瀹為檯鍙敾楂樺害姘歌繙涓€鑷淬€?
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
                contentExtendsIntoChrome: contentExtendsIntoChrome,
                headerFontSize: CGFloat(headerFontSize), headerTopGap: CGFloat(headerTopGap)
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

                // One clock per page instead of one per chrome element: two
                // `TimelineView`s per page doubled the per-frame work on the
                // text surface and showed up as the stutter while flipping.
                TimelineView(.everyMinute) { context in
                    ZStack(alignment: .topLeading) {
                        if geometry.showsHeader {
                            pagedPageHeader(page: page, geometry: geometry, now: context.date)
                        }
                        pagedPageFooter(page: page, geometry: geometry, now: context.date)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .preference(key: ReaderPageContainerMetricsKey.self, value: metrics)
        }
        .background(pageBackground.ignoresSafeArea())
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var pageBackground: some View {
        if background == .custom, let image = ReaderCustomWallpaperStore.cachedWallpaper {
            ZStack {
                ReaderWallpaperView(
                    image: image,
                    fillMode: ReaderWallpaperFillMode(rawValue: customWallpaperFillModeRaw) ?? .fill,
                    adjustment: ReaderCustomWallpaperStore.adjustment
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if customBackgroundIsDark {
                    Color.black.opacity(readerIsNight ? 0.60 : 0.35)
                } else {
                    Color.white.opacity(readerIsNight ? 0.15 : 0.20)
                }
            }
            .clipped()
        } else if background.hasTexture {
            ReaderPaperTextureView(background: background, night: readerIsNight)
        } else {
            readerThemeBackground
        }
    }

    /// 椤电湁锛?2pt 绔犺妭鍚?+锛堝彲閫夛級鏃堕棿 / 鐢甸噺銆備綅缃敱 geometry 鍐冲畾锛屾案杩滃湪瀹夊叏鍖哄唴銆?
    private func pagedPageHeader(page: ReaderPageBlock, geometry: ReaderPageGeometry, now: Date) -> some View {
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
                    Text(now, format: .dateTime.hour().minute())
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

    /// 椤佃剼锛氬彸涓嬭 `褰撳墠椤?鏈珷鎬婚〉`锛堢珵鍝佹牸寮?3/35锛夛紝鏃堕棿涓庣數閲忔寜寮€鍏虫帓鍒椼€?
    private func pagedPageFooter(page: ReaderPageBlock, geometry: ReaderPageGeometry, now: Date) -> some View {
        HStack(spacing: 10) {
            if statusPosition == "bottom" || statusPosition == "both" {
                if footerShowTime {
                    Text(now, format: .dateTime.hour().minute())
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

    /// 椤佃剼瀹為檯鍗犵敤楂樺害锛?0pt 鏉?+ 6pt 闂磋窛锛夛紝鍒嗛〉妯″紡鍥哄畾棰勭暀 26pt銆?
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

    private var readerStatusBarBackdrop: some View {
        readerThemeBackground
            .frame(height: readerTopSafeInset)
            .frame(maxHeight: .infinity, alignment: .top)
            .opacity(showOverlay || showSystemStatusBar ? 1 : 0)
            .animation(nil, value: showOverlay)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var readerHeader: some View {
        TimelineView(.everyMinute) { context in
            VStack(spacing: 0) {
                ReaderScrollChapterHeader(
                    title: chapterHeadingStyle == .hidden ? nil : currentDisplayChapterTitle,
                    geometry: scrollChromeGeometry,
                    horizontalPadding: CGFloat(pagePadding),
                    foreground: readerThemeTextColor,
                    paper: readerThemeBackground,
                    textOpacity: ReaderHeadingPreferences.opacity(headerOpacity),
                    showsLabels: !showOverlay,
                    wallpaper: background == .custom || background.hasTexture
                        ? AnyView(readerBackdrop.frame(height: effectiveViewportSize.height)
                            .frame(height: scrollChromeGeometry.protectedHeight, alignment: .top).clipped()) : nil
                ) {
                    // Keep explicit top-clock/battery preferences; the default
                    // bottom-status layout leaves only the chapter name here.
                    if showsTopStatus {
                        HStack(spacing: 8) {
                            if footerShowTime {
                                Text(context.date, format: .dateTime.hour().minute())
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
                // 闃呰椤靛拷鐣ヤ簡瀹夊叏鍖猴紝椤佃剼瑕佽嚜宸辫寮€ home indicator銆?
                // 0.35脳搴曢儴瀹夊叏鍖猴紙34pt 鈫?12pt锛変笌绔炲搧椤电爜绂诲簳 12.3pt 瀵归綈锛?
                // 鏂囧瓧钀藉湪鎵嬪娍鏉′笂鏂癸紝浣嗕笉浼氬儚鏃х増 0.25脳 閭ｆ牱鍘嬪埌鎸囩ず鏉′笂銆?
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
                    Button("閲嶈瘯") {
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
            .background(readerThemeBackground.opacity(0.98), in: Capsule())
            .overlay(Capsule().stroke(readerThemeTextColor.opacity(0.12), lineWidth: 0.5))
            .padding(.horizontal, 24)
            .padding(.bottom, max(CGFloat(footerHeight), 24) + 8)
        }
        .allowsHitTesting(status.isFailure)
        .animation(.easeInOut(duration: 0.2), value: status)
    }

    /// 鍏ㄥ睆闃呰蹇界暐浜嗗畨鍏ㄥ尯锛岄〉鐪夐〉鑴氬繀椤昏嚜宸辫寮€鍒樻捣涓?home indicator銆?
    /// 鎵€鏈夌獥鍙ｅ彇鏈€澶у畨鍏ㄥ尯锛歬ey window 鍙兘鏄鍣ㄧ獥鍙ｏ紙瀹夊叏鍖轰负 0锛夛紝
    /// 鍙彇 key window 浼氳椤电湁鐩存帴鍘嬪埌鐘舵€佹爮涓嬮潰銆?
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

    private var allowsNativeBookReturn: Bool {
        if #available(iOS 18.0, *) {
            return readerUsesBookReturn && ReaderSystemReturnPolicy.isEnabled(
                isScroll: readerMode == .scroll, menuVisible: showOverlay,
                blocked: showSettings || showChapterList || temporaryCoverPresented,
                selectionEnabled: textSelectionEnabled)
        }
        return false
    }

    private var readerOverlay: some View {
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
                        rebuildPagedBlocksCache()
                        HapticFeedback.light()
                    }
                    .accessibilityLabel("鍒囨崲澹佺焊鏂囧瓧榛戠櫧鑹?)
                }

                chromeIconButton(systemName: isCurrentChapterBookmarked ? "bookmark.fill" : "bookmark") {
                    toggleCurrentBookmark(openList: false)
                }

                ReaderNativeMenuButton(
                    menuIdentity: readerNativeMenuIdentity,
                    makeMenu: { readerNativeMenu },
                    foregroundColor: background.uiTextColor(isNight: readerIsNight),
                    backgroundColor: readerUsesTranslucentChrome ? .clear : background.uiColor(isNight: readerIsNight),
                    presentation: nativeMoreMenuPresentation
                )
                .frame(width: 44, height: 44)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .modifier(ReaderChromeSurface(paper: readerThemeBackground, ink: readerThemeTextColor, protectsReadingControls: true))
            .padding(.horizontal, 16)
            .padding(.top, readerTopSafeInset + 4)

            Spacer()

            VStack(spacing: 12) {
                // 婊氬姩妯″紡鏄剧ず钀界偣绔犺妭锛屽垎椤垫ā寮忔樉绀烘湰绔犻〉鐮侊紱涓よ€呰涔変笉鍚岋紝
                // 鍒嗛〉鏃舵嫋绔犺妭婊戞潯浼氳鏁寸珷閲嶆帓锛屾鏄€岀炕椤靛崱浣忋€嶇殑鏉ユ簮涔嬩竴銆?
                Text(readerMode == .scroll ? chapterSliderLabel : pageSliderLabel)
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(readerThemeTextColor.opacity(0.55))
                    .frame(height: 13)

                HStack(spacing: 10) {
                    navChapterButton(icon: "chevron.left", title: "涓婁竴绔?) {
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
                            .tint(AppTheme.accent)
                            .padding(.horizontal, 16)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(readerThemeBackground.opacity(0.98), in: Capsule())
                            .clipShape(Capsule())
                            .disabled(totalChapterCount <= 1)
                            .accessibilityLabel("绔犺妭杩涘害")
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
                            .tint(AppTheme.accent)
                            .padding(.horizontal, 16)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(readerThemeBackground.opacity(0.98), in: Capsule())
                            .clipShape(Capsule())
                            .disabled(currentChapterPageTotalForSlider <= 1)
                            .accessibilityLabel("鏈珷椤电爜")
                    }

                    navChapterButton(icon: "chevron.right", title: "涓嬩竴绔?) {
                        selectRelativeChapter(offset: 1)
                    }
                    .disabled(!canSelectRelativeChapter(offset: 1))
                }

                // TTS and auto-scroll moved into the top-right overflow menu.
                // Keeping five equal-width buttons made the bottom panel the
                // busiest part of the reader; the two primary actions stay
                // here and every secondary action is one tap away.
                HStack(spacing: 8) {
                    toolButton(icon: "list.bullet", title: "鐩綍") {
                        tocTab = 0
                        tocScrollIntent = .currentChapter
                        showChapterList = true
                        closeSettingsPanel()
                    }

                    // 鎹㈡簮鍏ュ彛浠庡彸涓婅婧㈠嚭鑿滃崟鎻愬埌甯搁┗搴曟爮锛氭崲婧愭槸杩芥洿鏃?
                    // 鏈€楂橀鐨勬搷浣滀箣涓€锛岃棌鍦ㄤ簩绾ц彍鍗曢噷姣忔瑕佸涓ゆ鐐瑰嚮銆?
                    toolButton(icon: "arrow.triangle.2.circlepath", title: "鎹㈡簮") {
                        closeSettingsPanel()
                        onRequestSourceSwitch?()
                    }
                    .disabled(onRequestSourceSwitch == nil)
                    .opacity(onRequestSourceSwitch == nil ? 0.35 : 1)

                    // 绗簲涓叆鍙ｇ粰鏈楄/鏆傚仠锛歍TS 鍘熸潵鍙湪鍙充笂瑙掓孩鍑鸿彍鍗曢噷锛?
                    // 杩芥洿鏃朵竴杈瑰惉涓€杈圭炕椤垫槸楂橀鎿嶄綔锛屽簳鏍忎竴閿彲杈俱€?
                    toolButton(
                        icon: speechController.isSpeaking && !speechController.isPaused ? "pause.fill" : "speaker.wave.2",
                        title: speechController.isSpeaking && !speechController.isPaused ? "鏆傚仠" : "鏈楄"
                    ) {
                        closeSettingsPanel()
                        toggleSpeech()
                    }

                    toolButton(icon: "gearshape", title: "璁剧疆") {
                        toggleSettingsPanel()
                    }
                    .accessibilityIdentifier("reader.openSettings")
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
            .padding(12)
            .modifier(ReaderChromeSurface(paper: readerThemeBackground, ink: readerThemeTextColor))
            .shadow(
                color: Color.black.opacity(background.isDark ? 0.30 : 0.10),
                radius: 18,
                x: 0,
                y: 8
            )
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
            .background(readerThemeTextColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                .background(Circle().fill(readerUsesTranslucentChrome ? Color.clear : readerThemeBackground))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private var readerUsesTranslucentChrome: Bool {
        ReaderChromeSurface.permitsTranslucency(reduceTransparency: UIAccessibility.isReduceTransparencyEnabled,
            increasedContrast: UIAccessibility.isDarkerSystemColorsEnabled, menuStyle: menuSurfaceStyle,
            usesWallpaper: menuUsesWallpaper)
    }

    private var settingsHint: String {
        switch settingsTab {
        case 0: return readerModeHint
        case 1: return "鍙充晶鍙洿鎺ヨ緭鍏ユ暟鍊硷紝绮捐皟瀛楀彿銆侀棿璺濆拰杈硅窛銆?
        default: return "杩欓噷淇濈暀涓嶉噸澶嶇殑闃呰杈呭姪锛氳嚜鍔ㄦ粴鍔ㄩ棿闅斻€佹湕璇婚€熷害銆佺潯鐪犲畾鏃朵笌鐐瑰嚮鍖哄煙銆?
        }
    }

    private var readerModeHint: String {
        switch readerMode {
        case .scroll:
            return "涓婁笅杩炵画婊戝姩锛岀珷鑺傛湯灏捐嚜鍔ㄨ鎺ヤ笅涓€绔狅紱椤靛唴娌℃湁妯悜缈婚〉鎵嬪娍銆?
        case .pageTurn:
            return "宸﹀彸骞崇Щ缈婚〉锛屾瘡椤靛浐瀹氫笉婊氬姩锛岄€傚悎涔犳儻鏁撮〉闃呰銆?
        case .cover:
            return "鎷栧姩鏃朵笅涓€椤典粠鍙充晶瑕嗙洊褰撳墠椤碉紝鏉炬墜鎸変綅绉诲拰閫熷害鍐冲畾鏄惁缈婚〉銆?
        case .pageCurl:
            return "绯荤粺鍘熺敓绾稿紶鍗锋洸鍔ㄧ敾锛屽彲鎷栧埌涓€鍗婂啀鏉炬墜鍥炲脊鎴栧畬鎴愩€?
        }
    }

    @ViewBuilder private var settingsPanel: some View {
        if usesAtelier { atelierPanel }
        else {
            ReaderClassicSettingsPanel(context: ReaderWorkbenchContext(bookTitle: content.title, background: background, bottomInset: readerFooterSafeInset,
                isNightOverride: readerIsNight),
                selection: $settingsTab, page: { AnyView(settingsPage(for: $0)) }, close: closeSettingsPanel)
        }
    }

    private var atelierPanel: some View {
        ReaderSettingsWorkbench(context: ReaderWorkbenchContext(
            bookTitle: appState.bookshelfStore.book(id: bookID)?.title ?? content.title,
            background: background, bottomInset: readerFooterSafeInset,
            menuOpacity: menuPaperOpacity, usesWallpaper: menuUsesWallpaper, isNightOverride: readerIsNight), preview: {
                let paragraphs = windowSections.first(where: { $0.chapterIndex == currentDisplayChapterIndex })?.paragraphs ?? content.paragraphs
                let excerpt = paragraphs.first(where: { ReaderImageSizingPolicy.imageURL(in: $0) == nil }) ?? ""
                return AnyView(ReaderAtelierPreview(title: currentDisplayChapterTitle, excerpt: String(excerpt.prefix(512)), paperRevision: backgroundWallpaperRevision))
            }, page: { workbenchPage($0) }, actions: ReaderWorkbenchActions(close: closeSettingsPanel, routeChanged: {
                settingsTab = $0 == .assistance ? 2 : $0 == .typography ? 1 : 0
            }))
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
            action("鍒锋柊鏈珷", "arrow.clockwise", enabled: onRefreshChapter != nil) { onRefreshChapter?() },
            action("缂撳瓨鍓嶅悗绔犺妭", "square.and.arrow.down", enabled: onCacheNextChapters != nil) { onCacheNextChapters?(windowCurrentChapterIndex) },
            action("缃戦〉鎵撳紑鏈珷", "safari", enabled: currentChapterWebURL != nil, leavesReader: true) { showChapterWebPage = true }
        ]
        if canShowPayAction {
            chapterActions.append(action("璐拱鏈珷", "cart", enabled: !isPerformingPayAction, leavesReader: true) { showPayActionConfirmation = true })
        }
        let playback: [UIMenuElement] = [
            action(autoScrollEnabled ? "鏆傚仠鑷姩缈婚〉" : "寮€濮嬭嚜鍔ㄧ炕椤?, autoScrollEnabled ? "pause.fill" : "play.fill") { toggleAutoScroll() }
        ]
        let bookActions: [UIMenuElement] = [
            action("涔︾睄璇︽儏", "info.circle", leavesReader: true) {
                if appState.bookshelfStore.book(id: bookID)?.sourceURL.hasPrefix("local://") == true {
                    showBookDetailSheet = true
                } else if let onRequestBookDetail { onRequestBookDetail() } else { showBookDetailSheet = true }
            },
            action("鍐呭杩囨护", "line.3.horizontal.decrease.circle", leavesReader: true) { showContentFilter = true },
            action("鐧诲綍涔︽簮", "person.badge.key", enabled: currentBookSource != nil, leavesReader: true) { readerLoginSource = currentBookSource }
        ]
        return UIMenu(children: [
            UIMenu(options: .displayInline, children: chapterActions),
            UIMenu(options: .displayInline, children: playback),
            UIMenu(options: .displayInline, children: bookActions)
        ])
    }

    private func closeSettingsPanel() {
        guard showSettings else { return }
        withAnimation(motion.animation(.expansion)) {
            chromeState.closeSettings()
        }
    }

    private func settingsTabButton(title: String, tag: Int) -> some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                settingsTab = tag
            }
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
            readerBrightnessSection
        }
    }

    private var readerModeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("缈婚〉妯″紡")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(readerThemeTextColor.opacity(0.62))
            Text(readerModeHint)
                .font(.caption2)
                .foregroundStyle(readerThemeTextColor.opacity(0.62))
            BrandSegmentedControl("缈婚〉妯″紡", selection: $readerModeRawValue, options:
                            ReaderMode.allCases.map { ($0.rawValue, $0.title) })
            .padding(.bottom, 8)
        }
    }

    private var perBookOverrideToggle: some View {
        Toggle("浠呭鏈功鐢熸晥鐙珛閰嶇疆", isOn: Binding(
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
            Text("闃呰鑳屾櫙 路 绾哥汗涓庢彃鐢?)
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
                    Text(ReaderCustomWallpaperStore.hasCustomWallpaper ? "鏇存崲鑷畾涔夊绾? : "浠庣浉鍐岄€夋嫨澹佺焊")
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

            if isPreparingWallpaper { Text("姝ｅ湪鍑嗗澹佺焊棰勮鈥?).font(.caption) }
            if let wallpaperMessage { Text(wallpaperMessage).font(.caption).foregroundStyle(.secondary) }
            if ReaderCustomWallpaperStore.hasCustomWallpaper {
                Button("缂栬緫宸蹭繚瀛樺绾?) {
                    Task { @MainActor in
                        await ReaderCustomWallpaperStore.warmWallpaper()
                        guard let image = ReaderCustomWallpaperStore.cachedWallpaper else {
                            wallpaperMessage = ReaderCustomWallpaperStore.lastError ?? "澹佺焊鏃犳硶璇诲彇锛岃閲嶆柊閫夋嫨鍥剧墖銆?; return
                        }
                        var adjustment = ReaderCustomWallpaperStore.adjustment
                        adjustment.fillMode = ReaderWallpaperFillMode(rawValue: customWallpaperFillModeRaw) ?? .fill
                        adjustment.usesLightText = customBackgroundIsDark
                        wallpaperDraft = ReaderWallpaperDraft(image: image, adjustment: adjustment, viewportSize: effectiveViewportSize)
                    }
                }.buttonStyle(.bordered)
            }

            BrandSegmentedControl("澹佺焊鍩哄簳涓庢枃瀛楅鏍?, selection: $customBackgroundIsDark, options:
                            [(false, "娴呰壊澹佺焊 (娣辫壊瀛?"), (true, "娣辫壊澹佺焊 (娴呰壊瀛?")])
            .padding(.top, 2)
            .onChange(of: customBackgroundIsDark) { newValue in
                UserDefaults.standard.set(true, forKey: "reader.customBackgroundIsDarkManual")
                UserDefaults.standard.set(newValue, forKey: "reader.customBackgroundIsDark")
                backgroundWallpaperRevision = UUID()
                rebuildPagedBlocksCache()
            }

            BrandSegmentedControl("澹佺焊濉厖鏂瑰紡", selection: $customWallpaperFillModeRaw, options:
                            ReaderWallpaperFillMode.allCases.map { ($0.rawValue, $0.title) })
            .padding(.top, 2)

            if ReaderCustomWallpaperStore.hasCustomWallpaper {
                Button(role: .destructive) {
                    confirmClearWallpaper = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text("鍒犻櫎鑷畾涔夊绾革紝鎭㈠绱犵櫧鑳屾櫙")
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                }
                .padding(.top, 2)
                .confirmationDialog("鍒犻櫎鑷畾涔夊绾革紵瑁佸垏涓庡師鍥惧皢涓€骞剁Щ闄ゃ€?, isPresented: $confirmClearWallpaper, titleVisibility: .visible) {
                    Button("鍒犻櫎鑷畾涔夊绾?, role: .destructive) {
                        Task { @MainActor in
                            do {
                                try await ReaderCustomWallpaperStore.clearEditedWallpaper()
                                backgroundRawValue = ReaderBackground.white.rawValue
                                backgroundWallpaperRevision = UUID(); rebuildPagedBlocksCache()
                            } catch { wallpaperMessage = "鍒犻櫎鏈畬鎴愶紝璇烽噸璇曘€? + error.localizedDescription }
                        }
                    }
                    Button("淇濈暀澹佺焊", role: .cancel) {}
                }
            }

            Text(ReaderCustomWallpaperStore.hasCustomWallpaper
                 ? "澹佺焊宸茬敓鏁堬紝鏀寔鑷富鍒囨崲娴呰壊/娣辫壊鏂囧瓧鏍峰紡浠ヤ繚璇佹渶浣冲姣斿害銆?
                 : "鍙粠鐩稿唽閫夋嫨澹佺焊锛屾敮鎸佽嚜鐢辨惌閰嶆祬鑹叉垨娣辫壊鏂囧瓧銆?)
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
                Text("闃呰浜害")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(readerThemeTextColor.opacity(0.62))
                Spacer()
                Text(readerBrightness < 0 ? "鑷姩浜害" : "\(Int(readerBrightness * 100))%")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.accent)
                Button("璺熼殢绯荤粺") {
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
            Text("鍙奖鍝嶉槄璇婚〉锛岄€€鍑洪槄璇诲櫒浼氭仮澶嶇郴缁熶寒搴︺€?)
                .font(.caption2)
                .foregroundStyle(readerThemeTextColor.opacity(0.42))
        }
    }

    private var appearancePreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("闃呰棰勮")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(readerThemeTextColor.opacity(0.64))
                Spacer()
                Text("\(fontFamily.title) 路 \(Int(fontSize))pt 路 缂╄繘\(Int(paragraphIndent))pt")
                    .font(.caption2)
                    .foregroundStyle(readerThemeTextColor.opacity(0.55))
            }

            Text("銆€銆€澶滆壊娌変笅鏉ヤ互鍚庯紝鏂囧瓧搴旇瀹夐潤銆佹竻妤氥€佽€愮湅銆傝皟鏁村瑙備笌鎺掔増鏃讹紝杩欓噷浼氱珛鍒昏窡闅忓瓧浣撱€佸瓧鍙枫€佽璺濄€佹棣栫缉杩涘拰鑳屾櫙鍙樺寲銆?)
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
                .accessibilityLabel("鍏抽棴璇煶閿欒鎻愮ず")
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
                    Text("瀛椾綋")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(readerThemeTextColor.opacity(0.62))
                    Spacer()
                    Button {
                        showFontManagementSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Text("瀛椾綋绠＄悊 / 瀵煎叆")
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
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Text("馃挕 鎺掔増璇存槑锛氭瘡椤瑰潎鏍囨槑鍏蜂綋浣滅敤涓庢帹鑽愬€笺€傚彸渚у彲鐐规暟瀛楃洿鎺ヨ緭鍏ワ紝婊戝潡鐢ㄤ簬蹇€熸粦鍔ㄧ矖璋冦€傚凡閲囩敤涓绘祦灏忚鏍囧噯鎺掔増瑙勮寖銆?)
                .font(.caption)
                .foregroundStyle(readerThemeTextColor.opacity(0.62))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(readerThemeTextColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            // 1. 娈佃惤宸紙娈甸棿璺濓級- 鏀惧湪鏈€鍓嶉潰涔嬩竴锛岀敤鎴峰弽棣堟渶楂橀鏌ユ壘椤?
            readerValueSlider("娈佃惤宸紙娈甸棿璺濓級", value: $paragraphSpacing, range: 0...28, step: 1, unit: "pt", help: "璋冩暣涓婁笅涓ゆ鏂囧瓧涔嬮棿鐨勫瀭鐩寸暀鐧姐€傛闂磋窛搴斿ぇ浜庤璺濓紝姝ｆ枃鎵嶄笉浼氱硦鎴愪竴鐗囷紙鎺ㄨ崘 10~14pt锛?)

            // 2. 姝ｆ枃瀛楀彿
            readerValueSlider("姝ｆ枃瀛楀彿", value: $fontSize, range: 12...34, step: 1, unit: "pt", help: "鏁翠綋鏀惧ぇ鎴栫缉灏忓皬璇存鏂囨枃瀛楀ぇ灏忥紙涓绘祦闃呰鎺ㄨ崘 18~20pt锛?)

            // 3. 琛岃窛锛堣楂橀棿璺濓級
            readerValueSlider("琛岃窛", value: $lineSpacing, range: 0...18, step: 1, unit: "pt", help: "琛岄珮闂磋窛锛氬悓涓€娈佃惤鍐呬笂涓嬫瘡涓€琛屾枃瀛椾箣闂寸殑鍨傜洿闂撮殭涓庡懠鍚告劅锛堟帹鑽?8~10pt锛?)

            // 4. 娈甸缂╄繘
            readerValueSlider("娈甸缂╄繘", value: $paragraphIndent, range: 0...50, step: 2, unit: "pt", help: "姣忎釜娈佃惤绗竴琛屽紑澶寸殑缂╄繘绌烘牸銆?8pt 鍒氬ソ涓烘爣鍑嗙┖涓や釜姹夊瓧")

            // 5. 瀛楅棿璺濓紙瀛楄窛锛?
            readerValueSlider("瀛楅棿璺濓紙瀛楄窛锛?, value: $letterSpacing, range: 0...4, step: 0.2, unit: "pt", help: "鍚屼竴琛屼腑姣忎釜姹夊瓧宸﹀彸涔嬮棿鐨勭揣鍑戝害锛堟帹鑽?0~0.5pt锛?)

            // 6. 灞忓箷杈硅窛锛堝乏鍙崇暀鐧斤級
            readerValueSlider("灞忓箷杈硅窛锛堝乏鍙崇暀鐧斤級", value: $pagePadding, range: 10...40, step: 1, unit: "pt", help: "姝ｆ枃鏂囧瓧璺濈鎵嬫満灞忓箷宸﹀彸涓や晶杈圭紭鐨勮窛绂伙紝闃叉鏂囧瓧璐磋竟锛堟帹鑽?18~22pt锛?)

            if includesLegacySections { legacyLayoutHeadingControls }

            Button {
                applyReaderTypographyPreset(includesLegacySections: includesLegacySections)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "wand.and.stars")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("搴旂敤绾搁棿鎺ㄨ崘鎺掔増").font(.subheadline.weight(.semibold))
                        Text("璋冩暣姝ｆ枃鐨勫瓧鍙枫€佽璺濄€佹璺濄€佽竟璺濆拰棣栬缂╄繘銆?)
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
        // 7. 绔犺妭鏍囬
        VStack(alignment: .leading, spacing: 8) {
            Text("绔犺妭鏍囬浣嶇疆")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(readerThemeTextColor.opacity(0.62))
            BrandSegmentedControl("绔犺妭鏍囬浣嶇疆", selection: $chapterHeadingStyleRaw, options:
                            ReaderPageChromeLayout.allCases.map { ($0.rawValue, $0.title) })
            Text(chapterHeadingStyle.help)
                .font(.caption2)
                .foregroundStyle(readerThemeTextColor.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
        }

        VStack(alignment: .leading, spacing: 10) {
            Text("绔犺妭鍚?路 鐙珛鎺掔増").font(.headline)
            Toggle("绔犺妭鍚嶅姞绮?, isOn: $chapterTitleBold)
            Picker("绔犺妭鍚嶅瓧浣?, selection: $chapterTitleFamilyRaw) {
                Text("璺熼殢姝ｆ枃").tag("")
                ForEach(ReaderFontFamily.allCases) { family in Text(family.title).tag(family.rawValue) }
            }
            readerValueSlider("绔犺妭鍚嶅瓧鍙?, value: Binding(get: { resolvedTitleSize }, set: { chapterTitleSize = $0 }), range: 14...44, step: 1, unit: "pt", help: "鍙敼鍙樼珷鑺傚悕锛屼笉鏀瑰彉姝ｆ枃瀛楀彿锛涙粴鍔ㄤ笌鍒嗛〉妯″紡鍏辩敤銆?)
            Button("绔犺妭鍚嶅瓧鍙疯窡闅忔鏂?) { chapterTitleSize = 0 }
        }

        VStack(alignment: .leading, spacing: 10) {
            Text("椤电湁 路 鐙珛鎺掔増").font(.headline)
            readerValueSlider("椤电湁瀛楀彿", value: $headerFontSize, range: 9...18, step: 1, unit: "pt", help: "澧炲ぇ瀛楀彿浼氬悓姝ラ鐣欓〉鐪夐珮搴︼紝涓嶈鐩栨鏂囥€?)
            readerValueSlider("椤电湁椤堕儴闂磋窛", value: $headerTopGap, range: 0...24, step: 1, unit: "pt", help: "浠庡畨鍏ㄥ尯涓嬫部寮€濮嬭绠楋紝閬垮厤鎸′綇鐏靛姩宀涖€?)
            readerValueSlider("椤电湁鏂囧瓧娴撳害", value: $headerOpacity, range: 0.35...1, step: 0.05, unit: "", help: "鐙珛浜庢鏂囬鑹诧紱鑳屾櫙鍥句粛杩炵画瑕嗙洊椤堕儴銆?)
            Toggle("绯荤粺鐘舵€佹爮鍙鏃朵粛閲嶅椤堕儴鏃堕棿鐢甸噺", isOn: $allowsDuplicateTopStatus)
        }

        readerValueSlider("绔犺妭鏍囬闂磋窛", value: $titleSpacing, range: 0...36, step: 2, unit: "pt", help: "浠呫€屾鏂囧ぇ鏍囬銆嶆ā寮忕敓鏁堬細澶х珷鑺傛爣棰樹笌姝ｆ枃绗竴琛屼箣闂寸殑鍨傜洿鐣欑櫧锛堟帹鑽?8~16pt锛夈€傞〉鐪夋ā寮忎笉鍗犵敤姝ｆ枃楂樺害銆?)

        Toggle("鍐呭寤朵几鑷抽〉鐪夐〉鑴氬尯鍩?, isOn: $contentExtendsIntoChrome)
            .font(.subheadline.weight(.semibold))
    }

    @ViewBuilder private var legacyLayoutStatusControls: some View {
        // 8. 搴曢儴瀹夊叏鐣欑櫧
        readerValueSlider("搴曢儴瀹夊叏鐣欑櫧", value: $footerHeight, range: 40...180, step: 8, unit: "pt", help: "灞忓箷鏈€搴曢儴鍚戜笂棰勭暀鐨勫畨鍏ㄧ┖闅欙紝闃叉鎵嬪娍閬尅鏈€鍚庝竴琛屾鏂囷紙鎺ㄨ崘 80~100pt锛?)

        // 9. 椤佃剼鍐呭寮€鍏炽€傚鐓у悓绫婚槄璇诲櫒锛堥鑹查椇闃佺殑 tr_showTime / tr_showBatView /
        // tr_showBatLabel 灏辨槸涓変釜鐙珛寮€鍏筹級锛屾妸銆屾椂闂?/ 鐢甸噺鍥炬爣 / 鐢甸噺鐧惧垎姣斻€嶆媶寮€锛?
        // 鍏ㄥ睆鏃朵笉鎯崇湅灏变笉鏄剧ず锛屼篃灏变笉瀛樺湪銆屼綅缃鎬€嶈繖浠朵簨銆?
        VStack(alignment: .leading, spacing: 10) {
            Text("椤电湁涓庨〉鑴氱姸鎬佹爮")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(readerThemeTextColor.opacity(0.62))

            HStack {
                Text("鐘舵€佹爮浣嶇疆")
                Spacer()
                BrandSegmentedControl("浣嶇疆", selection: $statusPosition, options:
                            [("bottom", "浠呴〉鑴?), ("top", "浠呴〉鐪?), ("both", "椤电湁+椤佃剼")])
                .frame(width: 200)
            }

            Toggle("濮嬬粓淇濈暀绯荤粺鍘熺敓鐘舵€佹爮", isOn: $showSystemStatusBar)
            Toggle("鏄剧ず鏃堕棿", isOn: $footerShowTime)
            Toggle("鏄剧ず鐢甸噺鍥炬爣", isOn: $footerShowBatteryIcon)
            Toggle("鏄剧ず鐢甸噺鐧惧垎姣?, isOn: $footerShowBatteryPercent)
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
        paragraphIndent = 40
        paragraphSpacing = ReaderTypographyDefaults.paragraphSpacing
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
            Text("楂樼骇閲屽彧鏀鹃槄璇昏緟鍔╋紝涓嶅啀閲嶅鍓嶉潰鐨勭炕椤靛拰瀛楀彿鍏ュ彛銆傛湕璇婚€熷害鍙璇€燂紝鑷姩婊氬姩鍦ㄤ富闃呰鑿滃崟銆?)
                .font(.caption)
                .foregroundStyle(readerThemeTextColor.opacity(0.62))

            readerValueSlider(
                "鑷姩婊氬姩闂撮殧",
                value: $autoScrollDelay,
                range: ReaderAutomationPolicy.minDelay...ReaderAutomationPolicy.maxDelay,
                step: 0.25,
                unit: "绉?,
                help: "鑷姩婊氬姩闂撮殧鏈€闀?60 绉掞紝鏁板€艰秺澶ф粴鍔ㄨ秺鎱紱杩愯涓慨鏀圭珛鍗抽噸鏂拌鏃躲€傛湕璇讳笌鑷姩婊氬姩浜掓枼銆?
            )

            readerValueSlider("鏈楄閫熷害", value: $ttsRate, range: 0.35...0.65, step: 0.01, unit: "鍊嶉€?, help: "璋冩暣璇煶鏈楄璇€燂紙0.35x ~ 0.65x锛夛紝浠庡綋鍓嶅彲瑙佹钀藉紑濮嬫湕璇伙紝涓嶄細璺冲洖绔犺妭寮€澶?)

            Text("鐫＄湢瀹氭椂")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(readerThemeTextColor.opacity(0.62))
            BrandSegmentedControl("鐫＄湢瀹氭椂", selection: $sleepTimerMinutes, options:
                            [(0, "鍏抽棴"), (-1, "鎾畬褰撶珷"), (15, "15 鍒嗛挓"), (30, "30 鍒嗛挓"), (60, "60 鍒嗛挓")])

            Toggle("闃呰鏃朵繚鎸佸睆骞曞父浜?, isOn: $keepScreenAwake)
                .font(.subheadline.weight(.semibold))

            Toggle("鍏佽姝ｆ枃鏂囧瓧閫夋嫨", isOn: $textSelectionEnabled)
                .font(.subheadline.weight(.semibold))

            Toggle("绻佷綋涓枃鏄剧ず锛堢畝杞箒锛?, isOn: $traditionalChineseEnabled)
                .font(.subheadline.weight(.semibold))

            Toggle("浠跨敓闃呰锛圔ionic Reading 璇嶉鍔犵矖锛?, isOn: $bionicReadingEnabled)
                .font(.subheadline.weight(.semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text("鎻掑浘鎺掔増鏍峰紡")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(readerThemeTextColor.opacity(0.62))
                BrandSegmentedControl("鎻掑浘鎺掔増鏍峰紡", selection: $globalImageStyleRaw, options:
                            ReaderImageStyle.allCases.map { ($0.rawValue, $0.title) })
            }

            settingStepper(title: "棰勫姞杞界珷鑺?, value: ReaderPreloadPolicy.title(for: preloadChapterCount)) {
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
        ReaderSettingsContent {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(readerThemeTextColor)
                        // 鏍囬鐙崰宸︿晶鍓╀綑瀹藉害锛屽彸渚у浐瀹氱粰绮剧‘杈撳叆妗嗭紱
                        // 銆岃璺濓紙琛岄珮闂磋窛锛夈€嶄笉鍐嶈鏁板€艰兌鍥婃尋鎴愪袱琛屻€?
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

                HStack(spacing: 8) {
                    Text("\(ReaderValueNormalizer.formatted(value.wrappedValue, step: step)) \(unit)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.accent)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(AppTheme.accent.opacity(0.12), in: Capsule())

                    Spacer(minLength: 0)

                    Text("鑼冨洿 \(ReaderValueNormalizer.formatted(range.lowerBound, step: step)) ~ \(ReaderValueNormalizer.formatted(range.upperBound, step: step))")
                        .font(.caption2)
                        .foregroundStyle(readerThemeTextColor.opacity(0.42))
                        .lineLimit(1)
                }

                // 閱掔洰鐨勫姛鑳借鏄庡崱鐗囷紝璁╃敤鎴锋竻妤氱煡閬撴瘡涓€椤硅皟鏁寸殑鏄粈涔堬紝鍛婂埆鐩叉祴
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.accent.opacity(0.85))
                        .padding(.top, 1)

                    Text(help)
                        .font(.caption)
                        .foregroundStyle(readerThemeTextColor.opacity(0.62))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(readerThemeTextColor.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                HStack(spacing: 12) {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        value.wrappedValue = max(range.lowerBound, (value.wrappedValue - step))
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(value.wrappedValue <= range.lowerBound ? readerThemeTextColor.opacity(0.25) : AppTheme.accent)
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
                            .foregroundStyle(value.wrappedValue >= range.upperBound ? readerThemeTextColor.opacity(0.25) : AppTheme.accent)
                    }
                    .disabled(value.wrappedValue >= range.upperBound)
                    .buttonStyle(.plain)
                }

            }
            .padding(12)
            .background(readerThemeTextColor.opacity(0.055), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(readerThemeTextColor.opacity(0.06), lineWidth: 0.8)
            }
            .padding(.vertical, 2)
        }
    }

    private var tapZoneSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("涔濆鏍肩偣鍑诲尯鍩?)
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
            Button("鎭㈠榛樿鐐瑰嚮鍖哄煙") {
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
                    } else {
                        bookmarkList(includeAddButton: true)
                    }
                }
            }
            // List 鑷甫 systemBackground锛屽彔鍦ㄤ富棰樿儗鏅笂灏辨槸銆岀珷鑺?(N)銆嶄笅闈㈤偅鏉＄櫧甯︺€?
            // 鎶婃粴鍔ㄥ唴瀹硅儗鏅涓洪€忔槑锛岃 readerBackdrop 閫忎笂鏉ワ紱琛岃儗鏅凡缁忔槸 clear銆?
            .scrollContentBackground(.hidden)
            .background(readerThemeBackground.ignoresSafeArea())
            .navigationTitle(tocTab == 0 ? "鐩綍" : "涔︾")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if tocTab == 0 {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(tocReversed ? "鍊掑簭" : "椤哄簭") {
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
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("瀹屾垚") {
                        showChapterList = false
                    }
                    .foregroundStyle(readerThemeTextColor)
                }
            }
            .toolbarBackground(readerThemeBackground, for: .navigationBar)
            .toolbarColorScheme(background.isDark ? .dark : .light, for: .navigationBar)
        }
        .readerSheetPresentation(color: readerThemeBackground)
        // 鐩綍鍥哄畾鍏ㄥ睆锛氬甫 .medium 鏃?SwiftUI 榛樿閫夋渶灏?detent锛屾瘡娆￠兘瑕佹墜鍔ㄤ笂鎷夈€?
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .tint(AppTheme.accent)
        .preferredColorScheme(background.isDark ? .dark : .light)
    }

    private var customTocSegmentedPicker: some View {
        HStack(spacing: 0) {
            tocTabButton(title: "鐩綍", tag: 0)
            tocTabButton(title: "涔︾", tag: 1)
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

                TextField("绛涢€夌珷鑺傚悕鎴栧簭鍙?, text: $tocQuery)
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

            // 娌℃湁 ScrollViewReader 鏃讹紝姣忔鎵撳紑鐩綍閮藉仠鍦ㄧ涓€琛岋細
            // 璇讳簡涓ょ櫨绔犲啀鐐圭洰褰曪紝杩樿鑷繁寰€涓嬬炕銆傝繖閲岀敤琛?identity
            // 鐩存帴瀹氫綅鍒板綋鍓嶉槄璇荤珷銆?
            ScrollViewReader { proxy in
            List {
                if chapters.isEmpty && navigationEntries.isEmpty {
                    Text("褰撳墠绔犺妭娌℃湁鍙垏鎹㈢洰褰?)
                        .foregroundStyle(readerThemeTextColor.opacity(0.6))
                        .listRowBackground(Color.clear)
                } else if visibleChapters.isEmpty && visibleNavigationEntries.isEmpty {
                    Text("娌℃湁鍖归厤绔犺妭")
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
                                    // same runloop was dropped 鈥?after which the reader
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
                            Text("绔犺妭 (\(visibleChapters.count))")
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
                            Text("椤甸潰鍐呯洰褰?)
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
                // 棣栧抚鐨勮杩樻病寤哄嚭鏉ワ紝鍚屼竴 runloop 閲?scrollTo 浼氳惤绌猴紝
                // 鎸埌涓嬩竴鎷嶅啀婊氬姩銆?
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

    /// 鎵撳紑鐩綍瀹氫綅褰撳墠绔狅紱鎵嬪姩鎺掑簭鎴栫瓫閫夊畾浣嶆柊鍒楄〃棣栬銆?
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
                    Text("绗?\(chapterIndex + 1) 绔? + (entry.paragraphIndex.map { " 路 绗?\($0 + 1) 娈? } ?? ""))
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
                    .navigationTitle("涔︾")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("瀹屾垚") {
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
        .presentationDetents([.large])
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
                        isCurrentChapterBookmarked ? "鍙栨秷褰撳墠娈佃惤涔︾" : "鍔犲叆褰撳墠娈佃惤涔︾",
                        systemImage: isCurrentChapterBookmarked ? "bookmark.slash" : "bookmark"
                    )
                    .foregroundStyle(AppTheme.accent)
                }
                .listRowBackground(Color.clear)
                .listRowSeparatorTint(readerThemeTextColor.opacity(0.15))
            }

            if bookmarks.isEmpty {
                Text("鏆傛棤涔︾")
                    .foregroundStyle(readerThemeTextColor.opacity(0.6))
                    .listRowBackground(Color.clear)
            } else {
                Section {
                    HStack {
                        Label("\(bookmarks.count) 涓功绛?, systemImage: "bookmark")
                        Spacer()
                        Text("鏈珷 \(currentChapterBookmarkCount)")
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
                                            Text("褰撳墠")
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
                                Label("鍗＄墖", systemImage: "quote.bubble.fill")
                            }
                            .tint(AppTheme.accent)
                        }
                        .swipeActions(edge: .trailing) {
                            Button("鍒犻櫎", role: .destructive) {
                                appState.bookshelfStore.removeBookmark(bookID: bookID, bookmarkID: bookmark.id)
                            }
                        }
                        .contextMenu {
                            Button {
                                quoteCardBookmark = bookmark
                            } label: {
                                Label("鐢熸垚閲戝彞鍗＄墖", systemImage: "quote.bubble")
                            }
                            Button("鍒犻櫎涔︾", role: .destructive) {
                                appState.bookshelfStore.removeBookmark(bookID: bookID, bookmarkID: bookmark.id)
                            }
                        }
                    }
                } header: {
                    Text("鎴戠殑涔︾")
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
            return "绗?\(bookmark.chapterIndex + 1) 绔?路 绗?\(paragraphIndex + 1) 娈?
        }
        return "绗?\(bookmark.chapterIndex + 1) 绔?
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
            positionPersistTask?.cancel()
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
            rebuildPagedBlocksCache(anchorOverride: ReaderChapterPosition(chapterIndex: index, paragraphIndex: paragraph))
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
            prefetchQueue.removeAll()
        } else {
            cancelPrefetch()
        }
        cancelPaginationWarmup()
        positionPersistTask?.cancel()
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
            // 鎷栧姩杩涘害鏉℃椂涓嶈兘椤烘墜鎶婃帶鍒堕潰鏉垮叧鎺夛紝鍚﹀垯婊戝埌涓€鍗婇潰鏉垮氨娑堝け浜嗐€?
            if !keepChrome { closeReaderChrome() }
            stopAutoScroll()
            stopSpeechPlayback()
            beginWindowJump(to: index, paragraphIndex: 0)
        case .outOfRange:
            return
        }
    }

    /// 褰撳墠椤靛湪鏈珷鍐呯殑 0-based 搴忓彿銆?
    private var currentChapterPageOrdinal: Int {
        guard pagedBlocks.indices.contains(pagedPageIndex) else { return 0 }
        return pagedBlocks[pagedPageIndex].pageOrdinal
    }

    /// 褰撳墠绔犳€婚〉鏁帮紝鐢ㄤ簬鍒嗛〉妯″紡婊戞潯涓婇檺銆?
    private var currentChapterPageTotalForSlider: Int {
        guard pagedBlocks.indices.contains(pagedPageIndex) else { return max(pagedBlocks.count, 1) }
        let block = pagedBlocks[pagedPageIndex]
        return max(chapterPageTotal(for: block.chapterIndex, fallback: block.pageOrdinal + 1), 1)
    }

    /// 鍒嗛〉妯″紡搴曟爮鏂囨锛氭湰绔犵鍑犻〉 / 鍏卞嚑椤点€?
    private var pageSliderLabel: String {
        let total = currentChapterPageTotalForSlider
        return "绗?\(min(currentChapterPageOrdinal + 1, total)) / \(total) 椤?
    }

    /// 鍒嗛〉妯″紡璺抽〉锛氬彧鍦ㄥ綋鍓嶇珷鑺傚唴绉诲姩锛屼笉瑙﹀彂绔犺妭閲嶆帓銆?
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

    /// 鎷栧姩杩涘害鏉℃椂鐨勮惤鐐规枃妗堬紱涓嶆嫋鍔ㄦ椂杩斿洖褰撳墠绔狅紙閰嶅悎 opacity 闅愯棌锛夈€?
    private var chapterSliderLabel: String {
        let total = max(displayTotalChapters ?? chapters.count, 1)
        let raw = Int((chapterSliderTarget ?? Double(currentDisplayChapterIndex)).rounded())
        let clamped = min(max(raw, 0), total - 1)
        return "绗?\(clamped + 1) / \(total) 绔?
    }

    /// 鎷栧姩杩涘害鏉℃椂鐨勩€岃竟鎷栬竟璺炽€嶏細鍋?0.12s 灏辫惤涓€绔犮€?
    /// 浠ュ墠鍙湁鎵嬫寚鎶捣锛坥nEditingChanged == false锛夋墠璺筹紝鎷栧埌鍝兘鐪嬩笉鍒板唴瀹瑰彉鍖栥€?
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
        withAnimation(motion.animation(.navigation)) {
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
        withAnimation(motion.animation(.expansion)) {
            if chromeState.isSettingsVisible {
                chromeState.closeSettings()
            } else {
                chromeState.openSettings()
            }
        }
    }

    private func closeReaderChrome() {
        withAnimation(motion.animation(.navigation)) {
            chromeState.closeAll()
        }
    }

    /// A delayed dismissal can close a newly reopened menu or settings panel.
    private func closeReaderChromeFromMenu() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { chromeState.closeAll() }
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
                    Text(speechController.isPaused ? "鏈楄宸叉殏鍋? : "AI 璇煶鏈楄涓?)
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
        .background(readerThemeBackground.opacity(0.98), in: Capsule())
        .overlay(Capsule().stroke(readerThemeTextColor.opacity(0.10), lineWidth: 0.8))
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
                    Text("鑷姩婊氬睆涓?)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(readerThemeTextColor)
                }
                Text(String(format: "%.1f 绉?灞?, autoScrollDelay))
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
        .background(readerThemeBackground.opacity(0.98), in: Capsule())
        .overlay(Capsule().stroke(readerThemeTextColor.opacity(0.10), lineWidth: 0.8))
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
                    appState.record(DiagnosticEvent(level: .info, stage: "reader.sleepTimer", sourceName: currentChapterTitle, message: "鐫＄湢瀹氭椂宸茬敓鏁堬細褰撳墠绔犺妭鎾斁瀹屾瘯宸茶嚜鍔ㄥ仠姝?))
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
            appState.record(DiagnosticEvent(level: .info, stage: "reader.sleepTimer", sourceName: content.title, message: "鐫＄湢瀹氭椂宸茬粨鏉?))
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

    private var openingPositionRecovery: some View {
        VStack(spacing: 16) {
            Text("鏈兘鎭㈠闃呰浣嶇疆").font(.headline)
            Text("宸蹭繚瀛樼殑浣嶇疆鏈洿鏀广€?)
                .font(.subheadline).foregroundStyle(.secondary)
            Button(isRetryingOpeningPosition ? "姝ｅ湪閲嶈瘯鈥? : "閲嶈瘯瀹氫綅") {
                isRetryingOpeningPosition = true
                openingPositionAttempt &+= 1
                if readerMode == .scroll {
                    didLandInitialPosition = false
                    scrollJumpGeneration &+= 1
                    paragraphJumpRequest = ParagraphJumpRequest(index: scrollParagraphTarget)
                } else {
                    rebuildPagedBlocksCache()
                    if readerMode == .cover { reportCoverVisibleIdentity(pagedPageIndex) }
                    if let key = pageIdentityTracker.key { recordVisiblePageIdentity(key) }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRetryingOpeningPosition)
            Button("杩斿洖") { dismiss() }.buttonStyle(.bordered)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(readerThemeTextColor)
        .background(readerThemeBackground.ignoresSafeArea())
        .accessibilityIdentifier("reader.openingRecovery")
    }

    private func resolveOpeningPreview() {
        guard readerOpeningManaged || hasOpeningPositionTimedOut, !hasResolvedOpeningPreview else { return }
        hasResolvedOpeningPreview = true
        hasOpeningPositionTimedOut = false
        scheduleReadingPositionPersistence()
    }

    private func persistReadingPosition(paragraphIndexOverride: Int? = nil) {
        guard pendingWindowJump == nil, !hasOpeningPositionTimedOut,
              !readerOpeningManaged || hasResolvedOpeningPreview else { return }
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
        positionPersistTask?.cancel()
        positionPersistTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: ReaderPerformancePolicy.positionPersistenceDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            // Capture chapter and paragraph together after the debounce.
            // A previously captured local paragraph may belong to another chapter.
            persistReadingPosition()
            checkDailyReadingGoal()
            positionPersistTask = nil
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
        streakDaysCount = max(1, summary.streakDays + (storedSeconds == 0 ? 1 : 0))
        let animation = motion.animation(.expansion)
        withAnimation(animation) { showGoalCelebrationToast = true }
        HapticFeedback.success()
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            withAnimation(animation) { showGoalCelebrationToast = false }
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

    /// 璇诲埌鏈珷鍊掓暟绗?3 椤垫椂灏辨妸涓嬩竴绔犳媺杩涙潵锛涚獥鍙ｅ熬閮ㄥ啀鍚戝澶氶鍙栦竴绔犮€?
    /// 杩欐槸銆岀炕椤佃兘鏃犳劅缁笂涓嬩竴绔犮€嶇殑鍏抽敭锛氫笉鑳界瓑鐢ㄦ埛婊戝埌鏈€鍚庝竴椤垫墠鍙戣姹傘€?
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
        // commit a stale index (the 鈥渃hapter 5 jumps back to chapter 2鈥?
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
            rebuildPagedBlocksCache()
            pagedPageIndex = min(max(pagedPageIndex, 0), positionMapping.maximumPageIndex)
            scheduleReadingPositionPersistence()
            pageLayoutTask = nil
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
            font: fontFamily.uiFont(ofSize: CGFloat(fontSize), customPostScriptName: customFontPostScriptName),
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
            chapterDecoration: chapterDecoration, chapterAlignment: chapterAlignment
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
            traditionalChinese: traditionalChineseEnabled
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

        // 鍒嗛〉涓庨〉闈㈡覆鏌撳叡鐢ㄥ悓涓€浠藉嚑浣曪細ReaderPageGeometry 宸茬粡鎶婂畨鍏ㄥ尯銆侀〉鐪夊甫銆?
        // 姝ｆ枃甯﹀拰椤佃剼甯︾畻鎴愮‘瀹氬潗鏍囷紝杩欓噷涓嶅啀閲嶅鎵?safeArea / padding銆?
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

/// Mutable gesture state that must not invalidate the SwiftUI reader tree.
/// `PageCurlReaderView` reports the start and end of a page turn from a UIKit
/// delegate callback; storing that in `@State` re-evaluates the entire reader
/// body on the first frame of every swipe.
final class ReaderInteractionGate {
    var isPageInteractionActive = false
    var rebuildDeferred = false
    var isScrollInteractionActive = false
    var scrollTrimDeferred = false
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

/// 鐩綍琛岀嫭绔嬫垚 Equatable 瑙嗗浘锛氭粴鍔ㄦ椂鍙湁鐪熸鍙樺寲鐨勮浼氶噸鏂版眰鍊硷紝
/// 鑰屼笉鏄瘡涓粴鍔ㄥ抚閲嶅缓鏁存帓 HStack锛堢珷鑺傚鏃惰繖灏辨槸鎺夊抚鐨勬潵婧愶級銆?
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
        ?? HttpTTSVoice(id: HttpTTSVoice.defaultVoiceID, name: "榛樿璇煶", url: "")
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
            lastErrorMessage = "鏈厤缃椋炰簯绔闊冲嚟鎹紝宸插洖閫€绯荤粺璇煶"
            resolvedEngine = .local
        }
        if resolvedEngine == .file && LocalVoiceLibrary.isEmpty {
            lastErrorMessage = "杩樻病瀵煎叆鏈湴澹伴煶锛屽凡鍥為€€绯荤粺璇煶锛堣缃?鈫?璇煶鏈楄 鈫?鏈湴澹伴煶锛?
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

    /// 鏈湴闊抽閫氶亾锛氱 N 娈电洿鎺ユ挱 `N.mp3`锛堜篃鎺ュ彈 `pN.mp3` / `N - 鏍囬.mp3`锛夈€?
    /// 缂哄摢涓钀藉氨璺宠繃閭ｄ竴娈碉紙鍜屽浘鐗囨钀藉悓鏍峰鐞嗭級锛屼笉鍚堟垚銆佷笉鑱旂綉锛?
    /// 鎾斁澶辫触鏃舵妸寮曟搸閫€鍥炵郴缁熻闊冲苟閲嶅康杩欎竴娈碉紝涓嶈鏁寸珷鍝戞帀銆?
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
            lastErrorMessage = "鏈湴闊抽鎾斁澶辫触锛歕(error.localizedDescription)锛屽凡鍥為€€绯荤粺璇煶"
            engineKind = .local
            playSegment(segment)
        }
    }

    private func playCloudSegment(_ segment: (index: Int, text: String)) {
        guard let credentials = cloudCredentialsStore.load(), credentials.isConfigured else {
            lastErrorMessage = "鏈厤缃椋炰簯绔闊冲嚟鎹紝宸插洖閫€绯荤粺璇煶"
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
        // 鍚屼竴濂楀洖閫€閫昏緫涔熸湇鍔?`.file` 閫氶亾锛屾枃妗堜笉鑳戒竴寰嬪啓銆屼簯绔€嶃€?
        let label = engineKind == .file ? "鏈湴闊抽涓嶅彲鐢? : "浜戠璇煶涓嶅彲鐢?
        lastErrorMessage = "\(label)锛屽凡鍥為€€绯荤粺璇煶锛歕(message)"
        engineKind = .local
        if let segment = activeSegment {
            playSegment(segment)
        } else {
            speakNext()
        }
    }

    private func updateNowPlayingInfo() {
        var info = [String: Any]()
        info[MPMediaItemPropertyTitle] = currentTitle.isEmpty ? "姝ｆ枃鏈楄" : currentTitle
        info[MPMediaItemPropertyArtist] = "绾搁棿璇煶鏈楄"
        info[MPMediaItemPropertyAlbumTitle] = "绾搁棿 (SourceRead)"
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

/// 婊氬姩妯″紡娈佃惤鏁扮粍鐨勬寚绾圭紦瀛樸€?
/// `ReaderView.body` 鍦ㄦ粴鍔ㄦ湡闂翠細琚弽澶嶆眰鍊硷紙鍙娈佃惤鍥炶皟銆佽繘搴﹁惤鍦般€侀〉鑴氬埛鏂帮級锛?
/// 姣忔閮芥妸绐楀彛鍐呭叏閮ㄦ钀芥嫾鎴愭柊鏁扮粍鏄ǔ瀹氱殑娴垂锛涜繖閲屾寜銆屼功 + 鍐呭鎸囩汗銆嶅彧鐣欎竴浠姐€?
/// 鍗曚緥鍙湪涓荤嚎绋嬭闂紙SwiftUI body 涓?Coordinator 鍥炶皟閮藉湪涓荤嚎绋嬶級銆?
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
            .navigationTitle("鎻掑浘鏌ョ湅")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("鍏抽棴") { dismiss() }
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
                            Text("鍔犺浇鎻掑浘涓?..")
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
                Text("鐐瑰嚮鏌ョ湅鎻掑浘澶у浘")
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
/// `.pageCurl` never pop the reader back to the root TabView ("涔︽灦/鍙戠幇/璁剧疆").
private struct ReaderNavigationPopLock: UIViewControllerRepresentable {
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
            if #available(iOS 18.0, *) {
                nav.interactivePopGestureRecognizer?.isEnabled = allowSystemReturn
            } else {
                nav.interactivePopGestureRecognizer?.isEnabled = false
            }
            #if compiler(>=6.2)
            if #available(iOS 26.0, *) {
                nav.interactiveContentPopGestureRecognizer?.isEnabled = allowSystemReturn
            }
            #endif
        }

        func restorePopLock() {
            guard let nav = lockedNavigationController ?? navigationController else { return }
            nav.interactivePopGestureRecognizer?.isEnabled = true
            #if compiler(>=6.2)
            if #available(iOS 26.0, *) {
                nav.interactiveContentPopGestureRecognizer?.isEnabled = true
            }
            #endif
            lockedNavigationController = nil
        }
    }
}
