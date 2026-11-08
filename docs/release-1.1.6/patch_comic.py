from pathlib import Path
R=Path(__file__).resolve().parents[2]
p=R/'project.yml';s=p.read_text(encoding='utf8').replace('MARKETING_VERSION: "1.1.5"','MARKETING_VERSION: "1.1.6"').replace('CURRENT_PROJECT_VERSION: "126"','CURRENT_PROJECT_VERSION: "127"');p.write_text(s,encoding='utf8')
p=R/'SourceReadSwift/Features/Reader/ComicReaderView.swift';s=p.read_text(encoding='utf8')
s=s.replace('    @State private var loadGeneration = 0','    @State private var chapterTask: Task<Void, Never>?\n    @State private var timeoutTask: Task<Void, Never>?\n    @State private var loadGeneration = 0')
s=s.replace('self._currentChapterIndex = State(initialValue: initialChapterIndex)','self._currentChapterIndex = State(initialValue: min(max(initialChapterIndex, 0), max(chapters.count - 1, 0)))')
s=s.replace('                            headers: imageHeaders','                            headers: pageRequestHeaders(page)')
s=s.replace('                    headers: imageHeaders','                    headers: pageRequestHeaders(page)')
s=s.replace('        .statusBarHidden(!showChrome && !showSystemStatusBar)','''        .statusBarHidden(!showChrome && !showSystemStatusBar)
        .toolbar(.hidden, for: .navigationBar)
        .hideRootTabBar()
        .onDisappear {
            loadGeneration &+= 1
            chapterTask?.cancel()
            timeoutTask?.cancel()
        }''')
s=s.replace('        guard chapters.indices.contains(index) else { return }','''        guard chapters.indices.contains(index) else {
            isLoading = false
            errorMessage = "漫画目录为空，请返回书籍详情刷新目录"
            return
        }
        chapterTask?.cancel()
        timeoutTask?.cancel()''')
s=s.replace('        Task {\n            let result = await engine.getContent(source: source, chapter: chapter)','''        timeoutTask = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: 30_000_000_000) } catch { return }
            guard generation == loadGeneration, isLoading else { return }
            loadGeneration &+= 1
            chapterTask?.cancel()
            isLoading = false
            errorMessage = "漫画章节请求超过 30 秒，可重试或返回换源"
        }
        chapterTask = Task {
            let result = await engine.getContent(source: source, chapter: chapter)''')
s=s.replace('                self.isLoading = false','                self.timeoutTask?.cancel()\n                self.isLoading = false')
# Parsing is CPU work, not main-actor UI work.
s=s.replace('            await MainActor.run {\n                // A stale', '''            let parsedPages: [ComicPage]
            if case .success(let content) = result {
                parsedPages = await Task.detached(priority: .userInitiated) {
                    ComicContentParser.parsePages(from: content)
                }.value
            } else { parsedPages = [] }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                // A stale''')
s=s.replace('case .success(let content):\n                    let parsedPages = ComicContentParser.parsePages(from: content)','case .success:')
s=s.replace('    private var comicHeader: some View {','''    private func pageRequestHeaders(_ page: ComicPage) -> [String: String] {
        ComicImageRequest(url: page.url, headers: page.headers)
            .mergingHeaders(imageHeaders, chapterURL: currentChapter?.url ?? source.cleanSourceURL)
    }

    private var comicHeader: some View {''')
a=s.index('    @State private var scale: CGFloat',s.index('private struct ComicPageImageView'))
s=s[:a]+s[a:].replace('    @State private var scale: CGFloat', '''    @State private var image: UIImage?
    @State private var failed = false
    @State private var attempt = 0
    @State private var scale: CGFloat''',1)
a=s.index('            if let imageURL = URL(string: url)',s.index('private struct ComicPageImageView'))
b=s.index('\n        }\n        .scaleEffect(scale)',a)
s=s[:a]+'''            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: .fit)
            } else {
                VStack(spacing: 12) {
                    if failed {
                        Image(systemName: "photo.badge.exclamationmark").font(.title2)
                        Text("第 \\(pageNumber) 页加载失败").font(.subheadline)
                        Text("网络、登录状态或图片防盗链可能导致失败")
                            .font(.caption).foregroundStyle(.white.opacity(0.6))
                        Button("重新加载这一页") { attempt += 1 }
                            .buttonStyle(.bordered).frame(minHeight: 44)
                    } else {
                        ProgressView().tint(.white)
                        Text("正在加载第 \\(pageNumber) / \\(totalPages) 页").font(.caption)
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 320)
                .background(Color.white.opacity(0.04))
            }'''+s[b:]
s=s.replace('        .scaleEffect(scale)','''        .task(id: url + "#" + String(attempt)) {
            image = nil
            failed = false
            guard let imageURL = URL(string: url) else { failed = true; return }
            let loaded = await RemoteImageLoader.shared.image(for: imageURL, headers: headers)
            guard !Task.isCancelled else { return }
            image = loaded
            failed = loaded == nil
        }
        .scaleEffect(scale)''')
p.write_text(s,encoding='utf8')
p=R/'SourceReadSwift/Shared/DesignSystem/RemoteImageLoader.swift';s=p.read_text(encoding='utf8').replace('var request = URLRequest(url: url)','var request = URLRequest(url: url, timeoutInterval: 18)');p.write_text(s,encoding='utf8')
