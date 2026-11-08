from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
p=ROOT/'SourceReadSwift/Features/Reader/ReaderView.swift'
s=p.read_text(encoding='utf-8-sig')
def replace(old,new):
    global s
    assert old in s,old[:130]
    s=s.replace(old,new)

replace('    @State private var showMoreOptionsMenu = false\n','')
replace('''            if showMoreOptionsMenu && showOverlay && !showSettings {
                moreOptionsMenuOverlay
            }

''','')
replace('''            readerLayoutKey,
            backgroundRawValue,''','''            readerLayoutKey,
            chapterViewportSignature,
            textSelectionEnabled ? "selectable" : "page-taps",
            backgroundRawValue,''')
replace('''"\\(section.chapterIndex):\\(section.title.hashValue):\\(section.paragraphs.count):\\(section.paragraphs.first?.hashValue ?? 0):\\(section.paragraphs.last?.hashValue ?? 0):\\(section.isReady ? 1 : 0)"''','''"\\(section.chapterIndex):\\(section.contentRevision):\\(section.state)"''')
replace('''"\\(section.chapterIndex)|\\(section.title)|\\(section.paragraphs.count)|\\(section.paragraphs.first?.hashValue ?? 0)|\\(section.paragraphs.last?.hashValue ?? 0)"''','''"\\(section.chapterIndex)|\\(section.contentRevision)"''')
replace('''            // `.pageTurn` and `.cover` share the UIKit paging scroll view.
            // `UIPageViewController(.scroll)` built a hosting controller
            // inside each gesture, which dropped frames on ProMotion
            // hardware; this surface keeps three reused slots instead.
''','''            // Cover and slide share transaction semantics, not displacement.
''')
replace('''            case .pageCurl:
                flipPagedReaderContent''','''            case .pageCurl:
                pageCurlReaderContent''')
start=s.index('    /// Simulated page turn ("仿真").')
end=s.index('    private var pageCurlReaderContent:',start)
s=s[:start]+s[end:]
replace('''            pageRevision: { _ in
                readerPageRevisionKey
            },''','''            pageRevision: { page in
                pageTextCacheKey(for: page)
            },''')
replace('''            contentRevision: pagedBlocksCacheKey,''','''            contentRevision: pagedBlocksCacheKey + "|" + readerPageRevisionKey,''')
for name in ['previous','current','next','previous2','next2']:
    replace(f'{name}Identity: {name}Block.map {{ ReaderPageIdentity(page: $0).key }} ?? "",',f'{name}Identity: {name}Block.map {{ pageTextCacheKey(for: $0) }} ?? "",')
replace('''            onPageContainerLayout: pageContainerLayoutHandler,
            pageBackgroundColor: pagedPageBackgroundColor,''','''            onPageContainerLayout: pageContainerLayoutHandler,
            turnStyle: readerMode == .pageTurn ? .slide : .cover,
            pageBackgroundColor: pagedPageBackgroundColor,''')
replace('''        reportCoverVisibleIdentity(resolved)
        updatePagedVisibleParagraph(pageIndex: resolved)
        handlePageInteraction(false)''','''        reportCoverVisibleIdentity(resolved)
        updatePagedVisibleParagraph(pageIndex: resolved)''')
replace('''return "\\(ReaderPageIdentity(page: page).key)|\\(highlightKey)|\\(readerPageRevisionKey)"''','''return "\\(ReaderPageIdentity(page: page).key)|\\(ReaderRenderRevision.page(page))|\\(highlightKey)|\\(readerPageRevisionKey)"''')
replace('''let rawTitle = page.chapterTitle.isEmpty ? chapterTitle(for: page.chapterIndex) : page.chapterTitle''','''let rawTitle = page.inlineTitleText ?? (page.chapterTitle.isEmpty ? chapterTitle(for: page.chapterIndex) : page.chapterTitle)''')
replace('''            // Reserve a safe buffer (16pt) so TextKit line fragments and paragraph breaks
            // can never push the last line past the clipping boundary of the page.
            contentHeight: max(geometry.contentHeight - 16, 120)''','''            // Text pages use final attributed-document TextKit containers.
            // The body rect already excludes header/footer; do not hide layout
            // disagreements behind a fixed subtraction.
            contentHeight: geometry.contentHeight''')
replace('''            let synchronousRadius = windowRadius''','''            let synchronousRadius = 0''')
replace('''               abs(section.chapterIndex - windowCurrentChapterIndex) > synchronousRadius,
               warmupIsRunning || geometryIsSettling {''','''               abs(section.chapterIndex - windowCurrentChapterIndex) > synchronousRadius {''')
replace('''            let warmupIsRunning = paginationWarmupPending
                || (paginationWarmupTask.map { !$0.isCancelled } ?? false)
''','')
replace('''            let geometryIsSettling = !chapterGeometrySettled
''','')
replace('''                placeholderDirection: page.placeholderDirection
''','''                placeholderDirection: page.placeholderDirection,
                inlineTitleText: page.inlineTitleText
''')
start=s.index('                Button {\n                    withAnimation(.easeOut(duration: 0.16)) {\n                        showMoreOptionsMenu.toggle()')
end=s.index('            }\n            .padding(.horizontal, 10)',start)
s=s[:start]+'''                ReaderNativeMenuButton(
                    menu: readerNativeMenu,
                    foregroundColor: background.uiTextColor(isNight: readerIsNight),
                    backgroundColor: background.uiColor(isNight: readerIsNight)
                )
                .frame(width: 44, height: 44)
'''+s[end:]
start=s.index('    @ViewBuilder\n    private var moreOptionsMenuOverlay:')
end=s.index('    private func closeSettingsPanel()',start)
s=s[:start]+'''    private var readerNativeMenu: UIMenu {
        func action(_ title: String, _ symbol: String, enabled: Bool = true, destructive: Bool = false, run: @escaping () -> Void) -> UIAction {
            var attributes: UIMenuElement.Attributes = []
            if !enabled { attributes.insert(.disabled) }
            if destructive { attributes.insert(.destructive) }
            return UIAction(title: title, image: UIImage(systemName: symbol), attributes: attributes) { _ in
                closeReaderChromeFromMenu()
                run()
            }
        }
        var chapterActions: [UIMenuElement] = [
            action("刷新本章", "arrow.clockwise", enabled: onRefreshChapter != nil) { onRefreshChapter?() },
            action("缓存前后章节", "square.and.arrow.down", enabled: onCacheNextChapters != nil) { onCacheNextChapters?(windowCurrentChapterIndex) },
            action("网页打开本章", "safari", enabled: currentChapterWebURL != nil) { showChapterWebPage = true }
        ]
        if canShowPayAction {
            chapterActions.append(action("购买本章", "cart", enabled: !isPerformingPayAction) { showPayActionConfirmation = true })
        }
        var playback: [UIMenuElement] = [
            action(speechController.isPaused ? "继续朗读" : (speechController.isSpeaking ? "暂停朗读" : "开始朗读"),
                   speechController.isSpeaking ? "pause.fill" : "speaker.wave.2") { toggleSpeech() },
            action(autoScrollEnabled ? "暂停自动翻页" : "开始自动翻页", autoScrollEnabled ? "pause.fill" : "play.fill") { toggleAutoScroll() }
        ]
        if speechController.isSpeaking {
            playback.append(action("停止朗读", "stop.fill", destructive: true) { stopSpeechPlayback() })
        }
        let bookActions: [UIMenuElement] = [
            action("书籍详情", "info.circle") {
                if let onRequestBookDetail { onRequestBookDetail() } else { showBookDetailSheet = true }
            },
            action("换源", "arrow.triangle.2.circlepath", enabled: onRequestSourceSwitch != nil) { onRequestSourceSwitch?() },
            action("登录书源", "person.badge.key", enabled: currentBookSource != nil) { readerLoginSource = currentBookSource }
        ]
        return UIMenu(children: [
            UIMenu(options: .displayInline, children: chapterActions),
            UIMenu(options: .displayInline, children: playback),
            UIMenu(options: .displayInline, children: bookActions)
        ])
    }

'''+s[end:]
replace('''        if showMoreOptionsMenu {
            withAnimation(.easeOut(duration: 0.15)) {
                showMoreOptionsMenu = false
            }
            return
        }
''','')
replace('''        showMoreOptionsMenu = false
''','')
assert 'showMoreOptionsMenu' not in s
p.write_text(s,encoding='utf8',newline='\n')
print('ReaderView integrated: native menu/curl, distinct slide/cover, full render revisions, limited sync pagination')
