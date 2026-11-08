import UIKit
import WebKit
import XCTest
@testable import SourceReadSwift

final class ReaderScrollAnchorTests: XCTestCase {
    @MainActor func testChapterWindowChangesKeepTheSignedGapBeforeTheNextTitle() async throws {
        for operation in ["trim", "prepend"] {
            let outcome = try await replay("""
            const operation = '\(operation)';
            const heading = document.querySelector('[data-key="c2"] h2');
            const tail = document.querySelector('[data-key="c1"] [data-local="9"]');
            const gapTop = tail.getBoundingClientRect().bottom + window.scrollY;
            const gapBottom = heading.getBoundingClientRect().top + window.scrollY;
            window.scrollTo(0,(gapTop+gapBottom)/2-style.topInset-1);
            const before = heading.getBoundingClientRect().top;
            const paragraph = document.querySelector('[data-key="c1"] .para');
            const next = operation === 'trim' ? sections.slice(1).map(describe) :
                [{...chapter(-1),start:0,titleFlat:0,first:true,paragraphs:chapter(0).paragraphs},
                    ...sections.map((section,index)=>describe(section,index+1))];
            const accepted = reader.setContent({revision:'changed',baseRevision:'initial',
                total:operation==='trim' ? 21 : 43,sections:next});
            return {accepted,before,after:heading.getBoundingClientRect().top,gap:gapBottom-gapTop,
                sameParagraph:document.querySelector('[data-key="c1"] .para')===paragraph};
            """)
            XCTAssertEqual(outcome["accepted"] as? Bool, true, operation)
            XCTAssertEqual(outcome["sameParagraph"] as? Bool, true, operation)
            XCTAssertGreaterThan(try XCTUnwrap(outcome["gap"] as? Double), 20, operation)
            let before = try XCTUnwrap(outcome["before"] as? Double)
            let after = try XCTUnwrap(outcome["after"] as? Double)
            XCTAssertEqual(after, before, accuracy: 1, "\(operation) must preserve the reading point inside chapter spacing")
        }
    }

    @MainActor func testFontChangeRetainsTheVisibleParagraphFraction() async throws {
        let outcome = try await replay("""
        const paragraph = document.querySelector('[data-key="c1"] [data-local="4"]');
        const rect = paragraph.getBoundingClientRect();
        window.scrollTo(0,rect.top+window.scrollY+rect.height*0.45-style.topInset-1);
        const fraction = () => (style.topInset+1-paragraph.getBoundingClientRect().top)/
            paragraph.getBoundingClientRect().height;
        const before = fraction();
        const oldHeight = paragraph.getBoundingClientRect().height;
        reader.setStyle({...style,fontSize:28});
        return {before,after:fraction(),oldHeight,newHeight:paragraph.getBoundingClientRect().height};
        """)
        let oldHeight = try XCTUnwrap(outcome["oldHeight"] as? Double)
        let newHeight = try XCTUnwrap(outcome["newHeight"] as? Double)
        XCTAssertGreaterThan(newHeight, oldHeight)
        let before = try XCTUnwrap(outcome["before"] as? Double)
        let after = try XCTUnwrap(outcome["after"] as? Double)
        XCTAssertEqual(after, before, accuracy: 0.01, "Font resizing must retain relative progress inside prose")
    }

    @MainActor func testTailAppendAndPlaceholderResolutionLeaveExistingSectionsUntouched() async throws {
        let outcome = try await replay("""
        const mounted = sections.map(section=>document.querySelector('[data-key="'+section.key+'"]'));
        const observer = new MutationObserver(()=>{});
        for (const node of mounted) observer.observe(node,{attributes:true,childList:true,subtree:true});
        const pending = {...chapter(3),loading:true,paragraphs:[],sig:'pending'};
        const appended = reader.setContent({revision:'pending',baseRevision:'initial',total:33,
            sections:[...sections.map(describe),pending]});
        const appendMutations = observer.takeRecords().length;
        const resolved = reader.setContent({revision:'ready',baseRevision:'pending',total:43,
            sections:[...sections.map(describe),chapter(3)]});
        const resolutionMutations = observer.takeRecords().length;
        observer.disconnect();
        return {appended,resolved,appendMutations,resolutionMutations,
            sameNodes:mounted.every(node=>document.querySelector('[data-key="'+node.dataset.key+'"]')===node)};
        """)
        XCTAssertEqual(outcome["appended"] as? Bool, true)
        XCTAssertEqual(outcome["resolved"] as? Bool, true)
        XCTAssertEqual(outcome["sameNodes"] as? Bool, true)
        XCTAssertEqual(outcome["appendMutations"] as? Int, 0)
        XCTAssertEqual(outcome["resolutionMutations"] as? Int, 0)
    }

    @MainActor private func replay(_ script: String) async throws -> [String: Any] {
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let previous = scene?.windows.first(where: \.isKeyWindow)
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
        let host = UIViewController()
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.addSubview(web)
        defer { web.stopLoading(); window.isHidden = true; previous?.makeKey() }
        web.loadHTMLString(WebReaderHTML.shell, baseURL: nil)
        var isReady = false
        for _ in 0..<100 {
            isReady = (try? await web.evaluateJavaScript("!!window.__reader")) as? Bool == true
            if isReady { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertTrue(isReady, "The production reader shell must finish before testing its layout")
        let outcome = try await web.evaluateJavaScript("(() => {" + Self.fixture + script + "})()")
        return try XCTUnwrap(outcome as? [String: Any])
    }

    private static let fixture = """
    const reader = window.__reader;
    const style = {fontFamily:'sans-serif',fontWeight:400,fontSize:20,lineHeight:1.4,
        letterSpacing:0,paragraphSpacing:12,paragraphIndent:40,sidePadding:20,topInset:50,
        bottomInset:24,titleSize:26,titleSpacing:16,textColor:'#000',surfaceColor:'#fff',
        highlightColor:'#ff0',accentColor:'#66c',selectable:false};
    reader.setStyle(style);
    const chapter = index => ({key:'c'+index,chapter:index,title:'章节 '+index,sig:'s'+index,
        start:index*11,titleFlat:index ? index*11-1 : 0,first:index===0,
        paragraphs:Array.from({length:10},(_,local)=>({flat:index*11+local,local,
            text:'窗外的风穿过树梢。'.repeat(10)}))});
    const sections = [0,1,2].map(chapter);
    reader.setContent({revision:'initial',total:32,sections});
    const describe = (section,index) => ({key:section.key,sig:section.sig,reuse:true,
        first:index===0,start:index*11,titleFlat:index ? index*11-1 : 0});
    """
}
