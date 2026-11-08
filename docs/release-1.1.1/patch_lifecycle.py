from pathlib import Path
root=Path(__file__).resolve().parents[2]
p=root/'SourceReadSwift/Features/Reader/ReaderView.swift';s=p.read_text(encoding='utf8')
s=s.replace('    @State private var tabChromeOwner = UUID()','    @State private var tabChromeOwner = UUID()\n    @State private var readerSessionEnded = false',1)
s=s.replace('        .onAppear {\n            // Dismissing the full-screen TOC','        .onAppear {\n            appState.acquireTabChromeHidden(owner: tabChromeOwner)\n            // Dismissing the full-screen TOC',1)
s=s.replace('            migrateTypographyDefaultsIfNeeded()','            readerSessionEnded = false\n            migrateTypographyDefaultsIfNeeded()',1)
a=s.index('            windowGeneration &+= 1',s.index('        .onDisappear {\n            // Cover presentation'))
b=s.index('\n        .onChange(of: keepScreenAwake)',a)
block=s[a:b];assert block.endswith('        }')
body=block[:-len('        }')]
s=s[:a]+'            endReaderSession()\n        }\n        .onReceive(NotificationCenter.default.publisher(for: .readerSourceWillChange)) { notice in\n            guard notice.object as? String == bookID else { return }\n            endReaderSession()\n        }'+s[b:]
s=s.replace('        .onDisappear {\n            // Cover presentation','        .onDisappear {\n            // Ownership is visibility-scoped even for temporary covers.\n            appState.releaseTabChromeHidden(owner: tabChromeOwner)\n            // Cover presentation',1)
marker='    private func scheduleGeometrySettle() {'
method='    private func endReaderSession() {\n        guard !readerSessionEnded else { return }\n        readerSessionEnded = true\n'+''.join(line[4:]+'\n' for line in body.splitlines())+'    }\n\n'
assert marker in s;s=s.replace(marker,method+marker,1)
s=s.replace('        if pendingWindowJump?.chapterIndex == index { return true }','        if let jump = pendingWindowJump { return jump.chapterIndex == index }',1)
s=s.replace('        guard readerMode != .scroll else { return }\n        pageLayoutTask?.cancel()','        guard readerMode != .scroll, pendingWindowJump == nil else { return }\n        pageLayoutTask?.cancel()')
# Prevent an old scheduled layout from competing with a deliberate far jump.
mark='        // A deliberate selection outranks speculative work for the old cursor.'
s=s.replace(mark,'        pageLayoutTask?.cancel()\n        pageLayoutTask = nil\n'+mark,1)
p.write_text(s,encoding='utf8')
p=root/'SourceReadSwift/Features/Reader/ReaderPresentationLifecycle.swift';s=p.read_text(encoding='utf8')
s=s.replace('private struct ReaderTemporaryCoverKey:', 'extension Notification.Name {\n    static let readerSourceWillChange = Notification.Name("SourceReadSwift.readerSourceWillChange")\n}\n\nprivate struct ReaderTemporaryCoverKey:',1);p.write_text(s,encoding='utf8')
p=root/'SourceReadSwift/Features/Bookshelf/BookshelfReaderGatewayView.swift';s=p.read_text(encoding='utf8')
s=s.replace('        appState.bookshelfStore.switchSource(bookID: book.id, to: candidate.book,','        // End the covered reader while its old source/progress are still authoritative.\n        NotificationCenter.default.post(name: .readerSourceWillChange, object: book.id)\n        appState.bookshelfStore.switchSource(bookID: book.id, to: candidate.book,',1)
p.write_text(s,encoding='utf8')
