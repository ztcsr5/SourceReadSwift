import XCTest
@testable import SourceReadSwift

final class ReaderSourceReviewTests: XCTestCase {
    func testRepeatedParagraphsKeepTheirOrdinalOnlyIfUnambiguous() throws {
        let link = ReaderSourceReview(url: try XCTUnwrap(URL(string: "https://example.invalid/talk")), isChapter: false, count: nil, paragraph: 3)
        let old = ["章名", "相同", "不同", "相同"]
        XCTAssertEqual(ReaderSourceReview.rebase([link], from: old, to: Array(old.dropFirst()))?.first?.paragraph, 2)
        XCTAssertNil(ReaderSourceReview.rebase([link], from: old, to: ["相同", "不同"]))
        for invalid in ["javascript:void(0)", "file:///tmp/review", "https://user:pass@example.invalid", "#", ""] {
            XCTAssertNil(ReaderSourceReview.webURL(invalid))
        }
    }

    func testEncodedChapterButtonDoesNotBecomeAnIllustration() throws {
        let base = try XCTUnwrap(URL(string: "https://example.invalid/read/1"))
        let raw = #"正文<img src='/button.svg' data-action='{&quot;click&quot;:&quot;showChapter(&apos;/reviews/1&apos;)&quot;}'/>"#
        let split = ReaderReviewMarkup.split(raw, base: base) { [$0] }
        XCTAssertEqual(split.text, ["正文"])
        let item = try XCTUnwrap(split.reviews?.first)
        XCTAssertTrue(item.isChapter); XCTAssertEqual(item.url.path, "/reviews/1")
        let inline = ReaderReviewMarkup.split(#"下一段<comment ident="/talk/4" count="12"/>"#, base: base) { [$0] }
        XCTAssertEqual(inline.text, ["下一段"]); XCTAssertEqual(inline.reviews?.first?.count, "12")
        XCTAssertEqual(inline.reviews?.first?.paragraph, 0)
    }

    func testRejectedEmptyWebAndNativeResponsesStayDistinct() {
        func response(_ body: String) -> ReaderReviewResponse { .decode(Data(body.utf8)) }
        guard case .rejected = response(#"{"code":401,"data":{"list":[]}}"#),
              case .comments(let empty) = response(#"{"code":0,"data":{"list":[]}}"#),
              case .website = response("<!DOCTYPE html><title>段评</title>"),
              case .rejected = response(#"{"data":[{"unrelated":1}]}"#),
              case .comments(let comments) = response(#"{"comments":[{"user":{"nickName":"纸间"},"text":"正文","likes":3}]}"#) else {
            return XCTFail("Unsupported, denied, web and empty responses must not be conflated")
        }
        XCTAssertTrue(empty.isEmpty)
        XCTAssertEqual(comments, [.init(author: "纸间", text: "正文", likes: 3)])
    }
}
