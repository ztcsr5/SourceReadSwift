from pathlib import Path
p=Path(__file__).resolve().parents[2]/'SourceReadSwift/Core/Audio/AudioBookPlaybackCoordinator.swift'
s=p.read_text(encoding='utf8')
marker='    func playChapter(at index: Int, resumeSeconds: Double? = nil) {'
s=s.replace(marker,'    private var chapterLoadTask: Task<Void, Never>?\n    private var chapterLoadID = UUID()\n\n'+marker,1)
s=s.replace('        currentChapterIndex = index\n','        chapterLoadTask?.cancel()\n        chapterLoadID = UUID()\n        let loadID = chapterLoadID\n        currentChapterIndex = index\n',1)
s=s.replace('extractAudioURL(from: chapter.url), isAudioMediaURL(directURL)','AudioContentParser.parseURL(chapter.url, base: chapter.url), AudioContentParser.isMediaURL(directURL)',1)
s=s.replace('        Task { @MainActor [weak self] in\n            guard let self else { return }\n            let contentResult = await engine.getContent(source: source, chapter: chapter)\n','        chapterLoadTask = Task { @MainActor [weak self] in\n            guard let self else { return }\n            let contentResult = await engine.getContent(source: source, chapter: chapter)\n            guard !Task.isCancelled, self.chapterLoadID == loadID else { return }\n',1)
s=s.replace('self.extractAudioURL(from: content.text) ?? self.extractAudioURL(from: chapter.url)','AudioContentParser.parseURL(content.text, base: chapter.url)',1)
s=s.replace('                } else if !content.text.isEmpty {\n                    self.setupPlayer(with: content.text.trimmingCharacters(in: .whitespacesAndNewlines))\n','',1)
# stop cancels request too: an old reply must not resurrect playback.
s=s.replace('    func stop() {','    func stop() {\n        chapterLoadID = UUID()\n        chapterLoadTask?.cancel()\n        chapterLoadTask = nil',1)
a=s.index('    private func extractAudioURL('); s=s[:a]+'}\n'
p.write_text(s,encoding='utf8')
