from pathlib import Path
import subprocess, json
r=Path(__file__).resolve().parents[2];o=Path('F:/SourceReadSwift/release-1.1.1')
def read(p): return (r/'SourceReadSwift'/p).read_text(encoding='utf8')
gateway=read('Features/Bookshelf/BookshelfReaderGatewayView.swift')
root=read('App/RootTabView.swift');reader=read('Features/Reader/ReaderView.swift')
coordinator=read('Core/Rules/SourceBatchCheckCoordinator.swift')
checks={
 'source picker fullscreen':'.fullScreenCover(isPresented: $showSourceSwitcher)' in gateway,
 'source candidate search ownership guarded':'sourceSwitchGeneration == token' in gateway,
 'partial TOC not trusted as full during source switch':'cached?.isComplete == true' in gateway,
 'source switch aligns live persisted chapter':'let progress = currentBook' in gateway and 'SourceChapterAlignment.match' in gateway,
 'covered old reader ends before store switches source':gateway.index('NotificationCenter.default.post(name: .readerSourceWillChange')<gateway.index('appState.bookshelfStore.switchSource'),
 'old-source background TOC cannot replace current': 'currentBook.sourceURL == activeBook.sourceURL' in gateway,
 'root nav occupies safe area':'.safeAreaInset(edge: .bottom' in root,
 'iOS26 native tabs plus old-system branch': '#available(iOS 26.0, *)' in root and 'legacyNavigationContent' in root,
 'tap next routes to animation request':'requestAnimatedPageTurn(direction: 1)' in reader,
 'source cover does not replay original reader position':'showChapterList || temporaryCoverPresented' in reader,
 'distant target bypasses old window warmup': 'if pendingWindowJump?.chapterIndex == section.chapterIndex' in reader,
 'production diagnostic does not mutate global fallback':'allowWebViewFallback = ' not in coordinator,
 'production diagnostic has no batch barriers':'sources.chunked' not in coordinator and 'iterator.next() { submit(source) }' in coordinator,
 'actual UI concurrency forwarded':'concurrency: batchCheckConcurrency' in read('Features/SourceManager/SourceManagerView.swift'),
 'search list pages twenty': 'ResultPage.slice' in read('Features/Discover/DiscoverView.swift') and 'size: Int = 20' in read('Shared/ResultPage.swift'),
 'minimum iOS16 preserved':'IPHONEOS_DEPLOYMENT_TARGET: 16.0' in (r/'project.yml').read_text(encoding='utf8'),
}
record={'head':subprocess.check_output(['git','rev-parse','HEAD'],cwd=r,text=True).strip(),
 'scope':'Source structure guards only; not native execution or physical-device performance proof.','checks':checks}
(o/'source-contracts.json').write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps(checks,ensure_ascii=False,indent=2));assert all(checks.values())
