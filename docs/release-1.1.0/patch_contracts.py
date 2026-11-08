from pathlib import Path
R=Path(__file__).resolve().parents[2]
p=R/'SourceReadSwiftTests/ReaderRecovery119Tests.swift';s=p.read_text(encoding='utf8')
s=s.replace('ReaderPageLayoutEngine.displayText(original, fontSize: size, indent: size * 2)', 'original').replace('ReaderPageLayoutEngine.displayText(original, fontSize: 20, indent: 40)', 'original')
p.write_text(s,encoding='utf8')
p=R/'SourceReadSwift/Features/Reader/ReaderChapterPaginator.swift';s=p.read_text(encoding='utf8').replace('// 页眉模式：章节名画在页眉带，正文第一页从与后续页完全相同的位置开始，\n        // 不再给标题预留 40~50pt 的正文高度。只有「正文大标题」模式保留旧行为。','// Both visible title modes include the chapter-opening heading. Only\n        // hidden explicitly removes it; header also retains the small page header.')
p.write_text(s,encoding='utf8')
p=R/'SourceReadSwift/Features/Discover/BookDetailView.swift';s=p.read_text(encoding='utf8').replace('if case .success(let value) = retry', 'if case .success(let value)? = retry')
s=s.replace('        guard current() else { return }\n        isLoading = false\n        let cacheDetail', '''        guard current() else { return }
        if appState.bookshelfStore.contains(selectedBook), let fetchedDetail {
            appState.bookshelfStore.updateDetails(bookID: selectedBook.id,
                latestChapterTitle: fetchedDetail.latestChapter, intro: fetchedDetail.intro,
                totalChapters: chapters.count, coverURL: fetchedDetail.coverUrl)
        }
        isLoading = false
        let cacheDetail''')
p.write_text(s,encoding='utf8')
p=R/'SourceReadSwift/Shared/AppVersion.swift';s=p.read_text(encoding='utf8').replace('1.0.119','1.1.0').replace('parts[1] : 0','parts[1] : 1').replace('parts[2] : 119','parts[2] : 0').replace('?? 119','?? 120');p.write_text(s,encoding='utf8')
p=R/'project.yml';s=p.read_text(encoding='utf8').replace('MARKETING_VERSION: "1.0.119"','MARKETING_VERSION: "1.1.0"').replace('CURRENT_PROJECT_VERSION: "119"','CURRENT_PROJECT_VERSION: "120"');p.write_text(s,encoding='utf8')
# Preserve the wide local cache, but do not enqueue six full TextKit chapters
# alongside the first interactive frame. Two workers leave CPU for WebKit/UI.
p=R/'SourceReadSwift/Shared/Performance/ReaderPerformancePolicy.swift';s=p.read_text(encoding='utf8').replace('static let paginationWarmupBatchSize = 6','static let paginationWarmupBatchSize = 2');p.write_text(s,encoding='utf8')
p=R/'SourceReadSwift/Features/Reader/ReaderView.swift';s=p.read_text(encoding='utf8').replace('if !isLocalChapterBook && interactionGate.isPageInteractionActive {','if interactionGate.isPageInteractionActive {')
s=s.replace('prewarmPageText(around index: Int, radius: Int = 12)', 'prewarmPageText(around index: Int, radius: Int = 4)')
s=s.replace('''        prefetchTask = Task { @MainActor in
            while''','''        prefetchTask = Task { @MainActor in
            // Let the first document/page commit before neighbouring chapters
            // start patching it. Cancellation still takes effect immediately.
            try? await Task.sleep(nanoseconds: 180_000_000)
            while''')
p.write_text(s,encoding='utf8')
