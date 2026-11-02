import SwiftUI
import XCTest
@testable import ZhijianMotionLab

final class LabMotionTests: XCTestCase {
    func testChoreographyClampsStepsAndWrapsOnlyNonemptyCollections() {
        XCTAssertEqual(IntroChoreography.safeStep(-1), 0)
        XCTAssertEqual(IntroChoreography.safeStep(Int.max), 5)
        XCTAssertNil(IntroChoreography.nextIndex(0, direction: 1, count: 0))
        XCTAssertEqual(IntroChoreography.nextIndex(0, direction: -1, count: 7), 6)
        XCTAssertEqual(IntroChoreography.nextIndex(6, direction: 1, count: 7), 0)
    }

    func testEveryBookHasStableIdentityAndUsableArtwork() throws {
        XCTAssertEqual(LabBook.samples.count, 7)
        XCTAssertEqual(Set(LabBook.samples.map(\.id)).count, 7)
        for book in LabBook.samples {
            XCTAssertFalse(book.title.isEmpty); XCTAssertFalse(book.synopsis.isEmpty)
            XCTAssertEqual(book.chapters.count, 3); XCTAssertEqual(book.paragraphs.count, 5)
            XCTAssertNotNil(UIImage(named: book.artwork))
        }
    }

    func testPagingTracksFingerSettlesInBothDirectionsAndRejectsInvalidGeometry() {
        XCTAssertEqual(IntroPaging.position(start: 0, translation: -195, width: 390), 0.5)
        XCTAssertEqual(IntroPaging.position(start: 1, translation: 195, width: 390), 0.5)
        XCTAssertEqual(IntroPaging.position(start: 0, translation: 200, width: 390), 0)
        XCTAssertEqual(IntroPaging.position(start: 5, translation: -200, width: 390), 5)
        XCTAssertEqual(IntroPaging.position(start: 2, translation: 20, width: 0), 2)
        XCTAssertEqual(IntroPaging.position(start: 2, translation: .nan, width: 390), 2)
        XCTAssertEqual(IntroPaging.target(origin: 0, translation: -150, predicted: -180, width: 390), 1)
        XCTAssertEqual(IntroPaging.target(origin: 1, translation: 150, predicted: 180, width: 390), 0)
        XCTAssertEqual(IntroPaging.target(origin: 1, translation: 30, predicted: 40, width: 390), 1)
        XCTAssertEqual(IntroPaging.target(origin: 1, translation: -25, predicted: -250, width: 390), 2)
        XCTAssertEqual(IntroPaging.target(origin: Int.max, translation: -300, predicted: -300, width: 390), 5)
        XCTAssertEqual(IntroPaging.blend(10, 30, fraction: 0.5), 20)
        XCTAssertEqual(IntroPaging.blend(10, 30, fraction: .nan), 10)
    }

    func testReadingBundleContainsRealBooksButNoRexPosterOrMovieFile() throws {
        XCTAssertEqual(LabBook.samples[0].title, "三体")
        XCTAssertEqual(Set(LabBook.samples.map(\.artwork)).count, 7)
        XCTAssertTrue(LabBook.samples.allSatisfy { $0.artwork.hasPrefix("Book") })
        XCTAssertNil(UIImage(named: "CoverTide"))
        XCTAssertNil(UIImage(named: "Ref106379"))
        let paths = FileManager.default.enumerator(at: Bundle.main.bundleURL, includingPropertiesForKeys: nil)?.allObjects.compactMap { $0 as? URL } ?? []
        XCTAssertTrue(paths.filter { ["mp4", "mov", "m4v"].contains($0.pathExtension.lowercased()) }.isEmpty)
        XCTAssertNil(Bundle.main.url(forResource: "ReferenceMedia", withExtension: "json"))
        XCTAssertTrue(LabBook.samples[0].paragraphs[0].contains("不是原书正文"))
    }

    @MainActor func testLocalPositionAndQuoteRoundTripDeduplicationAndReset() throws {
        let suite = "motionlab.tests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let book = LabBook.samples[0], library = LabLibrary(preferences: preferences)
        XCTAssertTrue(library.snapshot.positions.isEmpty); XCTAssertTrue(library.snapshot.quotes.isEmpty)
        library.savePosition(book: book, chapter: 1, paragraph: 3)
        library.saveQuote(book: book, paragraph: 2); library.saveQuote(book: book, paragraph: 2)
        library.saveQuote(book: book, paragraph: -1)
        let reopened = LabLibrary(preferences: preferences)
        XCTAssertEqual(reopened.position(for: book), LabPosition(chapter: 1, paragraph: 3))
        XCTAssertEqual(reopened.snapshot.quotes.count, 1)
        XCTAssertEqual(reopened.snapshot.quotes[0].text, book.paragraphs[2])
        reopened.savePosition(book: book, chapter: Int.max, paragraph: Int.min)
        XCTAssertEqual(reopened.position(for: book), LabPosition(chapter: 2, paragraph: 0))
        reopened.reset()
        XCTAssertEqual(LabLibrary(preferences: preferences).snapshot, LabSnapshot())
    }

    @MainActor func testDamagedDemoRecordIsReportedWithoutOverwritingOriginalBytes() throws {
        let suite = "motionlab.damaged.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let broken = Data("broken".utf8); preferences.set(broken, forKey: "lab.snapshot")
        let library = LabLibrary(preferences: preferences)
        XCTAssertNotNil(library.persistenceMessage)
        XCTAssertEqual(preferences.data(forKey: "lab.snapshot"), broken)
    }

    @MainActor func testDecodePreparesCoverAndPreblurredBackgroundOnce() async throws {
        let artwork = LabArtwork(); await artwork.prepare()
        XCTAssertTrue(artwork.isReady)
        for book in LabBook.samples { XCTAssertNotNil(artwork.image(book.artwork)) }
        for book in LabBook.samples {
            let cover = try XCTUnwrap(artwork.image(book.artwork))
            XCTAssertLessThanOrEqual(max(cover.size.width, cover.size.height), 1200)
            let haze = try XCTUnwrap(artwork.haze(book.artwork))
            XCTAssertLessThanOrEqual(max(haze.size.width, haze.size.height), 96)
        }
        let first = artwork.image("BookThreeBody"); await artwork.prepare()
        XCTAssertTrue(first === artwork.image("BookThreeBody"))
    }

    @MainActor func testSixIntroScenesAndPosterHomeMountedAtPhoneWidths() async throws {
        let suite = "motionlab.snapshots.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let library = LabLibrary(preferences: preferences), artwork = LabArtwork(); await artwork.prepare()
        for width: CGFloat in [320, 390] {
            let height: CGFloat = width == 320 ? 568 : 844
            for step in 0..<IntroChoreography.stepCount {
                try await capture("intro-\(step)-\(Int(width))", width: width, height: height,
                                  content: LabIntroView(step: .constant(step), onFinish: {}, sampledTime: 2)
                                    .environmentObject(library).environmentObject(artwork))
            }
            try await capture("poster-home-\(Int(width))", width: width, height: height,
                              content: ReadingHomeView(selectedIndex: .constant(0), onDetail: { _ in }, onRead: { _ in })
                                .environmentObject(library).environmentObject(artwork), style: .dark)
        }
        try await capture("intro-mid-drag-390", width: 390, height: 844,
                          content: LabIntroView(step: .constant(0), onFinish: {}, sampledTime: 2, sampledPosition: 0.5)
                            .environmentObject(library).environmentObject(artwork))
        library.minimizesMotion = true
        try await capture("intro-accessibility-static", width: 320, height: 568,
                          content: LabIntroView(step: .constant(0), onFinish: {}, sampledTime: 0)
                            .environment(\.dynamicTypeSize, .accessibility1)
                            .environmentObject(library).environmentObject(artwork))
    }

    @MainActor private func capture<Content: View>(_ name: String, width: CGFloat, height: CGFloat,
                                                  content: Content, style: UIUserInterfaceStyle = .light) async throws {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let previous = scene?.windows.first(where: \.isKeyWindow)
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
        window.frame = UIScreen.main.bounds; window.overrideUserInterfaceStyle = style
        let parent = UIViewController(), host = UIHostingController(rootView: content)
        host.overrideUserInterfaceStyle = style
        window.rootViewController = parent; window.makeKeyAndVisible()
        parent.addChild(host); parent.view.addSubview(host.view)
        host.view.frame = CGRect(x: 0, y: 0, width: width, height: height); host.didMove(toParent: parent)
        defer { window.isHidden = true; previous?.makeKey() }
        try await Task.sleep(nanoseconds: 350_000_000)
        host.view.layoutIfNeeded()
        XCTAssertEqual(host.view.bounds.width, width, accuracy: 1)
        XCTAssertEqual(host.traitCollection.userInterfaceStyle, style)
        let image = UIGraphicsImageRenderer(size: host.view.bounds.size).image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = "motionlab-\(name)"
        attachment.lifetime = .keepAlways; add(attachment)
    }
}
