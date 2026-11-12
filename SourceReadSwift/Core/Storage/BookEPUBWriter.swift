import Foundation
import ZIPFoundation

/// Minimal EPUB 3 packager for cached prose chapters. It intentionally has no
/// network dependency: the caller fetches chapters before entering this writer.
struct BookEPUBWriter {
    private struct ChapterFile {
        let id: String
        let fileName: String
        let title: String
        let xhtml: String
    }

    func export(
        book: BookshelfBook,
        chapters: [ChapterContent],
        coverJPEG: Data?,
        totalChapterCount: Int
    ) throws -> BookArchiveExport {
        try Task.checkCancellation()
        guard !chapters.isEmpty else { throw BookExportError.noContent }
        let ordered = chapters.enumerated().sorted {
            if $0.element.chapter.index != $1.element.chapter.index {
                return $0.element.chapter.index < $1.element.chapter.index
            }
            return $0.offset < $1.offset
        }.map(\.element)
        let url = temporaryURL(for: book)
        var completed = false
        defer {
            if !completed, FileManager.default.fileExists(atPath: url.path) {
                do { try FileManager.default.removeItem(at: url) }
                catch { NSLog("Incomplete EPUB cleanup failed: %ld", (error as NSError).code) }
            }
        }
        guard let archive = Archive(url: url, accessMode: .create) else {
            throw BookExportError.archiveCreationFailed
        }

        // EPUB requires mimetype to be the first entry, stored without compression.
        try addEntry("mimetype", data: Data("application/epub+zip".utf8),
                     to: archive, compression: CompressionMethod.none)
        try addEntry("META-INF/container.xml", data: Data(containerXML.utf8), to: archive)

        let identifier = "urn:uuid:\(UUID().uuidString.lowercased())"
        let modified = ISO8601DateFormatter().string(from: Date())
        let files = try ordered.enumerated().map { offset, chapter in
            try Task.checkCancellation()
            return ChapterFile(
                id: String(format: "chapter-%04d", offset + 1),
                fileName: String(format: "chapter-%04d.xhtml", offset + 1),
                title: chapter.title,
                xhtml: chapterXHTML(title: chapter.title, paragraphs: chapter.paragraphs)
            )
        }
        let hasCover = coverJPEG?.isEmpty == false
        let manifest = manifestXML(files: files, hasCover: hasCover)
        let spine = spineXML(files: files, hasCover: hasCover)
        try addEntry("OEBPS/content.opf",
            data: Data(contentOPF(book: book, identifier: identifier, modified: modified,
                                  manifest: manifest, spine: spine, hasCover: hasCover).utf8),
            to: archive)
        try addEntry("OEBPS/nav.xhtml",
            data: Data(navXHTML(book: book, files: files).utf8), to: archive)
        try addEntry("OEBPS/toc.ncx",
            data: Data(tocNCX(book: book, identifier: identifier, files: files).utf8), to: archive)
        try addEntry("OEBPS/style.css", data: Data(styleCSS.utf8), to: archive)
        if let coverJPEG, !coverJPEG.isEmpty {
            try addEntry("OEBPS/cover.jpg", data: coverJPEG, to: archive)
            try addEntry("OEBPS/cover.xhtml", data: Data(coverXHTML(book: book).utf8), to: archive)
        }
        for file in files {
            try Task.checkCancellation()
            try addEntry("OEBPS/\(file.fileName)", data: Data(file.xhtml.utf8), to: archive)
        }
        completed = true
        return BookArchiveExport(url: url, format: .epub,
            exportedChapterCount: ordered.count,
            totalChapterCount: max(totalChapterCount, ordered.count))
    }

    private var containerXML: String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>
        """
    }

    private var styleCSS: String {
        """
        body { margin: 1.4em; line-height: 1.72; font-family: serif; }
        h1 { font-size: 1.45em; line-height: 1.3; margin: 0 0 1.2em; }
        p { margin: 0 0 0.9em; text-indent: 2em; }
        img { max-width: 100%; height: auto; }
        """
    }

    private func manifestXML(files: [ChapterFile], hasCover: Bool) -> String {
        var items = [
            "<item id=\"nav\" href=\"nav.xhtml\" media-type=\"application/xhtml+xml\" properties=\"nav\"/>",
            "<item id=\"ncx\" href=\"toc.ncx\" media-type=\"application/x-dtbncx+xml\"/>",
            "<item id=\"style\" href=\"style.css\" media-type=\"text/css\"/>"
        ]
        if hasCover {
            items.append("<item id=\"cover-image\" href=\"cover.jpg\" media-type=\"image/jpeg\" properties=\"cover-image\"/>")
            items.append("<item id=\"cover\" href=\"cover.xhtml\" media-type=\"application/xhtml+xml\"/>")
        }
        for file in files {
            items.append("<item id=\"\(file.id)\" href=\"\(file.fileName)\" media-type=\"application/xhtml+xml\"/>")
        }
        return items.joined(separator: "\n    ")
    }

    private func spineXML(files: [ChapterFile], hasCover: Bool) -> String {
        var items: [String] = []
        if hasCover { items.append("<itemref idref=\"cover\" linear=\"no\"/>") }
        for file in files { items.append("<itemref idref=\"\(file.id)\"/>") }
        return items.joined(separator: "\n    ")
    }

    private func contentOPF(book: BookshelfBook, identifier: String, modified: String,
                             manifest: String, spine: String, hasCover: Bool) -> String {
        let intro = book.intro?.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = (intro?.isEmpty == false)
            ? "<dc:description>\(escapeXML(intro ?? ""))</dc:description>" : ""
        let coverMeta = hasCover ? "<meta name=\"cover\" content=\"cover-image\"/>" : ""
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:identifier id="bookid">\(escapeXML(identifier))</dc:identifier>
            <dc:title>\(escapeXML(book.title))</dc:title>
            <dc:creator>\(escapeXML(book.author))</dc:creator>
            <dc:language>zh-CN</dc:language>
            \(description)
            <meta property="dcterms:modified">\(modified)</meta>
            \(coverMeta)
          </metadata>
          <manifest>
            \(manifest)
          </manifest>
          <spine toc="ncx">
            \(spine)
          </spine>
        </package>
        """
    }

    private func navXHTML(book: BookshelfBook, files: [ChapterFile]) -> String {
        let items = files.map {
            "<li><a href=\"\($0.fileName)\">\(escapeXML($0.title))</a></li>"
        }.joined(separator: "\n        ")
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="zh-CN" xml:lang="zh-CN">
        <head><title>目录</title><link rel="stylesheet" type="text/css" href="style.css"/></head>
        <body><nav epub:type="toc" id="toc"><h1>\(escapeXML(book.title))</h1>
          <ol>
            \(items)
          </ol>
        </nav></body>
        </html>
        """
    }

    private func tocNCX(book: BookshelfBook, identifier: String, files: [ChapterFile]) -> String {
        let points = files.enumerated().map { offset, file in
            """
            <navPoint id="navPoint-\(offset + 1)" playOrder="\(offset + 1)">
              <navLabel><text>\(escapeXML(file.title))</text></navLabel>
              <content src="\(file.fileName)"/>
            </navPoint>
            """
        }.joined(separator: "\n    ")
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
          <head><meta name="dtb:uid" content="\(escapeXML(identifier))"/></head>
          <docTitle><text>\(escapeXML(book.title))</text></docTitle>
          <navMap>
            \(points)
          </navMap>
        </ncx>
        """
    }

    private func coverXHTML(book: BookshelfBook) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml" lang="zh-CN" xml:lang="zh-CN">
        <head><title>\(escapeXML(book.title))</title><link rel="stylesheet" type="text/css" href="style.css"/></head>
        <body><div><img src="cover.jpg" alt="\(escapeXML(book.title))"/></div></body>
        </html>
        """
    }

    private func chapterXHTML(title: String, paragraphs: [String]) -> String {
        let body = paragraphs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { "<p>\(escapeXML($0))</p>" }
            .joined(separator: "\n    ")
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml" lang="zh-CN" xml:lang="zh-CN">
        <head><title>\(escapeXML(title))</title><link rel="stylesheet" type="text/css" href="style.css"/></head>
        <body><h1>\(escapeXML(title))</h1>
            \(body)
        </body>
        </html>
        """
    }

    private func escapeXML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private func addEntry(_ name: String, data: Data, to archive: Archive,
                          compression: CompressionMethod = .deflate) throws {
        try archive.addEntry(with: name, type: .file, uncompressedSize: Int64(data.count),
            compressionMethod: compression,
            provider: { position, size in
                try Task.checkCancellation()
                let start = Int(position)
                let end = min(start + size, data.count)
                guard start < end else { return Data() }
                return data.subdata(in: start..<end)
            })
    }

    private func temporaryURL(for book: BookshelfBook) -> URL {
        let invalid = CharacterSet(charactersIn: "\\/:*?\"<>|").union(.controlCharacters)
        let cleaned = book.title.components(separatedBy: invalid)
            .joined(separator: "_").trimmingCharacters(in: .whitespacesAndNewlines)
        var title = ""
        for character in cleaned {
            guard title.utf8.count + String(character).utf8.count <= 180 else { break }
            title.append(character)
        }
        let name = "\(title.isEmpty ? "书籍导出" : title)-\(UUID().uuidString).epub"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: url)
        return url
    }
}
