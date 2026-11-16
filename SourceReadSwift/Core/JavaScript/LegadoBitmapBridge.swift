import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Bounded, runtime-local Android bitmap operations used by source imageDecode scripts.
final class LegadoBitmapBridge {
    struct Limits {
        var maximumEncodedBytes = ComicOfflineArchive.maximumPageBytes
        var maximumImagePixels = 8 * 1024 * 1024
        var maximumRetainedPixels = 16 * 1024 * 1024
        var maximumDimension = 32_768
        var maximumSurfaces = 8
    }

    enum Failure: String, Error, Sendable {
        case mainThread = "bitmap-work-requires-background-thread"
        case invalidArgument = "invalid-bitmap-argument"
        case invalidImage = "invalid-image-bytes"
        case encodedByteLimit = "bitmap-encoded-byte-limit"
        case pixelLimit = "bitmap-pixel-memory-limit"
        case surfaceLimit = "bitmap-surface-limit"
        case unknownSurface = "unknown-bitmap-handle"
        case immutableSurface = "bitmap-is-immutable"
        case unsupportedConfig = "unsupported-bitmap-config"
        case unsupportedFormat = "unsupported-bitmap-format"
        case unsupportedPixelFormat = "unsupported-bitmap-pixel-format"
        case allocation = "bitmap-allocation-failed"
        case encoding = "bitmap-png-encoding-failed"
        case unsupportedOperation = "unsupported-bitmap-operation"
    }

    struct Descriptor: Sendable {
        let id: String
        let width: Int
        let height: Int
        var object: [String: Any] { ["id": id, "width": width, "height": height] }
    }

    private struct Surface {
        let descriptor: Descriptor
        let bitmap: CGImage?
        let canvas: CGContext?
    }

    private let limits: Limits
    private var surfaces: [String: Surface] = [:]
    private var retainedPixels = 0

    init(limits: Limits = Limits()) { self.limits = limits }

    /// Returns a scalar JSON envelope so older JavaScriptCore runtimes never bridge byte arrays.
    func invoke(_ arguments: [Any]) -> String {
        do {
            let value = try dispatch(arguments)
            let encoded = try JSONSerialization.data(withJSONObject: ["ok": true, "value": value])
            return String(decoding: encoded, as: UTF8.self)
        } catch let failure as Failure {
            return "{\"ok\":false,\"error\":\"\(failure.rawValue)\"}"
        } catch {
            return "{\"ok\":false,\"error\":\"bitmap-result-encoding-failed\"}"
        }
    }

    func decode(_ bytes: Data, offset: Int, length: Int) throws -> Descriptor {
        try requireBackgroundThread()
        guard bytes.count <= limits.maximumEncodedBytes else { throw Failure.encodedByteLimit }
        guard offset >= 0, length > 0, offset <= bytes.count, length <= bytes.count - offset else {
            throw Failure.invalidArgument
        }
        let slice = bytes.subdata(in: offset..<(offset + length))
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(slice as CFData, options),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue else {
            throw Failure.invalidImage
        }
        try checkAllocation(width: width, height: height)
        if let depth = (properties[kCGImagePropertyDepth] as? NSNumber)?.intValue, depth > 8 {
            throw Failure.unsupportedPixelFormat
        }
        // Read dimensions before allocating pixels; compressed image size is not a memory bound.
        guard let bitmap = CGImageSourceCreateImageAtIndex(source, 0, options),
              bitmap.width == width, bitmap.height == height else { throw Failure.invalidImage }
        guard bitmap.bitsPerComponent <= 8, bitmap.bitsPerPixel <= 32,
              bitmap.bytesPerRow <= Int.max / height else { throw Failure.unsupportedPixelFormat }
        let reservedPixels = max(width * height, (bitmap.bytesPerRow * height + 3) / 4)
        guard reservedPixels <= limits.maximumRetainedPixels - retainedPixels else { throw Failure.pixelLimit }
        let descriptor = Descriptor(id: UUID().uuidString, width: width, height: height)
        surfaces[descriptor.id] = Surface(descriptor: descriptor, bitmap: bitmap, canvas: nil)
        retainedPixels += reservedPixels
        return descriptor
    }

    func create(width: Int, height: Int, config: String) throws -> Descriptor {
        try requireBackgroundThread()
        guard config == "ARGB_8888" else { throw Failure.unsupportedConfig }
        try checkAllocation(width: width, height: height)
        guard let canvas = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw Failure.allocation }
        canvas.clear(CGRect(x: 0, y: 0, width: width, height: height))
        let descriptor = Descriptor(id: UUID().uuidString, width: width, height: height)
        surfaces[descriptor.id] = Surface(descriptor: descriptor, bitmap: nil, canvas: canvas)
        retainedPixels += width * height
        return descriptor
    }

    func draw(_ sourceID: String, into destinationID: String, matrix: [Double]) throws {
        try requireBackgroundThread()
        guard matrix.count == 6, matrix.allSatisfy({ $0.isFinite && abs($0) <= 1_000_000 }) else {
            throw Failure.invalidArgument
        }
        let source = try surface(sourceID)
        let target = try surface(destinationID)
        guard let canvas = target.canvas else { throw Failure.immutableSurface }
        guard let bitmap = source.bitmap ?? source.canvas?.makeImage() else { throw Failure.invalidImage }
        let transform = CGAffineTransform(a: matrix[0], b: matrix[1], c: matrix[2], d: matrix[3], tx: matrix[4], ty: matrix[5])
        canvas.saveGState()
        defer { canvas.restoreGState() }
        canvas.interpolationQuality = .none
        // Android maps top-left image coordinates. Convert both destination and source
        // axes around its matrix so a +90 degree turn stays clockwise without mirroring.
        canvas.translateBy(x: 0, y: CGFloat(target.descriptor.height))
        canvas.scaleBy(x: 1, y: -1)
        canvas.concatenate(transform)
        canvas.translateBy(x: 0, y: CGFloat(source.descriptor.height))
        canvas.scaleBy(x: 1, y: -1)
        canvas.draw(bitmap, in: CGRect(x: 0, y: 0, width: source.descriptor.width, height: source.descriptor.height))
    }

    func compress(_ identifier: String, format: String, quality: Int) throws -> Data {
        try requireBackgroundThread()
        guard format == "PNG" else { throw Failure.unsupportedFormat }
        guard (0...100).contains(quality) else { throw Failure.invalidArgument }
        let surface = try surface(identifier)
        guard let bitmap = surface.bitmap ?? surface.canvas?.makeImage() else { throw Failure.invalidImage }
        let encoded = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(encoded, UTType.png.identifier as CFString, 1, nil) else {
            throw Failure.encoding
        }
        // Android ignores quality for PNG; keep bitmap dimensions and the alpha channel.
        CGImageDestinationAddImage(destination, bitmap, nil)
        guard CGImageDestinationFinalize(destination) else { throw Failure.encoding }
        guard encoded.length <= limits.maximumEncodedBytes else { throw Failure.encodedByteLimit }
        return encoded as Data
    }

    private func dispatch(_ arguments: [Any]) throws -> Any {
        try requireBackgroundThread()
        guard let operation = arguments.first as? String else { throw Failure.invalidArgument }
        switch operation {
        case "decode":
            guard arguments.count == 4, let base64 = arguments[1] as? String,
                  base64.utf8.count <= limits.maximumEncodedBytes * 4 / 3 + 8 else { throw Failure.encodedByteLimit }
            guard let bytes = Data(base64Encoded: base64) else { throw Failure.invalidImage }
            return try decode(bytes, offset: integer(arguments[2]), length: integer(arguments[3])).object
        case "create":
            guard arguments.count == 4, let config = arguments[3] as? String else { throw Failure.invalidArgument }
            return try create(width: integer(arguments[1]), height: integer(arguments[2]), config: config).object
        case "draw":
            guard arguments.count == 4, let source = arguments[1] as? String,
                  let destination = arguments[2] as? String, let coefficients = arguments[3] as? [NSNumber] else {
                throw Failure.invalidArgument
            }
            try draw(source, into: destination, matrix: coefficients.map(\.doubleValue))
            return true
        case "compress":
            guard arguments.count == 4, let identifier = arguments[1] as? String,
                  let format = arguments[2] as? String else { throw Failure.invalidArgument }
            return try compress(identifier, format: format, quality: integer(arguments[3])).base64EncodedString()
        default:
            throw Failure.unsupportedOperation
        }
    }

    private func checkAllocation(width: Int, height: Int) throws {
        guard width > 0, height > 0 else { throw Failure.invalidArgument }
        guard width <= limits.maximumDimension, height <= limits.maximumDimension,
              width <= limits.maximumImagePixels / height else { throw Failure.pixelLimit }
        let pixels = width * height
        guard pixels <= limits.maximumRetainedPixels - retainedPixels else { throw Failure.pixelLimit }
        guard surfaces.count < limits.maximumSurfaces else { throw Failure.surfaceLimit }
    }

    private func surface(_ identifier: String) throws -> Surface {
        guard let surface = surfaces[identifier] else { throw Failure.unknownSurface }
        return surface
    }

    private func requireBackgroundThread() throws {
        guard !Thread.isMainThread else { throw Failure.mainThread }
    }

    private func integer(_ value: Any) throws -> Int {
        guard let number = value as? NSNumber else { throw Failure.invalidArgument }
        let scalar = number.doubleValue
        guard scalar.isFinite, scalar.rounded(.towardZero) == scalar,
              scalar >= Double(Int.min), scalar < Double(Int.max) else { throw Failure.invalidArgument }
        return Int(scalar)
    }
}

extension LegadoBitmapBridge {
    /// Only the bitmap operations observed in byte imageDecode hooks are exposed.
    static let compatibilityPrelude = """
    (function() {
      function command(operation, values) {
        var reply = JSON.parse(String(__nativeLegado.invoke({ method: 'bitmap', args: [operation].concat(values) })));
        if (!reply || reply.ok !== true) throw new Error('android.graphics: ' + (reply && reply.error || 'invalid-native-result'));
        return reply.value;
      }
      function finite(value) {
        var number = Number(value);
        if (!isFinite(number)) throw new Error('android.graphics: invalid-matrix-number');
        return number;
      }
      function Bitmap(description) {
        if (!description || !description.id) throw new Error('android.graphics: invalid-bitmap-handle');
        this.__bitmapID = description.id;
        this.getWidth = function() { return description.width; };
        this.getHeight = function() { return description.height; };
        this.compress = function(format, quality, stream) {
          if (!stream || typeof stream.write !== 'function') throw new Error('android.graphics: invalid-output-stream');
          var encoded = command('compress', [description.id, String(format), Number(quality)]);
          stream.write(java.base64DecodeToByteArray(encoded));
          return true;
        };
      }
      Bitmap.__javaSimpleName = 'Bitmap';
      Bitmap.Config = { ARGB_8888: 'ARGB_8888' };
      Bitmap.CompressFormat = { PNG: 'PNG' };
      Bitmap.createBitmap = function(width, height, config) {
        if (arguments.length !== 3) throw new Error('android.graphics: unsupported-createBitmap-overload');
        return new Bitmap(command('create', [Number(width), Number(height), String(config)]));
      };
      var BitmapFactory = {
        __javaSimpleName: 'BitmapFactory',
        decodeByteArray: function(bytes, offset, length) {
          if (arguments.length !== 3 || !bytes || typeof bytes.length !== 'number')
            throw new Error('android.graphics: unsupported-decodeByteArray-arguments');
          if (bytes.length > \(ComicOfflineArchive.maximumPageBytes)) throw new Error('android.graphics: bitmap-encoded-byte-limit');
          return new Bitmap(command('decode', [java.base64Encode(bytes), Number(offset), Number(length)]));
        }
      };
      function Matrix() {
        this.__coefficients = [1, 0, 0, 1, 0, 0];
      }
      Matrix.__javaSimpleName = 'Matrix';
      Matrix.prototype.setRotate = function(degrees) {
        if (arguments.length !== 1) throw new Error('android.graphics: unsupported-setRotate-overload');
        var radians = (finite(degrees) % 360) * Math.PI / 180;
        var cosine = Math.cos(radians), sine = Math.sin(radians);
        if (Math.abs(cosine) < 1e-12) cosine = 0;
        if (Math.abs(sine) < 1e-12) sine = 0;
        this.__coefficients = [cosine, sine, -sine, cosine, 0, 0];
      };
      Matrix.prototype.postTranslate = function(dx, dy) {
        this.__coefficients[4] += finite(dx);
        this.__coefficients[5] += finite(dy);
        return true;
      };
      function Canvas(target) {
        if (!target || !target.__bitmapID) throw new Error('android.graphics: invalid-canvas-bitmap');
        this.drawBitmap = function(bitmap, matrix, paint) {
          if (!bitmap || !bitmap.__bitmapID || !matrix || !matrix.__coefficients || paint != null)
            throw new Error('android.graphics: unsupported-drawBitmap-arguments');
          command('draw', [bitmap.__bitmapID, target.__bitmapID, matrix.__coefficients]);
        };
      }
      Canvas.__javaSimpleName = 'Canvas';
      Packages.android.graphics = { BitmapFactory: BitmapFactory, Bitmap: Bitmap, Matrix: Matrix, Canvas: Canvas };
      android.graphics = Packages.android.graphics;
    })();
    """
}
