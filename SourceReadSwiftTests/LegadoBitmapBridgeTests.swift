import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import SourceReadSwift

final class LegadoBitmapBridgeTests: XCTestCase {
    func testImageDecodeRotatesPanoramaClockwiseWithoutStretchingPixels() async throws {
        let original = try makePNG(width: 10, height: 2)
        let output = try await decode(original).get()
        let bitmap = try readPixels(output)
        XCTAssertEqual(bitmap.width, 2)
        XCTAssertEqual(bitmap.height, 10)
        for y in 0..<bitmap.height {
            for x in 0..<bitmap.width {
                XCTAssertEqual(bitmap.pixel(x, y), fixturePixel(x: y, y: 1 - x))
            }
        }
    }

    func testImageDecodeKeepsOriginalBytesWhenRotationConditionDoesNotMatch() async throws {
        let original = try makePNG(width: 4, height: 2)
        let output = try await decode(original).get()
        XCTAssertEqual(output, original, "An ordinary page must not be recompressed or resized")
    }

    func testDecodeByteArrayHonorsOffsetAndLength() async throws {
        let png = try makePNG(width: 3, height: 2)
        let padded = Data([0, 1, 2]) + png + Data([3, 4])
        let descriptor = try await Task.detached {
            try LegadoBitmapBridge().decode(padded, offset: 3, length: png.count)
        }.value
        XCTAssertEqual(descriptor.width, 3)
        XCTAssertEqual(descriptor.height, 2)
    }

    func testInvalidBytesAndOffsetsFailExplicitly() async throws {
        let failures = await Task.detached {
            let bridge = LegadoBitmapBridge()
            return [
                self.failure { _ = try bridge.decode(Data([1, 2, 3]), offset: 0, length: 3) },
                self.failure { _ = try bridge.decode(Data([1]), offset: -1, length: 1) },
                self.failure { _ = try bridge.decode(Data([1]), offset: 0, length: Int.max) }
            ]
        }.value
        XCTAssertEqual(failures, [.invalidImage, .invalidArgument, .invalidArgument])
    }

    func testCompressedAndDecodedImageBudgetsFailBeforeSurfaceAllocation() async throws {
        let png = try makePNG(width: 3, height: 2)
        let failures = await Task.detached {
            let encoded = LegadoBitmapBridge(limits: .init(maximumEncodedBytes: 2))
            let pixels = LegadoBitmapBridge(limits: .init(maximumImagePixels: 4))
            return [
                self.failure { _ = try encoded.decode(png, offset: 0, length: png.count) },
                self.failure { _ = try pixels.decode(png, offset: 0, length: png.count) },
                self.failure { _ = try pixels.create(width: Int.max, height: Int.max, config: "ARGB_8888") }
            ]
        }.value
        XCTAssertEqual(failures, [.encodedByteLimit, .pixelLimit, .pixelLimit])
    }

    func testCombinedSurfaceBudgetAndHandleLimitCannotBeBypassed() async throws {
        let failures = try await Task.detached {
            let pixels = LegadoBitmapBridge(limits: .init(maximumRetainedPixels: 6))
            _ = try pixels.create(width: 2, height: 2, config: "ARGB_8888")
            let handles = LegadoBitmapBridge(limits: .init(maximumSurfaces: 1))
            _ = try handles.create(width: 1, height: 1, config: "ARGB_8888")
            return [
                self.failure { _ = try pixels.create(width: 2, height: 2, config: "ARGB_8888") },
                self.failure { _ = try handles.create(width: 1, height: 1, config: "ARGB_8888") }
            ]
        }.value
        XCTAssertEqual(failures, [.pixelLimit, .surfaceLimit])
    }

    func testInvalidMatrixAndUnsupportedFormatDoNotProduceSuccessfulImages() async throws {
        let failures = try await Task.detached {
            let bridge = LegadoBitmapBridge()
            let source = try bridge.create(width: 2, height: 2, config: "ARGB_8888")
            let target = try bridge.create(width: 2, height: 2, config: "ARGB_8888")
            return [
                self.failure { try bridge.draw(source.id, into: target.id, matrix: [1, 0, 0, 1, .nan, 0]) },
                self.failure { _ = try bridge.compress(target.id, format: "JPEG", quality: 100) },
                self.failure { _ = try bridge.create(width: 2, height: 2, config: "RGB_565") }
            ]
        }.value
        XCTAssertEqual(failures, [.invalidArgument, .unsupportedFormat, .unsupportedConfig])
    }

    @MainActor
    func testBitmapWorkRejectsMainThread() {
        let bridge = LegadoBitmapBridge()
        XCTAssertThrowsError(try bridge.create(width: 1, height: 1, config: "ARGB_8888")) { error in
            XCTAssertEqual(error as? LegadoBitmapBridge.Failure, .mainThread)
        }
    }

    private func decode(_ bytes: Data) async -> Result<Data, ComicImageFailure> {
        let source = BookSource(bookSourceName: "Bitmap fixture", bookSourceUrl: "https://bitmap.fixture.invalid",
            bookSourceType: 2, ruleContent: .init(fields: ["imageDecode": Self.rotationRule]))
        let chapter = BookChapter(title: "Fixture", url: "https://bitmap.fixture.invalid/chapter",
            bookUrl: "https://bitmap.fixture.invalid/book", index: 0)
        guard let context = SourceImageDecodeContext(source: source, chapter: chapter) else { return .failure(.imageDecodeFailed) }
        return await SourceImageByteDecoder.decode(bytes, sourceURL: URL(string: "https://bitmap.fixture.invalid/page.png")!, context: context)
    }

    // Synthetic API fixture: it carries no publisher source, URLs or credentials.
    private static let rotationRule = """
    (function(bytes) {
      var classes = new JavaImporter(Packages.android.graphics, Packages.java.io);
      with (classes) {
        var picture = BitmapFactory.decodeByteArray(bytes, 0, bytes.length);
        if (picture.getWidth() <= picture.getHeight() * 4.5) return bytes;
        var destination = Bitmap.createBitmap(picture.getHeight(), picture.getWidth(), Bitmap.Config.ARGB_8888);
        var transform = new Matrix();
        transform.setRotate(90);
        transform.postTranslate(destination.getWidth(), 0);
        new Canvas(destination).drawBitmap(picture, transform, null);
        var encoded = new ByteArrayOutputStream();
        if (!destination.compress(Bitmap.CompressFormat.PNG, 100, encoded)) throw new Error('PNG encoding failed');
        return encoded.toByteArray();
      }
    })(result)
    """

    private func failure(_ operation: () throws -> Void) -> LegadoBitmapBridge.Failure? {
        do { try operation(); return nil }
        catch { return error as? LegadoBitmapBridge.Failure }
    }

    private func fixturePixel(x: Int, y: Int) -> [UInt8] {
        [UInt8(20 + x * 10), UInt8(30 + y * 60), UInt8(80 + x * 3 + y * 7), 255]
    }

    private func makePNG(width: Int, height: Int) throws -> Data {
        let pixels = (0..<height).flatMap { y in (0..<width).flatMap { fixturePixel(x: $0, y: y) } }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
        let bitmap = try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let encoded = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(encoded, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, bitmap, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return encoded as Data
    }

    private struct Pixels {
        let width: Int
        let height: Int
        let bytes: [UInt8]
        func pixel(_ x: Int, _ y: Int) -> [UInt8] {
            Array(bytes[((y * width + x) * 4)..<((y * width + x) * 4 + 4)])
        }
    }

    private func readPixels(_ bytes: Data) throws -> Pixels {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(bytes as CFData, nil))
        let bitmap = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let context = try XCTUnwrap(CGContext(data: nil, width: bitmap.width, height: bitmap.height, bitsPerComponent: 8,
            bytesPerRow: bitmap.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(bitmap, in: CGRect(x: 0, y: 0, width: bitmap.width, height: bitmap.height))
        let pointer = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        return Pixels(width: bitmap.width, height: bitmap.height,
            bytes: Array(UnsafeBufferPointer(start: pointer, count: bitmap.width * bitmap.height * 4)))
    }
}
