import UIKit

#if DEBUG
/// Offline fixtures are reachable only by an explicit UI-test launch argument and isolated store.
@MainActor enum FloatingDeskRegressionLaunch {
    static func makeAppState() -> AppState {
        // An argument-domain override would mask writes made by the real style toggle.
        UserDefaults.standard.set(true, forKey: "settings.floatingReadingDeskEnabled")
        if ProcessInfo.processInfo.arguments.contains("--forest-appearance-regression") {
            UserDefaults.standard.set(AppVisualTheme.forest.rawValue, forKey: AppVisualTheme.selectionKey)
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("floating-desk-ui-" + UUID().uuidString)
        let shelf = BookshelfStore(persistence: BookshelfPersistence(rootURL: root),
            groupPersistence: BookshelfGroupPersistence(rootURL: root))
        // Titles/covers are visual fixtures; the original QA prose is not either novel's content.
        let resumesLongChapter = ProcessInfo.processInfo.arguments.contains("--desk-resume-paragraph")
        let crossesChapters = ProcessInfo.processInfo.arguments.contains("--desk-cross-chapter")
        let hasUnreadBook = ProcessInfo.processInfo.arguments.contains("--desk-first-reading")
        let chapters = crossesChapters ? crossingFixtureChapters() : resumesLongChapter ? resumeFixtureChapters() : [LocalTextChapter(title: "剑气长城", paragraphs: [
            "这是纸间的隔离视觉验证书库。封面用于对照构图，正文为原创验证文字，不提供所展示作品的原文。",
            "阅读位置与书架入口仍走真实存储和导航；实验不会覆盖用户的书籍。"
        ], index: 0), LocalTextChapter(title: "山中来信", paragraphs: ["翻过这一页，继续阅读。"], index: 1)]
        let reference = makeReferenceCover(at: root)
        let titles = ["白昼之后，我们把很长很长的信写给远方与尚未相逢的人", "月亮与六便士", "剑来"]
        let authors = ["纸间", "毛姆", "烽火戏诸侯"]
        for (index, title) in titles.enumerated() {
            let cover = index == 0 ? nil : index == 2 ? reference ?? makeCover(at: root, index: index, title: title) : makeCover(at: root, index: index, title: title)
            shelf.addLocalTextBook(LocalTextBook(title: title, author: authors[index], chapters: chapters, coverURL: cover))
            if let book = shelf.books.first, !(hasUnreadBook && index == 1) {
                shelf.markReaderOpened(bookID: book.id)
                let chapter = resumesLongChapter || crossesChapters ? 1 : 0
                shelf.updateReadingProgress(bookID: book.id, chapterIndex: chapter, chapterTitle: chapters[chapter].title,
                    totalChapters: chapters.count, paragraphIndex: resumesLongChapter ? 12 : 0)
            }
        }
        if ProcessInfo.processInfo.arguments.contains("--desk-shelf-scroll") {
            for number in 1...24 {
                shelf.addLocalTextBook(LocalTextBook(title: "书架回归第\(number)册", author: "纸间", chapters: chapters))
            }
        }
        return AppState(sourceStore: SourceStore(persistence: SourcePersistence(rootURL: root)), bookshelfStore: shelf,
            readingHistoryStore: ReadingHistoryStore(persistence: ReadingHistoryPersistence(rootURL: root)))
    }

    private static func crossingFixtureChapters() -> [LocalTextChapter] {
        (0..<4).map { chapter in
            LocalTextChapter(title: "连续阅读第\(chapter + 1)章", paragraphs: (0..<8).map { paragraph in
                "【连续章\(chapter + 1)·段\(paragraph + 1)】" + String(repeating: "窗外的风吹过树梢，纸上的文字接着上一行继续。", count: 3)
            }, index: chapter)
        }
    }

    private static func resumeFixtureChapters() -> [LocalTextChapter] {
        (0..<2).map { chapter in
            let paragraphs = (0..<32).map { paragraph in
                let prefix = chapter == 1 && paragraph == 12 ? "【已保存的阅读段落】" : "第\(paragraph + 1)段。"
                return prefix + String(repeating: "窗边的风轻轻翻过一张纸，天色已经渐亮。", count: 6)
            }
            return LocalTextChapter(title: "恢复位置第\(chapter + 1)章", paragraphs: paragraphs, index: chapter)
        }
    }

    private static func makeCover(at root: URL, index: Int, title: String) -> URL? {
        let path = root.appendingPathComponent("desk-cover-\(index).png")
        let image = UIGraphicsImageRenderer(size: CGSize(width: 336, height: 448)).image { context in
            let bounds = CGRect(x: 0, y: 0, width: 336, height: 448)
            (index == 1 ? UIColor(red: 0.91, green: 0.86, blue: 0.75, alpha: 1) : UIColor(red: 0.16, green: 0.24, blue: 0.30, alpha: 1)).setFill()
            context.fill(bounds)
            if index == 2 {
                UIColor(red: 0.74, green: 0.77, blue: 0.69, alpha: 1).setFill()
                context.cgContext.fillEllipse(in: CGRect(x: 204, y: 64, width: 64, height: 64))
                for row in 0..<5 {
                    UIColor(white: CGFloat(row) * 0.07 + 0.18, alpha: 1).setFill()
                    let ridge = UIBezierPath()
                    ridge.move(to: CGPoint(x: 0, y: 200 + row * 32))
                    ridge.addCurve(to: CGPoint(x: 336, y: 190 + row * 40),
                        controlPoint1: CGPoint(x: 100, y: 100 + row * 40), controlPoint2: CGPoint(x: 180, y: 300 + row * 24))
                    ridge.addLine(to: CGPoint(x: 336, y: 448)); ridge.addLine(to: CGPoint(x: 0, y: 448)); ridge.close(); ridge.fill()
                }
            }
            let ink: UIColor = index == 1 ? .darkGray : .white
            (title as NSString).draw(in: CGRect(x: 32, y: 40, width: 272, height: 180), withAttributes: [
                .font: UIFont.systemFont(ofSize: 36, weight: .medium), .foregroundColor: ink])
        }
        do { try image.pngData()?.write(to: path); return path }
        catch { assertionFailure("Could not write isolated floating-desk cover: \(error)"); return nil }
    }

    private static func makeReferenceCover(at root: URL) -> URL? {
        guard let encoded = ProcessInfo.processInfo.environment["SOURCEREAD_UI_COVER_JPEG"] else { return nil }
        guard encoded.utf8.count <= 192_000, let bytes = Data(base64Encoded: encoded),
              bytes.count <= 128_000, UIImage(data: bytes) != nil else {
            assertionFailure("Expected a valid bounded UI-test reference cover"); return nil
        }
        let path = root.appendingPathComponent("reference-cover.jpg")
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try bytes.write(to: path); return path
        } catch {
            assertionFailure("Could not write isolated reference cover: \(error)"); return nil
        }
    }
}
#endif
