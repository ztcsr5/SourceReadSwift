from pathlib import Path
R=Path(__file__).resolve().parents[2]
def edit(name,fn):
 p=R/name;s=p.read_text(encoding='utf-8');t=fn(s);assert t!=s,name;p.write_text(t,encoding='utf-8')
def once(s,a,b):
 assert s.count(a)==1,(a[:90],s.count(a));return s.replace(a,b,1)

def root(s):
 start=s.index('        return ZStack(alignment: .bottom) {')
 end=s.index('        // Let SwiftUI lift',start)
 s=s[:start]+'''        return Group {
            switch selectedTab {
            case 0: BookshelfView()
            case 1: DiscoverView(viewModel: appState.discoverViewModel)
            default: SettingsView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The chrome itself owns the inset. An overlay plus an unrelated clear
        // spacer outside NavigationStack was not propagated to pushed Lists.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !appState.isTabChromeHidden {
                VStack(spacing: 8) {
                    if audioCoordinator.currentBook != nil { miniAudioPlayerBar }
                    customTabBar
                }
            }
        }
'''+s[end:]
 return s
edit('SourceReadSwift/App/RootTabView.swift',root)
def shelf(s):
 s=once(s,'.navigationTitle(title)','.navigationTitle(title)\n        .hideRootTabBar()')
 s=once(s,'ToolbarItem(placement: .navigationBarLeading) {\n                if !books.isEmpty','ToolbarItem(placement: .navigationBarTrailing) {\n                if !books.isEmpty')
 # Text over SF Symbol avoids labels wrapping into unreadable narrow columns.
 for title,icon in [('标记已读','checkmark.circle'),('导出','square.and.arrow.up'),('删除','trash'),('移动','folder')]:
  s=once(s,f'Label("{title}", systemImage: "{icon}")',f'Label("{title}", systemImage: "{icon}")\n                                .labelStyle(.iconOnly)\n                                .accessibilityLabel("{title}")')
 return s
edit('SourceReadSwift/Features/Bookshelf/BookshelfView.swift',shelf)
def discover(s):
 s=once(s,'    @Published var displayMode: SearchDisplayMode = .aggregated','    @Published var displayMode: SearchDisplayMode = .aggregated { didSet { resultPage = 0 } }\n    @Published var resultPage = 0\n    static let resultPageSize = 20\n    var resultPageCount: Int { max(1, (displayCount + Self.resultPageSize - 1) / Self.resultPageSize) }\n    private var displayCount: Int { displayMode == .aggregated ? aggregatedResults.count : results.count }\n    var pagedAggregatedResults: [AggregatedSearchBook] { ResultPage.slice(aggregatedResults, page: resultPage) }\n    var pagedGroupedResults: [ResultGroup] { Self.makeGroupedResults(from: ResultPage.slice(results, page: resultPage)) }')
 s=s.replace('ForEach(viewModel.aggregatedResults)', 'ForEach(viewModel.pagedAggregatedResults)').replace('ForEach(viewModel.groupedResults)', 'ForEach(viewModel.pagedGroupedResults)')
 needle='''            if viewModel.displayMode == .aggregated {
                if resultLayout == .grid {'''
 s=once(s,needle,'''            resultPageControls
            if viewModel.displayMode == .aggregated {
                if resultLayout == .grid {''')
 needle='''    private func aggregatedBookGridCard'''
 i=s.index(needle);s=s[:i]+'''    private var resultPageControls: some View {
        HStack {
            Button("上一页") { viewModel.resultPage = max(0, viewModel.resultPage - 1) }
                .disabled(viewModel.resultPage == 0)
            Spacer()
            Text("第 \\(viewModel.resultPage + 1) / \\(viewModel.resultPageCount) 页 · 每页 20 条")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            Spacer()
            Button("下一页") { viewModel.resultPage = min(viewModel.resultPageCount - 1, viewModel.resultPage + 1) }
                .disabled(viewModel.resultPage + 1 >= viewModel.resultPageCount)
        }
        .buttonStyle(.bordered)
    }

'''+s[i:]
 s=once(s,'        aggregatedResults = Self.makeAggregatedResults(from: results)','        aggregatedResults = Self.makeAggregatedResults(from: results)\n        resultPage = min(resultPage, resultPageCount - 1)')
 s=once(s,'        results = []\n        errorMessage', '        resultPage = 0\n        results = []\n        errorMessage') if '        results = []\n        errorMessage' in s else s
 return s
edit('SourceReadSwift/Features/Discover/DiscoverView.swift',discover)

def diagnostic(s):
 a=s.index('        var start = 0\n');b=s.index('\n        return SourceDiagnosticBatchReport(',a)
 s=s[:a]+'''        // Refill a slot as soon as it finishes. Fixed batches made every fast
        // source wait for the slowest timeout before any new probe could start.
        await withTaskGroup(of: SourceDiagnosticReport.self) { group in
            var iterator = sources.makeIterator()
            func submit(_ source: BookSource) {
                group.addTask {
                    await self.run(source: source, keyword: keyword, deepCheck: deepCheck,
                                   page: page, timeout: timeout)
                }
            }
            for _ in 0..<min(size, sources.count) {
                if Task.isCancelled { break }
                if let source = iterator.next() { submit(source) }
            }
            while let report = await group.next() {
                if Task.isCancelled { group.cancelAll(); break }
                reports.append(report)
                completed += 1
                await progress?(completed, report)
                if let source = iterator.next() { submit(source) }
            }
        }
'''+s[b:];return s
edit('SourceReadSwift/Core/Rules/SourceBatchDiagnosticRunner.swift',diagnostic)
for file in ['SourceReadSwift/Features/Settings/SettingsView.swift','SourceReadSwift/Features/SourceManager/SourceManagerView.swift']:
 edit(file,lambda s:s.replace('batchCheckThreads = 4','batchCheckThreads = 8').replace('batchCheckConcurrency: Int = 4','batchCheckConcurrency: Int = 8'))
print('core UI and scheduler patched')
