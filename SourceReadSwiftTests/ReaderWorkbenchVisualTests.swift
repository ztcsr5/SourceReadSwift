import SwiftUI
import XCTest
@testable import SourceReadSwift

final class ReaderWorkbenchVisualTests: XCTestCase {
    @MainActor func testWorkbenchHomeAndHeadingAtNarrowWidth() async throws {
        try await capture(routes: [nil, .heading], width: 320, paper: .white)
    }
    @MainActor func testWorkbenchThemesAndChromeOnDarkPaper() async throws {
        try await capture(routes: [.themes, .chrome], width: 390, paper: .dark)
    }
    @MainActor func testWorkbenchAppearanceTypographyAndAssistanceRemainAccessible() async throws {
        try await capture(routes: [.appearance, .typography, .assistance], width: 390, paper: .bamboo)
    }
    func testWorkbenchValueSizeIsWithinTheExistingPhysicalStackBudget() {
        XCTAssertLessThanOrEqual(MemoryLayout<ReaderSettingsWorkbench>.size, 16 * 1024)
        XCTAssertEqual(Set(ReaderWorkbenchRoute.allCases), Set([.themes, .typography, .appearance, .heading, .chrome, .assistance]))
    }
    @MainActor private func capture(routes: [ReaderWorkbenchRoute?], width: CGFloat, paper: ReaderBackground) async throws {
        let defaults = UserDefaults.standard
        let old = defaults.object(forKey: "reader.background")
        let oldDecoration = defaults.object(forKey: "reader.chapterDecoration")
        defaults.set(paper.rawValue, forKey: "reader.background")
        defaults.set("mountains", forKey: "reader.chapterDecoration")
        defer {
            if let old { defaults.set(old, forKey: "reader.background") } else { defaults.removeObject(forKey: "reader.background") }
            if let oldDecoration { defaults.set(oldDecoration, forKey: "reader.chapterDecoration") } else { defaults.removeObject(forKey: "reader.chapterDecoration") }
        }
        let chapter = BookChapter(title: "第十二章 · 山中来信", url: "local://workbench/0", bookUrl: "local://workbench", index: 0)
        let reader = ReaderView(bookID: "workbench", content: ChapterContent(chapter: chapter, title: chapter.title,
            paragraphs: ["窗外的风翻过书页。所有装饰应在章节开头停下，把后面的时间留给故事。"]), chapterIndex: 0, totalChapters: 1)
        for route in routes {
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            let previous = scene?.windows.first(where: \.isKeyWindow)
            let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
            window.frame = UIScreen.main.bounds
            let context = ReaderWorkbenchContext(bookTitle: "书页之间", background: paper, bottomInset: 12, initialRoute: route)
            let workbench = ReaderSettingsWorkbench(context: context,
                preview: { AnyView(ReaderAtelierPreview(title: chapter.title, excerpt: "窗外的风翻过书页。让纸张、字与留白，成为同一种气质。")) },
                page: { reader.workbenchPage($0) }, actions: ReaderWorkbenchActions(close: {}))
            let host = UIHostingController(rootView: workbench.background(paper.color(isNight: paper.isDark).opacity(0.5)))
            let parent = UIViewController()
            window.rootViewController = parent; window.makeKeyAndVisible()
            parent.addChild(host); parent.view.addSubview(host.view)
            host.view.frame = CGRect(x: 0, y: 0, width: width, height: 844); host.didMove(toParent: parent)
            defer { window.isHidden = true; previous?.makeKey() }
            try await Task.sleep(nanoseconds: 500_000_000); host.view.layoutIfNeeded()
            XCTAssertEqual(host.view.bounds.width, width, accuracy: 1)
            let image = UIGraphicsImageRenderer(size: host.view.bounds.size).image { _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "reader-workbench-\(Int(width))-\(paper.rawValue)-\(route?.rawValue ?? "home")"
            attachment.lifetime = .keepAlways; add(attachment)
        }
    }
}
