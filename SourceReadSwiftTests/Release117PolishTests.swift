import SwiftUI
import Combine
import UIKit
import UniformTypeIdentifiers
import WebKit
import XCTest
@testable import SourceReadSwift

final class Release117PolishTests: XCTestCase {
    @MainActor func testDetailIdentityIsReadableBeforeArrivalAnimationStarts() throws {
        let previousTheme = UserDefaults.standard.object(forKey: "settings.visualTheme")
        UserDefaults.standard.set("classic", forKey: "settings.visualTheme")
        defer {
            if let previousTheme { UserDefaults.standard.set(previousTheme, forKey: "settings.visualTheme") }
            else { UserDefaults.standard.removeObject(forKey: "settings.visualTheme") }
        }
        let renderer = ImageRenderer(content: ImmediateDossierFixture().frame(width: 358, height: 360)
            .background(.white).environment(\.colorScheme, .light))
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.uiImage?.cgImage)
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: 1, y: -1)
            context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
            return true
        }
        XCTAssertTrue(rendered)
        // The right-middle region excludes the jacket, top label and source footer.
        // A hidden title leaves only near-white paper here; count actual text ink.
        var inkPixels = 0
        for y in 90..<230 {
            for x in 190..<330 {
                let offset = (y * width + x) * 4
                if pixels[offset] < 100 && pixels[offset + 1] < 100 && pixels[offset + 2] < 100 { inkPixels += 1 }
            }
        }
        XCTAssertGreaterThan(inkPixels, 40, "Book identity must be legible even before onAppear/animation runs")
    }
    func testFontResourcesAreBoundedAndCannotEscapeTheFontDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertNil(ReaderFontResource.file(for: URL(string: "readerfont://custom/../outside.ttf")!, customDirectory: root))
        XCTAssertNil(ReaderFontResource.file(for: URL(string: "readerfont://custom/%2Foutside.ttf")!, customDirectory: root))
        XCTAssertNil(ReaderFontResource.file(for: URL(string: "readerfont://custom/font.ttf?path=secret")!, customDirectory: root))
        XCTAssertNil(ReaderFontResource.file(for: URL(string: "readerfont://bundle/unknown.ttf")!))
        XCTAssertEqual(ReaderFontResource.file(for: URL(string: "readerfont://custom/font.ttf")!, customDirectory: root),
            root.appendingPathComponent("font.ttf").resolvingSymlinksInPath())
        let css = ReaderFontResource.css(name: "A\"\\字体", file: root.appendingPathComponent("font.ttf"))
        XCTAssertLessThan(css.utf8.count, 1024)
        XCTAssertFalse(css.contains("base64"))
    }

    @MainActor func testWebKitActuallyLoadsTheBundledFontThroughItsLocalScheme() async throws {
        let configuration = WKWebViewConfiguration()
        let handler = ReaderFontSchemeHandler()
        configuration.setURLSchemeHandler(handler, forURLScheme: ReaderFontResource.scheme)
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 568), configuration: configuration)
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let prior = scene?.windows.first(where: \.isKeyWindow)
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
        let controller = UIViewController(); window.rootViewController = controller
        window.makeKeyAndVisible(); controller.view.addSubview(web)
        defer { web.stopLoading(); handler.cancelAll(); window.isHidden = true; prior?.makeKey() }
        let css = WebReaderBundledFontCache.css(for: .maShanZheng)
        web.loadHTMLString("<style>\(css)</style><p style='font-family:MaShanZheng-Regular'>纸间字体</p><script>window.fontResult='pending';document.fonts.load('20px MaShanZheng-Regular').then(function(f){window.fontResult=f.length>0?'loaded':'empty'},function(e){window.fontResult=String(e)})</script>", baseURL: nil)
        var result = "pending"
        for _ in 0..<150 {
            try await Task.sleep(nanoseconds: 100_000_000)
            let value = try? await web.evaluateJavaScript("window.fontResult")
            if let text = value as? String { result = text }
            if result != "pending" { break }
        }
        XCTAssertEqual(result, "loaded", "The font must reach WebContent, not only register in UIKit")
    }
    func testDeskSelectionUsesOnlyActualHistoryAndNeverMutatesTheShelf() {
        var books = (0..<8).map { index in
            BookshelfBook(id: "book-\(index)", title: "书\(index)", author: "纸间", coverURL: nil,
                sourceName: "本地", sourceURL: "local://text", bookURL: "local://\(index)", intro: nil)
        }
        XCTAssertEqual(ReadingDeskSelection.books(from: books).map(\.id), ["book-0"])
        for index in books.indices { books[index].lastReadAt = Date(timeIntervalSince1970: Double(8 - index)) }
        let candidates = ReadingDeskSelection.books(from: books)
        XCTAssertEqual(candidates.map(\.id), ["book-0", "book-1", "book-2", "book-3", "book-4"])
        XCTAssertEqual(ReadingDeskSelection.resolve("book-2", in: candidates), "book-2")
        XCTAssertEqual(ReadingDeskSelection.resolve("deleted", in: candidates), "book-0")
        XCTAssertEqual(ReadingDeskSelection.resolve(nil, in: []), "")
        XCTAssertEqual(books[0].currentChapterIndex, 0)
        XCTAssertNil(AppMotionPolicy(reducesMotion: true).arrivalAnimation(stage: 1))
    }

    @MainActor func testPickerCallbackImportsARealFontAndPreservesItAfterInvalidSelection() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let fonts = CustomFontManager(rootURL: root.appendingPathComponent("fonts"))
        let source = try XCTUnwrap(Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil)?.first)
        let completed = expectation(description: "Native picker delegate produces a usable named font")
        var imported: CustomFontItem?
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        let coordinator = UniversalDocumentPicker.Coordinator(onPick: { urls in
            Task { @MainActor in
                do { imported = try await fonts.importPickedFont(from: urls[0]) }
                catch { XCTFail("Real picker import failed: \(error)") }
                completed.fulfill()
            }
        }, onCancel: { XCTFail("Selecting a font is not cancellation") })
        coordinator.documentPicker(picker, didPickDocumentsAt: [source])
        await fulfillment(of: [completed], timeout: 15)
        let first = try XCTUnwrap(imported)
        XCTAssertNotNil(UIFont(name: first.postScriptName, size: 20))
        XCTAssertEqual(fonts.installedFonts.count, 1)
        let saved = fonts.fontsDirectory.appendingPathComponent(first.fileName)
        let original = try Data(contentsOf: saved)
        let invalid = root.appendingPathComponent(source.lastPathComponent)
        try Data("not a font".utf8).write(to: invalid)
        do { _ = try await fonts.importPickedFont(from: invalid); XCTFail("Invalid bytes must not report success") }
        catch { XCTAssertNotNil(fonts.lastErrorMessage) }
        XCTAssertEqual(try Data(contentsOf: saved), original)
        let again = try await fonts.importPickedFont(from: source)
        XCTAssertEqual(again.postScriptName, first.postScriptName)
        XCTAssertEqual(fonts.installedFonts.count, 1)
        fonts.reloadAndRegisterFonts()
        XCTAssertEqual(fonts.installedFonts.first?.postScriptName, first.postScriptName)
    }

    @MainActor func testMountedClassicBotanicalEditorialDeskAndDossier() async throws {
        try await captureThemes([.classic, .botanical, .editorial])
    }

    @MainActor func testMountedCoastRoseGraphiteDeskAndDossier() async throws {
        try await captureThemes([.coast, .rose, .graphite])
    }

    @MainActor func testMountedFolioInkwashBlueprintDeskAndDossier() async throws {
        try await captureThemes([.folio, .inkwash, .blueprint])
    }

    @MainActor private func captureThemes(_ themes: [AppVisualTheme]) async throws {
        let defaults = UserDefaults.standard
        let previousTheme = defaults.object(forKey: "settings.visualTheme")
        let previousKey = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)
        defer {
            if let previousTheme { defaults.set(previousTheme, forKey: "settings.visualTheme") }
            else { defaults.removeObject(forKey: "settings.visualTheme") }
            previousKey?.makeKey()
        }
        for theme in themes {
            defaults.set(theme.rawValue, forKey: "settings.visualTheme")
            for style in [UIUserInterfaceStyle.light, .dark] {
                let width: CGFloat = style == .dark ? 390 : 320
                let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
                let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
                let host = UIHostingController(rootView: PolishVisualFixture())
                window.frame = UIScreen.main.bounds
                window.overrideUserInterfaceStyle = style
                host.overrideUserInterfaceStyle = style
                let parent = UIViewController(); window.rootViewController = parent
                window.makeKeyAndVisible(); parent.addChild(host); parent.view.addSubview(host.view)
                host.view.frame = CGRect(x: 0, y: 0, width: width, height: 1000); host.didMove(toParent: parent)
                try await Task.sleep(nanoseconds: 350_000_000)
                host.view.layoutIfNeeded()
                XCTAssertEqual(host.traitCollection.userInterfaceStyle, style)
                XCTAssertEqual(host.view.bounds.width, width, accuracy: 1)
                let picture = UIGraphicsImageRenderer(size: host.view.bounds.size).image { _ in
                    host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
                }
                let attachment = XCTAttachment(image: picture)
                attachment.name = "polish-desk-dossier-\(theme.rawValue)-\(style == .dark ? "dark" : "light")"
                attachment.lifetime = .keepAlways; add(attachment)
                window.isHidden = true
            }
        }
    }
    @MainActor func testReadingProgressPublishesOneCoherentSnapshot() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let shelf = BookshelfStore(persistence: BookshelfPersistence(rootURL: root))
        shelf.addLocalTextBook(LocalTextBook(title: "进度发布", author: "纸间",
            chapters: [.init(title: "第一章", paragraphs: ["正文"], index: 0)], language: "zh-CN"))
        let book = try XCTUnwrap(shelf.books.first)
        var snapshots: [[BookshelfBook]] = []
        let observation = shelf.$books.dropFirst().sink { snapshots.append($0) }
        defer { observation.cancel() }
        shelf.updateReadingProgress(bookID: book.id, chapterIndex: 3, chapterTitle: "第四章", totalChapters: 12, paragraphIndex: 18)
        XCTAssertEqual(snapshots.count, 1, "One position must not invalidate every app screen once per field")
        XCTAssertEqual(snapshots.last?.first?.currentParagraphIndex, 18)
        XCTAssertEqual(snapshots.last?.first?.currentChapterTitle, "第四章")
        XCTAssertEqual(snapshots.last?.first?.totalChapters, 12)
        XCTAssertEqual(try BookshelfPersistence(rootURL: root).load().first?.currentParagraphIndex, 18)
    }
    @MainActor func testReadingCardHasCompactRegularHeightAndUnclippedAccessibleLayout() {
        let book = BookshelfBook(id: "polish", title: "写给远方的一封信", author: "纸间",
            coverURL: nil, sourceName: "本地", sourceURL: "local://text", bookURL: "local://polish", intro: nil)
        for width: CGFloat in [288, 358, 398] {
            let regular = UIHostingController(rootView: ReadingHeroCard(book: book).environment(\.dynamicTypeSize, .large))
                .sizeThatFits(in: CGSize(width: width, height: 3000))
            let accessible = UIHostingController(rootView: ReadingHeroCard(book: book).environment(\.dynamicTypeSize, .accessibility3))
                .sizeThatFits(in: CGSize(width: width, height: 3000))
            XCTAssertGreaterThanOrEqual(regular.height, 160)
            XCTAssertLessThanOrEqual(regular.height, 280, "One current book must not consume most of the home screen")
            XCTAssertEqual(regular.width, width, accuracy: 1)
            XCTAssertGreaterThan(accessible.height, regular.height)
        }
    }
}

private struct PolishVisualFixture: View {
    @Namespace private var namespace
    private let book = BookshelfBook(id: "polish", title: "无封面的本地书 · 写给远方的一封长信", author: "纸间读者",
        coverURL: nil, sourceName: "本地 TXT", sourceURL: "local://text", bookURL: "local://polish", intro: nil)
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("正在阅读").font(.title2.weight(.semibold))
                ReadingHeroCard(book: book)
                Text("藏书档案").font(.title2.weight(.semibold))
                BookDetailHero(book: book.asSearchBook, readerSourceID: "fixture", namespace: namespace)
                Text("经典紧凑").font(.headline)
                ReadingHeroCard(book: book, usesSpatialStyle: false)
            }.padding(16)
        }.coordinateSpace(name: "bookDetailScroll").pageBackground()
    }
}

private struct ImmediateDossierFixture: View {
    @Namespace private var namespace
    var body: some View {
        BookDetailHero(book: SearchBook(name: "书籍标题保持清晰", author: "作者姓名", coverUrl: nil,
            bookUrl: "local://immediate", sourceName: "本地", sourceUrl: "local://text", intro: nil),
            readerSourceID: "immediate", namespace: namespace)
    }
}
