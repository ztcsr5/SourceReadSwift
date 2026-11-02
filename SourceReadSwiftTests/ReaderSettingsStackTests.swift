import SwiftUI
import UIKit
import XCTest
@testable import SourceReadSwift

final class ReaderSettingsStackTests: XCTestCase {
    @MainActor func testActualSettingsPagesMountOnNarrowLightAndNormalDarkPaper() async throws {
        let defaults = UserDefaults.standard
        let old = defaults.object(forKey: "reader.background")
        defer {
            if let old { defaults.set(old, forKey: "reader.background") }
            else { defaults.removeObject(forKey: "reader.background") }
        }
        let chapter = BookChapter(title: "第一章", url: "local://stack-regression/0",
            bookUrl: "local://stack-regression", index: 0)
        for (width, paper) in [(CGFloat(320), "white"), (390, "dark")] {
            defaults.set(paper, forKey: "reader.background")
            var pictures = Set<Data>()
            for tab in 0..<3 {
                let reader = ReaderView(bookID: "stack-regression",
                    content: ChapterContent(chapter: chapter, title: chapter.title, paragraphs: ["正文"]),
                    chapterIndex: 0, totalChapters: 1)
                let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
                let previous = scene?.windows.first(where: \.isKeyWindow)
                let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
                window.frame = UIScreen.main.bounds
                let parent = UIViewController()
                let host = UIHostingController(rootView: ScrollView {
                    reader.settingsPage(for: tab)
                }.padding(16).background(paper == "dark" ? Color.black : Color.white)
                    .environment(\.colorScheme, paper == "dark" ? .dark : .light))
                window.rootViewController = parent; window.makeKeyAndVisible()
                parent.addChild(host); parent.view.addSubview(host.view)
                host.view.frame = CGRect(x: 0, y: 0, width: width, height: 760)
                host.didMove(toParent: parent)
                defer { window.isHidden = true; previous?.makeKey() }
                try await Task.sleep(nanoseconds: 150_000_000)
                host.view.layoutIfNeeded()
                XCTAssertEqual(host.view.bounds.width, width, accuracy: 1)
                let picture = UIGraphicsImageRenderer(size: host.view.bounds.size).image { _ in
                    host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
                }
                pictures.insert(try XCTUnwrap(picture.pngData()))
                let attachment = XCTAttachment(image: picture)
                attachment.name = "reader-settings-stack-\(Int(width))-\(paper)-tab\(tab)"
                attachment.lifetime = .keepAlways; add(attachment)
            }
            XCTAssertEqual(pictures.count, 3, "The real appearance, layout and advanced pages must all render")
        }
    }

    @MainActor func testBoundaryDefersConstructionAndReadsCurrentBindings() {
        var value = 18.0
        var renderedValues: [Double] = []
        let binding = Binding(get: { value }, set: { value = $0 })
        let section = ReaderSettingsContent {
            renderedValues.append(binding.wrappedValue)
            return Text("\(binding.wrappedValue)")
        }
        XCTAssertTrue(renderedValues.isEmpty, "The parent must not build a settings tuple eagerly")
        XCTAssertLessThanOrEqual(MemoryLayout.size(ofValue: section), 32)
        _ = section.body
        binding.wrappedValue = 24
        _ = section.body
        XCTAssertEqual(renderedValues, [18, 24], "The boundary must not cache a stale view or detach bindings")
        XCTAssertEqual(value, 24)
    }

    @MainActor func testSettingsPagesDoNotPropagateOversizedValuesIntoThePanel() {
        let chapter = BookChapter(title: "第一章", url: "local://stack-regression/0",
            bookUrl: "local://stack-regression", index: 0)
        let reader = ReaderView(bookID: "stack-regression",
            content: ChapterContent(chapter: chapter, title: chapter.title, paragraphs: ["正文"]),
            chapterIndex: 0, totalChapters: 1)
        // Reserve at least half of the reported 1008 KB device stack even
        // with 32 nested copies; this is a value budget, not an FPS assertion.
        for (page, bytes) in reader.settingsViewValueSizes() {
            print("READER_SETTINGS_VALUE_BYTES \(page)=\(bytes)")
            XCTAssertLessThanOrEqual(bytes, 16 * 1024,
                "\(page) must have a bounded view boundary before joining the settings panel")
        }
    }
}
