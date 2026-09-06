import Foundation

/// Minimal, bounds-checked TrueType/OpenType reader used by Legado's
/// `java.queryTTF` anti-crawl helper.  Legado only needs the cmap/loca/glyf
/// tables and a stable glyph fingerprint; this reader intentionally avoids
/// registering fonts or exposing arbitrary file access.
final class QueryTTF {
    private struct Table {
        let offset: Int
        let length: Int
    }

    private struct Glyph {
        let contours: Int
        let simple: SimpleGlyph?
        let components: [Component]
    }

    private struct SimpleGlyph {
        let flags: [UInt8]
        let x: [Int]
        let y: [Int]
    }

    private struct Component {
        let flags: UInt16
        let glyphIndex: Int
        let arg1: Int
        let arg2: Int
        let xScale: Double
        let scale01: Double
        let scale10: Double
        let yScale: Double
    }

    private let data: Data
    private var tables: [String: Table] = [:]
    private var unitsPerEm = 0
    private var indexToLocFormat = 0
    private var numGlyphs = 0
    private var maxContours = Int.max
    private var loca: [Int] = []
    private var glyphs: [Glyph?] = []
    private(set) var unicodeToGlyphId: [Int: Int] = [:]
    private(set) var unicodeToGlyph: [Int: String] = [:]
    private(set) var glyphToUnicode: [String: Int] = [:]

    init(data: Data) {
        self.data = data
        parse()
    }

    /// Glyph index for a Unicode scalar.  Legado returns zero for a miss.
    func getGlyfIdByUnicode(_ unicode: Int) -> Int {
        unicodeToGlyphId[unicode] ?? 0
    }

    /// A deterministic outline/fingerprint string matching the Flutter/Dart
    /// QueryTTF port: simple glyphs are delta coordinate pairs and composites
    /// are a compact component description.
    func getGlyfByUnicode(_ unicode: Int) -> String {
        guard let glyphID = unicodeToGlyphId[unicode] else { return "" }
        return glyphString(for: glyphID) ?? ""
    }

    /// Reverse lookup for a fingerprint.  Zero is the Android/Legado miss
    /// value (and is also the .notdef glyph index).
    func getUnicodeByGlyf(_ glyph: String) -> Int {
        glyphToUnicode[glyph] ?? 0
    }

    func isBlankUnicode(_ unicode: Int) -> Bool {
        switch unicode {
        case 0x0009, 0x0020, 0x00A0, 0x2002, 0x2003, 0x2007,
             0x200A, 0x200B, 0x200C, 0x200D, 0x202F, 0x205F:
            return true
        default:
            return false
        }
    }

    private func parse() {
        guard let numTables = readU16(4), data.count >= 12,
              numTables > 0,
              data.count >= 12 + Int(numTables) * 16 else { return }
        for index in 0..<Int(numTables) {
            let base = 12 + index * 16
            guard let tagData = readData(base, count: 4),
                  let tag = String(data: tagData, encoding: .ascii),
                  let offset = readU32(base + 8),
                  let length = readU32(base + 12),
                  Int(offset) <= data.count,
                  Int(length) <= data.count - Int(offset) else { continue }
            tables[tag] = Table(offset: Int(offset), length: Int(length))
        }
        readHead()
        readMaxp()
        readCmap()
        readLoca()
        readGlyf()
        for (unicode, glyphID) in unicodeToGlyphId {
            guard let fingerprint = glyphString(for: glyphID) else { continue }
            unicodeToGlyph[unicode] = fingerprint
            if glyphToUnicode[fingerprint] == nil { glyphToUnicode[fingerprint] = unicode }
        }
    }

    private func readHead() {
        guard let table = tables["head"], table.length >= 52,
              let units = readU16(table.offset + 18),
              let format = readI16(table.offset + 50) else { return }
        unitsPerEm = Int(units)
        indexToLocFormat = Int(format)
    }

    private func readMaxp() {
        guard let table = tables["maxp"], table.length >= 6,
              let count = readU16(table.offset + 4) else { return }
        numGlyphs = Int(count)
        // maxp version 1.0 places maxPoints at +6 and maxContours at +8.
        if table.length >= 10, let contours = readU16(table.offset + 8) {
            maxContours = Int(contours)
        }
    }

    private func readCmap() {
        guard let table = tables["cmap"], table.length >= 4,
              let count = readU16(table.offset + 2) else { return }
        var records: [(platform: Int, encoding: Int, offset: Int)] = []
        for index in 0..<Int(count) {
            let base = table.offset + 4 + index * 8
            guard base + 8 <= table.offset + table.length,
                  let platform = readU16(base),
                  let encoding = readU16(base + 2),
                  let offset = readU32(base + 4) else { continue }
            records.append((Int(platform), Int(encoding), Int(offset)))
        }
        // Prefer Unicode/full repertoire, then Windows Unicode BMP, then
        // legacy Mac/Windows records.  Do not parse the same subtable twice.
        let ordered = records.sorted { lhs, rhs in
            cmapPriority(lhs.platform, lhs.encoding) < cmapPriority(rhs.platform, rhs.encoding)
        }
        var seen = Set<Int>()
        for record in ordered {
            guard seen.insert(record.offset).inserted,
                  record.offset >= 0,
                  record.offset <= table.length - 2 else { continue }
            let base = table.offset + record.offset
            guard let format = readU16(base) else { continue }
            switch format {
            case 0: parseCmap0(base: base, table: table)
            case 4: parseCmap4(base: base, table: table)
            case 6: parseCmap6(base: base, table: table)
            default: continue
            }
        }
    }

    private func cmapPriority(_ platform: Int, _ encoding: Int) -> Int {
        switch (platform, encoding) {
        case (3, 10): return 0
        case (0, 4): return 1
        case (3, 1): return 2
        case (1, 0): return 3
        case (0, 3): return 4
        case (0, 1): return 5
        default: return 10
        }
    }

    private func parseCmap0(base: Int, table: Table) {
        guard let length = readU16(base + 2), Int(length) >= 262,
              base + Int(length) <= table.offset + table.length else { return }
        for unicode in 0..<256 {
            guard let glyph = readU8(base + 6 + unicode), glyph != 0 else { continue }
            unicodeToGlyphId[unicode] = Int(glyph)
        }
    }

    private func parseCmap6(base: Int, table: Table) {
        guard let length = readU16(base + 2), let first = readU16(base + 6),
              let count = readU16(base + 8),
              Int(length) >= 10 + Int(count) * 2,
              base + Int(length) <= table.offset + table.length else { return }
        for index in 0..<Int(count) {
            guard let glyph = readU16(base + 10 + index * 2), glyph != 0 else { continue }
            unicodeToGlyphId[Int(first) + index] = Int(glyph)
        }
    }

    private func parseCmap4(base: Int, table: Table) {
        guard let length = readU16(base + 2), let segCountX2 = readU16(base + 6),
              Int(length) >= 16, segCountX2 % 2 == 0 else { return }
        let segCount = Int(segCountX2 / 2)
        let endStart = base + 14
        let startStart = endStart + segCount * 2 + 2
        let deltaStart = startStart + segCount * 2
        let rangeStart = deltaStart + segCount * 2
        let glyphArrayStart = rangeStart + segCount * 2
        guard glyphArrayStart <= base + Int(length),
              rangeStart + segCount * 2 <= base + Int(length) else { return }
        var endCodes: [Int] = []
        var starts: [Int] = []
        var deltas: [Int] = []
        var ranges: [Int] = []
        for index in 0..<segCount {
            guard let end = readU16(endStart + index * 2),
                  let start = readU16(startStart + index * 2),
                  let delta = readI16(deltaStart + index * 2),
                  let range = readU16(rangeStart + index * 2) else { return }
            endCodes.append(Int(end)); starts.append(Int(start)); deltas.append(Int(delta)); ranges.append(Int(range))
        }
        for segment in 0..<segCount {
            let first = starts[segment]
            let last = min(endCodes[segment], 0xFFFF)
            guard first <= last else { continue }
            for unicode in first...last where unicode != 0xFFFF {
                var glyphID = 0
                if ranges[segment] == 0 {
                    glyphID = (unicode + deltas[segment]) & 0xFFFF
                } else {
                    // idRangeOffset is measured from the location of its own
                    // word.  Compute the target directly and bounds-check it.
                    let target = rangeStart + segment * 2 + ranges[segment] + (unicode - first) * 2
                    guard target + 2 <= base + Int(length), let raw = readU16(target) else { continue }
                    glyphID = raw == 0 ? 0 : (Int(raw) + deltas[segment]) & 0xFFFF
                }
                if glyphID != 0 { unicodeToGlyphId[unicode] = glyphID }
            }
        }
    }

    private func readLoca() {
        guard let table = tables["loca"], numGlyphs > 0 else { return }
        let count = indexToLocFormat == 0 ? table.length / 2 : table.length / 4
        guard count > 0 else { return }
        loca = (0..<count).compactMap { index in
            if indexToLocFormat == 0 { return readU16(table.offset + index * 2).map { Int($0) * 2 } }
            return readI32(table.offset + index * 4).map { max(0, Int($0)) }
        }
    }

    private func readGlyf() {
        guard let table = tables["glyf"], numGlyphs > 0 else { return }
        glyphs = Array(repeating: nil, count: numGlyphs)
        guard loca.count >= 2 else { return }
        for index in 0..<numGlyphs {
            guard index + 1 < loca.count else { break }
            let start = loca[index], end = loca[index + 1]
            guard end > start, start >= 0, end <= table.length,
                  let contours = readI16(table.offset + start),
                  start + 10 <= end else { continue }
            if Int(contours) > maxContours { continue }
            let body = table.offset + start
            if contours > 0 {
                guard let simple = parseSimpleGlyph(base: body + 10, contours: Int(contours), end: table.offset + end) else { continue }
                glyphs[index] = Glyph(contours: Int(contours), simple: simple, components: [])
            } else if contours < 0 {
                let components = parseComponents(base: body + 10, end: table.offset + end)
                glyphs[index] = Glyph(contours: Int(contours), simple: nil, components: components)
            } else {
                glyphs[index] = Glyph(contours: 0, simple: nil, components: [])
            }
        }
    }

    private func parseSimpleGlyph(base: Int, contours: Int, end: Int) -> SimpleGlyph? {
        guard contours > 0, base + contours * 2 + 2 <= end else { return nil }
        var endPoints: [Int] = []
        for index in 0..<contours {
            guard let value = readU16(base + index * 2) else { return nil }
            endPoints.append(Int(value))
        }
        guard let instructionLength = readU16(base + contours * 2),
              base + contours * 2 + 2 + Int(instructionLength) <= end else { return nil }
        var cursor = base + contours * 2 + 2 + Int(instructionLength)
        let pointCount = (endPoints.last ?? -1) + 1
        guard pointCount > 0 else { return nil }
        var flags: [UInt8] = []
        flags.reserveCapacity(pointCount)
        while flags.count < pointCount, cursor < end {
            guard let flag = readU8(cursor) else { return nil }
            cursor += 1; flags.append(flag)
            if flag & 0x08 != 0 {
                guard let repeatCount = readU8(cursor) else { return nil }
                cursor += 1
                for _ in 0..<Int(repeatCount) where flags.count < pointCount { flags.append(flag) }
            }
        }
        guard flags.count == pointCount else { return nil }
        var x: [Int] = []; x.reserveCapacity(pointCount)
        var y: [Int] = []; y.reserveCapacity(pointCount)
        for flag in flags {
            let delta: Int
            if flag & 0x02 != 0 {
                guard let value = readU8(cursor) else { return nil }; cursor += 1
                delta = flag & 0x10 != 0 ? Int(value) : -Int(value)
            } else if flag & 0x10 != 0 { delta = 0 }
            else { guard let value = readI16(cursor) else { return nil }; cursor += 2; delta = Int(value) }
            // Legado's QueryTTF returns the encoded coordinate deltas rather
            // than accumulated absolute points.  This matters for obfuscated
            // fonts where the fingerprint is compared byte-for-byte.
            x.append(delta)
        }
        for flag in flags {
            let delta: Int
            if flag & 0x04 != 0 {
                guard let value = readU8(cursor) else { return nil }; cursor += 1
                delta = flag & 0x20 != 0 ? Int(value) : -Int(value)
            } else if flag & 0x20 != 0 { delta = 0 }
            else { guard let value = readI16(cursor) else { return nil }; cursor += 2; delta = Int(value) }
            y.append(delta)
        }
        return SimpleGlyph(flags: flags, x: x, y: y)
    }

    private func parseComponents(base: Int, end: Int) -> [Component] {
        var cursor = base
        var output: [Component] = []
        while cursor + 4 <= end {
            guard let flags = readU16(cursor), let glyphIndex = readU16(cursor + 2) else { break }
            cursor += 4
            let argWords = flags & 0x0001 != 0
            let argsAreXY = flags & 0x0002 != 0
            let arg1: Int, arg2: Int
            if argWords {
                guard cursor + 4 <= end else { break }
                arg1 = argsAreXY ? Int(readI16(cursor) ?? 0) : Int(readU16(cursor) ?? 0)
                arg2 = argsAreXY ? Int(readI16(cursor + 2) ?? 0) : Int(readU16(cursor + 2) ?? 0)
                cursor += 4
            } else {
                guard cursor + 2 <= end else { break }
                arg1 = argsAreXY ? Int(Int8(bitPattern: readU8(cursor) ?? 0)) : Int(readU8(cursor) ?? 0)
                arg2 = argsAreXY ? Int(Int8(bitPattern: readU8(cursor + 1) ?? 0)) : Int(readU8(cursor + 1) ?? 0)
                cursor += 2
            }
            var xScale = 1.0, scale01 = 0.0, scale10 = 0.0, yScale = 1.0
            switch flags & 0x00C8 {
            case 0x0008:
                guard cursor + 2 <= end, let value = readU16(cursor) else { break }
                xScale = Double(value) / 16384.0; yScale = xScale; cursor += 2
            case 0x0040:
                guard cursor + 4 <= end, let xValue = readU16(cursor), let yValue = readU16(cursor + 2) else { break }
                xScale = Double(xValue) / 16384.0; yScale = Double(yValue) / 16384.0; cursor += 4
            case 0x0080:
                guard cursor + 8 <= end,
                      let xValue = readU16(cursor), let s01Value = readU16(cursor + 2),
                      let s10Value = readU16(cursor + 4), let yValue = readU16(cursor + 6) else { break }
                xScale = Double(xValue) / 16384.0; scale01 = Double(s01Value) / 16384.0
                scale10 = Double(s10Value) / 16384.0; yScale = Double(yValue) / 16384.0; cursor += 8
            default: break
            }
            output.append(Component(flags: flags, glyphIndex: Int(glyphIndex), arg1: arg1, arg2: arg2,
                                    xScale: xScale, scale01: scale01, scale10: scale10, yScale: yScale))
            if flags & 0x0020 == 0 { break }
        }
        return output
    }

    private func glyphString(for glyphID: Int) -> String? {
        guard glyphID >= 0, glyphID < glyphs.count, let glyph = glyphs[glyphID] else { return nil }
        if glyph.contours >= 0 {
            guard let simple = glyph.simple else { return nil }
            return zip(simple.x, simple.y).map { "\($0.0),\($0.1)" }.joined(separator: "|")
        }
        let components = glyph.components.map {
            "{flags:\($0.flags),glyphIndex:\($0.glyphIndex),arg1:\($0.arg1),arg2:\($0.arg2),xScale:\($0.xScale),scale01:\($0.scale01),scale10:\($0.scale10),yScale:\($0.yScale)}"
        }.joined(separator: ",")
        return "[\(components)]"
    }

    private func readData(_ offset: Int, count: Int) -> Data? {
        guard offset >= 0, count >= 0, offset <= data.count - count else { return nil }
        return data.subdata(in: offset..<(offset + count))
    }

    private func readU8(_ offset: Int) -> UInt8? {
        guard offset >= 0, offset < data.count else { return nil }
        return data[offset]
    }

    private func readU16(_ offset: Int) -> UInt16? {
        guard let bytes = readData(offset, count: 2) else { return nil }
        return UInt16(bytes[bytes.startIndex]) << 8 | UInt16(bytes[bytes.startIndex + 1])
    }

    private func readI16(_ offset: Int) -> Int16? {
        guard let value = readU16(offset) else { return nil }
        return Int16(bitPattern: value)
    }

    private func readU32(_ offset: Int) -> UInt32? {
        guard let bytes = readData(offset, count: 4) else { return nil }
        return UInt32(bytes[bytes.startIndex]) << 24 |
            UInt32(bytes[bytes.startIndex + 1]) << 16 |
            UInt32(bytes[bytes.startIndex + 2]) << 8 |
            UInt32(bytes[bytes.startIndex + 3])
    }

    private func readI32(_ offset: Int) -> Int32? {
        guard let value = readU32(offset) else { return nil }
        return Int32(bitPattern: value)
    }
}
