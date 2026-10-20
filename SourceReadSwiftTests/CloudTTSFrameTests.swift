import XCTest
@testable import SourceReadSwift

final class CloudTTSFrameTests: XCTestCase {

    func testDecodesIntermediateFrameWithAudio() throws {
        let json = """
        {"code":0,"message":"success","sid":"s1","data":{"status":1,"audio":"YWI=","ced":"1"}}
        """
        let frame = try XunfeiTTSFrame.decode(Data(json.utf8))
        XCTAssertEqual(frame.code, 0)
        XCTAssertEqual(frame.data?.status, 1)
        XCTAssertFalse(frame.isFinal)
        XCTAssertEqual(frame.decodedAudio, Data([0x61, 0x62]))
    }

    func testDecodesFinalFrame() throws {
        let json = """
        {"code":0,"sid":"s2","data":{"status":2,"audio":"Y2Q="}}
        """
        let frame = try XunfeiTTSFrame.decode(Data(json.utf8))
        XCTAssertTrue(frame.isFinal)
        XCTAssertEqual(frame.decodedAudio, Data([0x63, 0x64]))
    }

    func testFinalFrameWithoutAudioYieldsNilChunk() throws {
        let json = """
        {"code":0,"data":{"status":2}}
        """
        let frame = try XunfeiTTSFrame.decode(Data(json.utf8))
        XCTAssertTrue(frame.isFinal)
        XCTAssertNil(frame.decodedAudio)
    }

    func testInvalidBase64YieldsNilAudio() throws {
        let json = """
        {"code":0,"data":{"status":1,"audio":"!!!not-base64!!!"}}
        """
        let frame = try XunfeiTTSFrame.decode(Data(json.utf8))
        XCTAssertNil(frame.decodedAudio)
    }

    func testInvalidJSONThrowsInvalidFrame() {
        XCTAssertThrowsError(try XunfeiTTSFrame.decode(Data("not json".utf8))) { error in
            XCTAssertEqual(error as? XunfeiTTSError, .invalidFrame)
        }
    }

    func testErrorCodeIsPreserved() throws {
        let json = """
        {"code":10105,"message":"illegal access","sid":"s3"}
        """
        let frame = try XunfeiTTSFrame.decode(Data(json.utf8))
        XCTAssertEqual(frame.code, 10105)
        XCTAssertEqual(frame.message, "illegal access")
        XCTAssertFalse(frame.isFinal)
    }
}
