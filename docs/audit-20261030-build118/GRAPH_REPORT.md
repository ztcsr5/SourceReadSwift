> 范围：25个阅读器Swift文件的结构提取，加上已核对的历史/审查语义分片。不是全项目业务正确性证明；token usage未从子代理取得，未统计。

# Graph Report - D:\Gemini反重力\SourceReadSwift2  (2026-10-31)

## Corpus Check
- 25 files · ~63,936 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1085 nodes · 2774 edges · 49 communities (42 shown, 7 thin omitted)
- Extraction: 93% EXTRACTED · 7% INFERRED · 0% AMBIGUOUS · INFERRED: 187 edges (avg confidence: 0.81)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_阅读器组件 0|阅读器组件 0]]
- [[_COMMUNITY_排版与几何 1|排版与几何 1]]
- [[_COMMUNITY_翻页与控制器 2|翻页与控制器 2]]
- [[_COMMUNITY_网页滚动渲染 3|网页滚动渲染 3]]
- [[_COMMUNITY_朗读与音频 4|朗读与音频 4]]
- [[_COMMUNITY_翻页与控制器 5|翻页与控制器 5]]
- [[_COMMUNITY_阅读器组件 6|阅读器组件 6]]
- [[_COMMUNITY_排版与几何 7|排版与几何 7]]
- [[_COMMUNITY_朗读与音频 8|朗读与音频 8]]
- [[_COMMUNITY_阅读器组件 9|阅读器组件 9]]
- [[_COMMUNITY_排版与几何 10|排版与几何 10]]
- [[_COMMUNITY_阅读器组件 11|阅读器组件 11]]
- [[_COMMUNITY_历史与验证 12|历史与验证 12]]
- [[_COMMUNITY_翻页与控制器 13|翻页与控制器 13]]
- [[_COMMUNITY_阅读器组件 14|阅读器组件 14]]
- [[_COMMUNITY_阅读器组件 15|阅读器组件 15]]
- [[_COMMUNITY_阅读器组件 16|阅读器组件 16]]
- [[_COMMUNITY_阅读器组件 17|阅读器组件 17]]
- [[_COMMUNITY_朗读与音频 18|朗读与音频 18]]
- [[_COMMUNITY_朗读与音频 19|朗读与音频 19]]
- [[_COMMUNITY_排版与几何 20|排版与几何 20]]
- [[_COMMUNITY_阅读器组件 21|阅读器组件 21]]
- [[_COMMUNITY_阅读会话集成 22|阅读会话集成 22]]
- [[_COMMUNITY_阅读器组件 23|阅读器组件 23]]
- [[_COMMUNITY_排版与几何 24|排版与几何 24]]
- [[_COMMUNITY_排版与几何 25|排版与几何 25]]
- [[_COMMUNITY_阅读器组件 26|阅读器组件 26]]
- [[_COMMUNITY_翻页与控制器 27|翻页与控制器 27]]
- [[_COMMUNITY_朗读与音频 28|朗读与音频 28]]
- [[_COMMUNITY_阅读器组件 29|阅读器组件 29]]
- [[_COMMUNITY_阅读器组件 30|阅读器组件 30]]
- [[_COMMUNITY_网页滚动渲染 31|网页滚动渲染 31]]
- [[_COMMUNITY_网页滚动渲染 32|网页滚动渲染 32]]
- [[_COMMUNITY_阅读器组件 33|阅读器组件 33]]
- [[_COMMUNITY_阅读器组件 34|阅读器组件 34]]
- [[_COMMUNITY_网页滚动渲染 35|网页滚动渲染 35]]
- [[_COMMUNITY_朗读与音频 36|朗读与音频 36]]
- [[_COMMUNITY_阅读器组件 37|阅读器组件 37]]
- [[_COMMUNITY_排版与几何 38|排版与几何 38]]
- [[_COMMUNITY_阅读器组件 39|阅读器组件 39]]
- [[_COMMUNITY_朗读与音频 40|朗读与音频 40]]
- [[_COMMUNITY_翻页与控制器 41|翻页与控制器 41]]
- [[_COMMUNITY_朗读与音频 42|朗读与音频 42]]
- [[_COMMUNITY_阅读器组件 43|阅读器组件 43]]
- [[_COMMUNITY_阅读器组件 44|阅读器组件 44]]
- [[_COMMUNITY_阅读器组件 45|阅读器组件 45]]
- [[_COMMUNITY_阅读器组件 46|阅读器组件 46]]
- [[_COMMUNITY_阅读会话集成 47|阅读会话集成 47]]
- [[_COMMUNITY_阅读器组件 48|阅读器组件 48]]

## God Nodes (most connected - your core abstractions)
1. `ReaderView` - 201 edges
2. `Int` - 70 edges
3. `String` - 46 edges
4. `ReaderSpeechController` - 42 edges
5. `Coordinator` - 38 edges
6. `View` - 37 edges
7. `ReaderBackground` - 35 edges
8. `Bool` - 35 edges
9. `CoverPageHostController` - 33 edges
10. `ReaderChapterSection` - 28 edges

## Surprising Connections (you probably didn't know these)
- `Pagination audit` --references--> `ReaderPageTextCache`  [EXTRACTED]
  docs/audit-20261030-build118/pagination-audit.md → ReaderView.swift
- `118页脚全safeBottom及16pt缓冲` --does_not_resolve--> `现存分页/富文本缓存revision不足`  [INFERRED]
  SourceReadSwift/Features/Reader/ReaderPageGeometry.swift → docs/audit-20261030-build118/pagination-audit.md
- `118全窗口冷缓存同步分页` --rationale_for--> `MainActor同步排版成本风险`  [INFERRED]
  SourceReadSwift/Features/Reader/ReaderView.swift → docs/audit-20261030-build118/pagination-audit.md
- `ReaderView` --calls--> `ReaderChromeStateMachine`  [INFERRED]
  ReaderView.swift → ReaderAutomationPolicy.swift
- `ReaderView` --calls--> `ReaderPlaybackCoordinator`  [INFERRED]
  ReaderView.swift → ReaderAutomationPolicy.swift

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **跨版本同类阅读反馈** — build103_feedback, build115_crash_feedback, after116_feedback, after117_feedback [INFERRED 0.93]

## Communities (49 total, 7 thin omitted)

### Community 0 - "阅读器组件 0"
Cohesion: 0.08
Nodes (42): CFTimeInterval, CGRect, Configuration, Anchor, Configuration, Coordinator, InsetsSignature, NativeReaderTextView (+34 more)

### Community 1 - "排版与几何 1"
Cohesion: 0.06
Nodes (37): AVFoundation, Date, LocalTextNavigationEntry, PhotosUI, PreferenceKey, ReaderPageEntry, ReaderPageTextSpec, Color (+29 more)

### Community 2 - "翻页与控制器 2"
Cohesion: 0.08
Nodes (35): Item, LockViewController, NSCoder, Coordinator, PageCurlReaderView, PageHostingController, Binding, Bool (+27 more)

### Community 3 - "网页滚动渲染 3"
Cohesion: 0.07
Nodes (35): NSObject, ObjectIdentifier, WebKit, Coordinator, ReaderImageSchemeHandler, Any, Bool, CGFloat (+27 more)

### Community 4 - "朗读与音频 4"
Cohesion: 0.06
Nodes (36): AirPlayRoutePickerView, Context, UIColor, AVKit, AVPlayer, AVRoutePickerView, MediaPlayer, ReaderWallpaperUIImageView (+28 more)

### Community 5 - "翻页与控制器 5"
Cohesion: 0.09
Nodes (25): CATransform3D, CoverPageHostController, CoverPageHostController, CoverPageReaderView, CoverPageTurnStyle, cover, flip, AnyView (+17 more)

### Community 6 - "阅读器组件 6"
Cohesion: 0.09
Nodes (25): Equatable, Layout, LayoutSlot, LoadState, failed, loading, ready, ReaderChapterJumpDisposition (+17 more)

### Community 7 - "排版与几何 7"
Cohesion: 0.07
Nodes (23): ChapterContent, ParagraphJumpRequest, PhotosPickerItem, ReaderBackground, ReaderChapterSlice, ReaderChapterWindowPolicy, ReaderPendingChapterJump, ReaderTapAction (+15 more)

### Community 8 - "朗读与音频 8"
Cohesion: 0.14
Nodes (12): AVSpeechSynthesizer, AVSpeechSynthesizerDelegate, AVSpeechUtterance, Error, HttpTTSVoice, MPRemoteCommand, Notification, ReaderSpeechController (+4 more)

### Community 9 - "阅读器组件 9"
Cohesion: 0.11
Nodes (22): CharacterSet, ProposedViewSize, ReaderCJKPunctuationCompression, CGFloat, Character, NSMutableAttributedString, UIFont, Coordinator (+14 more)

### Community 10 - "排版与几何 10"
Cohesion: 0.15
Nodes (21): NSParagraphStyle, NSTextAlignment, ReaderChapterPaginationContext, ReaderChapterPaginator, Bool, CGFloat, Double, Int (+13 more)

### Community 11 - "阅读器组件 11"
Cohesion: 0.11
Nodes (22): ReaderBackground, azure, custom, dark, eink, gray, green, kraft (+14 more)

### Community 12 - "历史与验证 12"
Cohesion: 0.07
Nodes (28): 116后末章漏字和快翻拖拽复反馈, 117后菜单、拖拽、底行与设置回归反馈, 118全窗口冷缓存同步分页, 103翻页卡顿、衔接慢、选章后不能下一章, 103未闭环问题总账, 106稳定reader身份与窗口内跳转, Build114段距与几何修补, Build115五槽宿主与预热 (+20 more)

### Community 13 - "翻页与控制器 13"
Cohesion: 0.10
Nodes (20): Outcome, next, previous, springBack, ReaderCoverSettlePolicy, ReaderCoverSwipeDecision, cancel, next (+12 more)

### Community 14 - "阅读器组件 14"
Cohesion: 0.10
Nodes (23): CaseIterable, Codable, ComicReadingMode, horizontalLTR, horizontalRTL, vertical, Hashable, Identifiable (+15 more)

### Community 15 - "阅读器组件 15"
Cohesion: 0.19
Nodes (4): ParagraphJumpRequest, ReaderPageBlock, ReaderPageEntry, Int

### Community 16 - "阅读器组件 16"
Cohesion: 0.12
Nodes (13): Decoder, Encoder, ReaderFontFamily, bold, custom, kaiti, light, rounded (+5 more)

### Community 19 - "朗读与音频 19"
Cohesion: 0.22
Nodes (5): ReaderAutomationSession, ReaderPositionMapping, Bool, Int, ReaderMode

### Community 20 - "排版与几何 20"
Cohesion: 0.26
Nodes (11): ReaderPageChrome, ReaderPageChromeLayout, header, hidden, inline, ReaderPageContainerMetrics, ReaderPageContainerMetricsKey, ReaderPageGeometry (+3 more)

### Community 21 - "阅读器组件 21"
Cohesion: 0.17
Nodes (3): ScrollChapterStatus, Bool, ReaderWindowChapterOutcome

### Community 22 - "阅读会话集成 22"
Cohesion: 0.20
Nodes (11): ComicPage, ComicPageImageView, ComicReaderView, AppState, BookChapter, BookSource, Bool, CGFloat (+3 more)

### Community 23 - "阅读器组件 23"
Cohesion: 0.18
Nodes (11): ReaderImageSizingPolicy, ReaderImageStyle, full, single, standard, text, Bool, CGFloat (+3 more)

### Community 24 - "排版与几何 24"
Cohesion: 0.22
Nodes (3): ReaderPageContainerMetrics, Double, Task

### Community 25 - "排版与几何 25"
Cohesion: 0.26
Nodes (8): ReaderNumberInput, ReaderTypographyDefaults, ReaderValueNormalizer, Binding, ClosedRange, Double, String, UInt32

### Community 26 - "阅读器组件 26"
Cohesion: 0.20
Nodes (9): Combine, ReaderCoverSwipeState, ReaderPagedSwipeDecision, next, previous, ReaderPagedSwipePolicy, ReaderScrollChromePolicy, ReaderSettingsLayoutPolicy (+1 more)

### Community 27 - "翻页与控制器 27"
Cohesion: 0.16
Nodes (14): CoverPageHostController.apply, ReaderView.commitCoverTurn, ReaderView.coverPagedReaderContent, CoverPageHostController.installFramesIfNeeded, CoverPageHostController.scrollViewWillBeginDragging, CoverPageHostController, PageCurlReaderView.Coordinator.prewarm, ReaderCoverSettlePolicy.outcome(shift:) (+6 more)

### Community 28 - "朗读与音频 28"
Cohesion: 0.16
Nodes (7): ObservableObject, ReaderPlaybackCoordinator, ReaderPlaybackMode, autoScroll, idle, pausedSpeech, speech

### Community 29 - "阅读器组件 29"
Cohesion: 0.23
Nodes (8): QuoteCardTheme, aurora, bamboo, obsidian, parchment, QuoteCardView, Color, UIImage

### Community 30 - "阅读器组件 30"
Cohesion: 0.15
Nodes (5): ReaderChromeMode, hidden, overlay, settings, ReaderChromeStateMachine

### Community 31 - "网页滚动渲染 31"
Cohesion: 0.24
Nodes (8): CoreText, ReaderFontFamily, Any, Int, WebReaderContentPayloadBuilder, WebReaderFlatIndexPolicy, WebReaderHTML, WebReaderSection

### Community 32 - "网页滚动渲染 32"
Cohesion: 0.33
Nodes (6): Data, String, URL, WebReaderCustomFontCache, WebReaderImageScheme, WebReaderJavaScriptLiteral

### Community 33 - "阅读器组件 33"
Cohesion: 0.33
Nodes (7): ReaderPageIdentity, ReaderPageRestoration, Bool, Int, ReaderChapterPosition, ReaderPageBlock, String

### Community 34 - "阅读器组件 34"
Cohesion: 0.22
Nodes (7): AttributedString, ReaderTextTransform, CGFloat, Character, Font, NSAttributedString, UIFont

### Community 35 - "网页滚动渲染 35"
Cohesion: 0.31
Nodes (7): UITraitCollection, Bool, Double, ReaderFontFamily, UIColor, WebReaderColor, WebReaderStylePayload

### Community 36 - "朗读与音频 36"
Cohesion: 0.29
Nodes (8): AudioBookPlayerView, AppState, Bool, Double, Float, Int, ReaderBookmark, String

### Community 37 - "阅读器组件 37"
Cohesion: 0.22
Nodes (7): ReaderAdvanceDecision, advance, nextChapter, stop, ReaderAutomationPolicy, Double, ReaderMode

### Community 38 - "排版与几何 38"
Cohesion: 0.27
Nodes (3): ReaderChapterPageCacheEntry, ReaderChapterPaginationContext, ReaderPageTypography

### Community 39 - "阅读器组件 39"
Cohesion: 0.31
Nodes (4): CGImage, ReaderCustomWallpaperStore, URL, UIImage

### Community 40 - "朗读与音频 40"
Cohesion: 0.36
Nodes (5): JSCoreRuntime, ReaderSpeechQueue, Bool, String, URL

### Community 41 - "翻页与控制器 41"
Cohesion: 0.43
Nodes (3): CoreGraphics, Foundation, UIKit

### Community 43 - "阅读器组件 43"
Cohesion: 0.52
Nodes (4): Insets, ReaderSafeAreaResolver, CGFloat, CGSize

### Community 45 - "阅读器组件 45"
Cohesion: 0.40
Nodes (5): AppState, iOS unit-test workflow, Independent IPA workflow, XcodeGen project, Project audit

## Knowledge Gaps
- **215 isolated node(s):** `AppState`, `ReaderBookmark`, `Bool`, `Float`, `String` (+210 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **7 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `ReaderView` connect `排版与几何 7` to `排版与几何 1`, `网页滚动渲染 3`, `翻页与控制器 5`, `朗读与音频 8`, `阅读器组件 9`, `排版与几何 10`, `阅读器组件 15`, `阅读器组件 17`, `朗读与音频 18`, `朗读与音频 19`, `排版与几何 20`, `阅读器组件 21`, `排版与几何 24`, `朗读与音频 28`, `阅读器组件 30`, `阅读器组件 33`, `排版与几何 38`, `阅读器组件 44`, `阅读器组件 45`?**
  _High betweenness centrality (0.339) - this node is a cross-community bridge._
- **Why does `View` connect `排版与几何 1` to `朗读与音频 36`, `朗读与音频 4`, `排版与几何 7`, `阅读会话集成 22`, `排版与几何 25`, `阅读器组件 29`?**
  _High betweenness centrality (0.060) - this node is a cross-community bridge._
- **Why does `ReaderSpeechController` connect `朗读与音频 8` to `排版与几何 1`, `网页滚动渲染 3`, `排版与几何 7`, `朗读与音频 40`, `阅读器组件 15`, `阅读器组件 21`, `排版与几何 24`, `朗读与音频 28`?**
  _High betweenness centrality (0.060) - this node is a cross-community bridge._
- **Are the 2 inferred relationships involving `ReaderView` (e.g. with `ReaderChromeStateMachine` and `ReaderPlaybackCoordinator`) actually correct?**
  _`ReaderView` has 2 INFERRED edges - model-reasoned connections that need verification._
- **What connects `AppState`, `ReaderBookmark`, `Bool` to the rest of the system?**
  _215 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `阅读器组件 0` be split into smaller, more focused modules?**
  _Cohesion score 0.0808641975308642 - nodes in this community are weakly interconnected._
- **Should `排版与几何 1` be split into smaller, more focused modules?**
  _Cohesion score 0.06015037593984962 - nodes in this community are weakly interconnected._