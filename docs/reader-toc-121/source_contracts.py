"""Source-level regression guards, not a substitute for native/runtime tests."""
from pathlib import Path
import hashlib,json,subprocess
ROOT=Path(__file__).resolve().parents[2]
OUT=Path('F:/SourceReadSwift/reader-toc-121')
reader=(ROOT/'SourceReadSwift/Features/Reader/ReaderView.swift').read_text(encoding='utf-8')
toc=reader.split('private var tocList: some View {',1)[1].split('private func chapterRow',1)[0]
commit=reader.split('private func commitWindowChapterJump',1)[1].split('private var readyWindowIndices',1)[0]
detail=(ROOT/'SourceReadSwift/Features/Discover/BookDetailView.swift').read_text(encoding='utf-8').split('private struct BookDetailAllChaptersView',1)[1]
settings=(ROOT/'SourceReadSwift/Features/Settings/SettingsView.swift').read_text(encoding='utf-8').split('private var settingsHeroSection',1)[0]
cache=(ROOT/'SourceReadSwift/Core/Storage/ChapterContentCacheStore.swift').read_text(encoding='utf-8')
checks={
 'TOC upper bound evaluated once outside row closure':toc.count('windowChapterUpperBound')==1 and toc.index('windowChapterUpperBound')<toc.index('ForEach(visibleChapters)'),
 'TOC no per-row full-scan canJump': 'canJump(to:' not in toc,
 'detail projection evaluated once outside List':detail.count('let visibleChapters = filteredChapters')==1 and 'filteredChapters[index]' not in detail,
 'detail stable one-view row': 'VStack(alignment: .leading, spacing: 8)' in detail and 'id: \\.element.id' in detail,
 'explicit target anchor built before flat-to-page jump':commit.index('rebuildPagedBlocksCache(anchorOverride:')<commit.index('jumpToWindowFlat('),
 'foreground pagination detached and late-result gated':'Task.detached(priority: .userInitiated)' in reader and 'requestID == chapterJumpRequestID' in reader,
 'pending target survives trim':'if let jump = pendingWindowJump { keep.insert(jump.chapterIndex) }' in reader,
 'UI settings have one appearance navigation entry':settings.count('Label("外观"')==1 and 'Section("自定义外观")' not in settings,
 'cache uses ordered background writer':'persistence.saveInBackground(entries)' in cache and 'Self.diskQueue.async' in cache and 'Self.diskQueue.sync' in cache,
 'TOC cover/resume does not replay reader startup':'guard readerPresentationLifecycle.beginAppearance() else { return }' in reader and 'guard readerPresentationLifecycle.endAppearance(chapterListPresented: showChapterList) else { return }' in reader,
 'iOS deployment remains 16': 'IPHONEOS_DEPLOYMENT_TARGET: 16.0' in (ROOT/'project.yml').read_text(),
}
record={'head':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),'scope':'Source contracts only; see native XCTest evidence for executed tests. Device FPS not measured.','checks':checks}
(OUT/'source-contracts.json').write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(record,ensure_ascii=False,indent=2))
assert all(checks.values())
