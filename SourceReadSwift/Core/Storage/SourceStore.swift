import Foundation

struct SourceImportReport: Equatable, Sendable {
    var addedBookSources = 0
    var updatedBookSources = 0
    var addedRSSSources = 0
    var updatedRSSSources = 0
    var addedCatalogs = 0
    var updatedCatalogs = 0
    var ignored = 0

    var totalAdded: Int {
        addedBookSources + addedRSSSources + addedCatalogs
    }

    var totalUpdated: Int {
        updatedBookSources + updatedRSSSources + updatedCatalogs
    }

    var userMessage: String {
        "导入完成：新增 \(totalAdded)，更新 \(totalUpdated)，忽略 \(ignored)；书源 \(addedBookSources)/\(updatedBookSources)，仓库 \(addedCatalogs)/\(updatedCatalogs)，RSS \(addedRSSSources)/\(updatedRSSSources)"
    }
}

/// Outcome of a smart import that may have gone through the network.
struct SourceSmartImportResult: Sendable {
    let input: SourceImportInput
    let report: SourceImportReport
    /// Final URL after redirects, or nil when the input was pasted JSON.
    let downloadedFrom: URL?
}

@MainActor
final class SourceStore: ObservableObject {
    private(set) var sourcesRevision: UInt64 = 0
    @Published private(set) var sources: [BookSource] = [] {
        didSet { sourcesRevision &+= 1 }
    }
    @Published private(set) var rssSources: [RSSSource] = []
    @Published private(set) var catalogs: [SourceCatalog] = []
    @Published private(set) var lastError: String?
    private let persistence: SourcePersistence

    nonisolated static let defaultRSSSources: [RSSSource] = [
        RSSSource(
            sourceName: "使用说明",
            sourceUrl: "https://www.yuque.com/legado",
            sourceIcon: "http://ku.mumuceo.com/static/images/applogo/yuedu.png",
            enabled: true
        ),
        RSSSource(
            sourceName: "源仓库",
            sourceUrl: "http://yck.mumuceo.com/",
            sourceIcon: "https://txc.gtimg.com/data/145120/2020/0418/99f04e2fdbed180f8ad0cb6ee5cfddca.png",
            enabled: true
        ),
        RSSSource(
            sourceName: "海阔视界",
            sourceUrl: "https://haikuoshijie.cn/topics/node/1?p=2",
            sourceIcon: "http://image.5you.com/attachment/soft/2020/0720/171051_34898081.png",
            enabled: true
        )
    ]

    nonisolated static var defaultBookSources: [BookSource] {
        [
            BuiltinBrowserSourceProvider.defaultBrowserSource,
            BookSource(
                bookSourceName: "新版笔趣阁",
                bookSourceUrl: "https://www.biquge8.xyz",
                bookSourceGroup: "官方精选",
                bookSourceType: 0,
                enabled: true,
                weight: 100,
                searchUrl: "https://www.biquge8.xyz/search?keyword={{key}}",
                ruleSearch: SourceRule(fields: [
                    "bookList": "ul.flex li",
                    "name": "h2@text",
                    "author": ".li_bottom a[href*='/author/']@text",
                    "bookUrl": ".w100 a@href||h2 a@href||a[href^='/']:not([href*='/author/'])@href",
                    "coverUrl": "img@crs||img@src",
                    "intro": ".indent@text",
                    "kind": ".img_span span@text"
                ]),
                ruleBookInfo: SourceRule(fields: [
                    "name": ".novel_info_title h1@text||h1@text",
                    "author": ".novel_info_title a[href*='/author/']@text",
                    "coverUrl": ".novel_info_main img@src",
                    "intro": ".novel_info_main .indent@text",
                    "kind": ".novel_info_title p span.0@text",
                    "lastChapter": ".to100 a@text"
                ]),
                ruleToc: SourceRule(fields: [
                    "chapterList": ".chapter_list li a",
                    "chapterName": "@text",
                    "chapterUrl": "@href"
                ]),
                ruleContent: SourceRule(fields: [
                    "content": "#bodybox@html||#article@html||#content@html",
                    "nextContentUrl": "#next_page@href"
                ]),
                header: "{\"User-Agent\":\"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36\"}"
            ),
            BookSource(
                bookSourceName: "笔趣米",
                bookSourceUrl: "https://www.biqumi.com",
                bookSourceGroup: "官方精选",
                bookSourceType: 0,
                enabled: true,
                weight: 95,
                searchUrl: "https://www.biqumi.com/search.php?q={{key}}",
                ruleSearch: SourceRule(fields: [
                    "bookList": "div.col-12.col-md-6",
                    "name": "h3 a@text##\\[.*?\\]##",
                    "author": ".book_other:contains(作者) span@text||.book_other:contains(作者)@text##作者：##",
                    "bookUrl": "dt a@href",
                    "coverUrl": "dt img@src",
                    "lastChapter": ".book_other:contains(最新章节) a@text"
                ]),
                ruleBookInfo: SourceRule(fields: [
                    "name": ".info h1@text||h1@text",
                    "author": ".info li:contains(作者) a@text||.book_other:contains(作者) a@text",
                    "coverUrl": "img.img-thumbnail@src||dt img@src",
                    "intro": "#intro_pc@ownText||.intro@text",
                    "lastChapter": ".info li:contains(最新) a@text"
                ]),
                ruleToc: SourceRule(fields: [
                    "chapterList": "ul.row li.col-md-3 a||.book_list2 li a||.col-md-3 a",
                    "chapterName": "@text",
                    "chapterUrl": "@href"
                ]),
                ruleContent: SourceRule(fields: [
                    "content": "article@html||.font_max@html||#content@html",
                    "nextContentUrl": "a:contains(下一章)@href||#next1@href",
                    "replaceRegex": "##第\\(\\d+/\\d+\\)页##"
                ]),
                header: "{\"User-Agent\":\"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36\"}"
            ),
            BookSource(
                bookSourceName: "无极小说",
                bookSourceUrl: "https://www.wjxsw.net",
                bookSourceGroup: "官方精选",
                bookSourceType: 0,
                enabled: true,
                weight: 90,
                searchUrl: "https://www.wjxsw.net/search.php?q={{key}}",
                ruleSearch: SourceRule(fields: [
                    "bookList": "div.col-12.col-md-6",
                    "name": "h3 a@text##\\[.*?\\]##",
                    "author": ".book_other:contains(作者) span@text||.book_other:contains(作者)@text##作者：##",
                    "bookUrl": "dt a@href",
                    "coverUrl": "dt img@src",
                    "lastChapter": ".book_other:contains(最新章节) a@text"
                ]),
                ruleBookInfo: SourceRule(fields: [
                    "name": ".info h1@text||h1@text",
                    "author": ".info li:contains(作者) a@text||.book_other:contains(作者) a@text",
                    "coverUrl": "img.img-thumbnail@src||dt img@src",
                    "intro": "#intro_pc@ownText||.intro@text",
                    "lastChapter": ".info li:contains(最新) a@text"
                ]),
                ruleToc: SourceRule(fields: [
                    "chapterList": "ul.row li.col-md-3 a||.book_list li a||.col-md-3 a",
                    "chapterName": "@text",
                    "chapterUrl": "@href"
                ]),
                ruleContent: SourceRule(fields: [
                    "content": "article@html||.font_max@html||#content@html",
                    "nextContentUrl": "a:contains(下一章)@href||#next1@href",
                    "replaceRegex": "##第\\(\\d+/\\d+\\)页##"
                ]),
                header: "{\"User-Agent\":\"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36\"}"
            ),
            BookSource(
                bookSourceName: "新笔趣阁CC",
                bookSourceUrl: "https://www.xbshu.com",
                bookSourceGroup: "官方精选",
                bookSourceType: 0,
                enabled: true,
                weight: 88,
                searchUrl: "https://www.xbshu.com/search.php?q={{key}}",
                ruleSearch: SourceRule(fields: [
                    "bookList": "div.col-12.col-md-6",
                    "name": "h3 a@text##\\[.*?\\]##",
                    "author": ".book_other:contains(作者) span@text||.book_other:contains(作者)@text##作者：##",
                    "bookUrl": "dt a@href||h3 a@href",
                    "coverUrl": "dt img@src",
                    "lastChapter": ".book_other:contains(最新章节) a@text"
                ]),
                ruleBookInfo: SourceRule(fields: [
                    "name": ".info h1@text||h1@text",
                    "author": ".info li:contains(作者) a@text||.book_other:contains(作者) a@text",
                    "coverUrl": "img.img-thumbnail@src||dt img@src",
                    "intro": "#intro_pc@ownText||.intro@text",
                    "lastChapter": ".info li:contains(最新) a@text"
                ]),
                ruleToc: SourceRule(fields: [
                    "chapterList": "ul.row li.col-md-3 a||.book_list li a||.col-md-3 a||#list a||dd a",
                    "chapterName": "@text",
                    "chapterUrl": "@href"
                ]),
                ruleContent: SourceRule(fields: [
                    "content": "article@html||.font_max@html||#content@html",
                    "nextContentUrl": "a:contains(下一章)@href||#next1@href",
                    "replaceRegex": "##第\\(\\d+/\\d+\\)页##"
                ]),
                header: "{\"User-Agent\":\"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36\"}"
            ),
            BookSource(
                bookSourceName: "笔趣阁5",
                bookSourceUrl: "https://www.biquge5.com",
                bookSourceGroup: "官方精选",
                bookSourceType: 0,
                enabled: true,
                weight: 85,
                searchUrl: "https://www.biquge5.com/search.php?q={{key}}",
                ruleSearch: SourceRule(fields: [
                    "bookList": "div.col-12.col-md-6",
                    "name": "h3 a@text##\\[.*?\\]##",
                    "author": ".book_other:contains(作者) span@text||.book_other:contains(作者)@text##作者：##",
                    "bookUrl": "dt a@href",
                    "coverUrl": "dt img@src",
                    "lastChapter": ".book_other:contains(最新章节) a@text"
                ]),
                ruleBookInfo: SourceRule(fields: [
                    "name": ".info h1@text||h1@text",
                    "author": ".info li:contains(作者) a@text||.book_other:contains(作者) a@text",
                    "coverUrl": "img.img-thumbnail@src||dt img@src",
                    "intro": "#intro_pc@ownText||.intro@text",
                    "lastChapter": ".info li:contains(最新) a@text"
                ]),
                ruleToc: SourceRule(fields: [
                    "chapterList": "ul.row li.col-md-3 a||.book_list li a||.col-md-3 a",
                    "chapterName": "@text",
                    "chapterUrl": "@href"
                ]),
                ruleContent: SourceRule(fields: [
                    "content": "article@html||.font_max@html||#content@html",
                    "nextContentUrl": "a:contains(下一章)@href||#next1@href",
                    "replaceRegex": "##第\\(\\d+/\\d+\\)页##"
                ]),
                header: "{\"User-Agent\":\"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36\"}"
            ),
            BookSource(
                bookSourceName: "天空影视 (官方精选)",
                bookSourceUrl: "https://api.tiankongapi.com",
                bookSourceGroup: "官方精选",
                bookSourceType: 3,
                enabled: true,
                weight: 120,
                searchUrl: "https://api.tiankongapi.com/api.php/provide/vod/at/json?wd={{key}}",
                ruleSearch: SourceRule(fields: [
                    "bookList": "$.list[*]",
                    "name": "$.vod_name",
                    "author": "$.vod_director||$.vod_actor",
                    "coverUrl": "$.vod_pic",
                    "intro": "$.vod_content",
                    "kind": "$.type_name",
                    "lastChapter": "$.vod_remarks",
                    "bookUrl": "https://api.tiankongapi.com/api.php/provide/vod/at/json?ac=detail&ids={{$.vod_id}}"
                ]),
                ruleBookInfo: SourceRule(fields: [
                    "name": "$.list[0].vod_name",
                    "author": "$.list[0].vod_director",
                    "coverUrl": "$.list[0].vod_pic",
                    "intro": "$.list[0].vod_content",
                    "kind": "$.list[0].type_name",
                    "lastChapter": "$.list[0].vod_remarks"
                ]),
                ruleToc: SourceRule(fields: [
                    "chapterList": "$.list[0].vod_play_url@js:result ? result.split('#').filter(function(x){return x && x.indexOf('$')!==-1;}).map(function(x){var p=x.split('$');return {name:p[0],url:p[1]};}) : []",
                    "chapterName": "name",
                    "chapterUrl": "url"
                ]),
                ruleContent: SourceRule(fields: [
                    "content": "$.url||@text"
                ]),
                header: "{\"User-Agent\":\"Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15\"}"
            ),
            BookSource(
                bookSourceName: "包子漫画 (官方精选)",
                bookSourceUrl: "https://cn.baozimh.com",
                bookSourceGroup: "官方精选",
                bookSourceType: 2,
                enabled: true,
                weight: 110,
                searchUrl: "https://cn.baozimh.com/search?q={{key}}",
                ruleSearch: SourceRule(fields: [
                    "bookList": "div.comics-card",
                    "name": "a.comics-card__title@text||h3@text",
                    "author": "small.comics-card__sub-title@text",
                    "coverUrl": "amp-img@src||img@src",
                    "bookUrl": "a.comics-card__poster@href||a@href"
                ]),
                ruleBookInfo: SourceRule(fields: [
                    "name": "h1.comics-detail__title@text",
                    "author": "h2.comics-detail__author@text",
                    "coverUrl": "div.pure-u-1-1 amp-img@src||img@src",
                    "intro": "p.comics-detail__desc@text"
                ]),
                ruleToc: SourceRule(fields: [
                    "chapterList": "div#chapter-items div.pure-u-1-2 a||div.pure-g a",
                    "chapterName": "span@text||@text",
                    "chapterUrl": "@href"
                ]),
                ruleContent: SourceRule(fields: [
                    "content": "div.comic-contain amp-img@src||div.comic-contain img@src"
                ]),
                header: "{\"User-Agent\":\"Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15\"}"
            ),
            BookSource(
                bookSourceName: "520听书网 (官方精选)",
                bookSourceUrl: "https://www.ting520.net",
                bookSourceGroup: "官方精选",
                bookSourceType: 1,
                enabled: true,
                weight: 100,
                searchUrl: "https://www.ting520.net/search.php?searchtype=name&searchword={{key}}",
                ruleSearch: SourceRule(fields: [
                    "bookList": "ul.list-works li",
                    "name": "h3.list-book-dt a@text",
                    "author": "span.book-author@text",
                    "coverUrl": "img@src",
                    "bookUrl": "h3.list-book-dt a@href"
                ]),
                ruleBookInfo: SourceRule(fields: [
                    "name": "div.book-title h1@text",
                    "author": "span.author a@text",
                    "coverUrl": "div.book-cover img@src",
                    "intro": "div.book-intro@text"
                ]),
                ruleToc: SourceRule(fields: [
                    "chapterList": "ul#playlist li a",
                    "chapterName": "@text",
                    "chapterUrl": "@href"
                ]),
                ruleContent: SourceRule(fields: [
                    "content": "audio@src||source@src||#jp_audio_0@src"
                ]),
                header: "{\"User-Agent\":\"Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15\"}"
            )
        ]
    }

    nonisolated static var defaultBookSourcesJSON: String {
        guard let data = try? JSONEncoder().encode(defaultBookSources),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    init(persistence: SourcePersistence = SourcePersistence()) {
        self.persistence = persistence
        do {
            let snapshot = try persistence.load()
            sources = snapshot.sources.map { source in
                if source.bookSourceUrl.contains("xbqg.cc") {
                    return BookSource(
                        bookSourceName: source.bookSourceName,
                        bookSourceUrl: "https://www.xbshu.com",
                        bookSourceGroup: source.bookSourceGroup,
                        bookSourceType: source.bookSourceType,
                        enabled: source.enabled,
                        weight: source.weight,
                        searchUrl: "https://www.xbshu.com/search.php?q={{key}}",
                        exploreUrl: source.exploreUrl,
                        ruleSearch: source.ruleSearch ?? SourceRule(fields: [
                            "bookList": "div.col-12.col-md-6",
                            "name": "h3 a@text##\\[.*?\\]##",
                            "author": ".book_other:contains(作者) span@text||.book_other:contains(作者)@text##作者：##",
                            "bookUrl": "dt a@href||h3 a@href",
                            "coverUrl": "dt img@src",
                            "lastChapter": ".book_other:contains(最新章节) a@text"
                        ]),
                        ruleBookInfo: source.ruleBookInfo,
                        ruleToc: SourceRule(fields: [
                            "chapterList": "ul.row li.col-md-3 a||.book_list li a||.col-md-3 a||#list a||dd a",
                            "chapterName": "@text",
                            "chapterUrl": "@href"
                        ]),
                        ruleContent: source.ruleContent,
                        ruleExplore: source.ruleExplore,
                        header: source.header,
                        loginUrl: source.loginUrl,
                        loginCheckJs: source.loginCheckJs,
                        customConfig: source.customConfig,
                        raw: source.raw
                    )
                }
                return source
            }.filter { !$0.bookSourceUrl.contains("6yzw.org") }
            rssSources = snapshot.rssSources
            catalogs = snapshot.catalogs
        } catch {
            lastError = error.localizedDescription
        }
    }

    func loadDefaultBookSources() throws {
        try importSources(Self.defaultBookSources)
    }

    func loadDefaultRSSSources() throws {
        try importRSSSources(Self.defaultRSSSources)
    }

    @discardableResult
    func importJSON(_ text: String) throws -> SourceImportReport {
        try importJSONData(Data(text.utf8))
    }

    @discardableResult
    func importSmartInput(_ input: String) throws -> SourceImportInput {
        let parsed = SourceImportLinkParser.parse(input)
        switch parsed.kind {
        case .empty:
            throw SourceImportError.empty
        case .json:
            _ = try importJSON(parsed.value)
        case .url:
            throw SourceImportError.urlImportRequired(parsed.value)
        case .unsupportedScheme:
            throw SourceImportError.unsupportedScheme
        case .unknown:
            throw SourceImportError.unknownInput
        }
        return parsed
    }

    /// Smart import that also handles HTTP(S) URLs and reader import links.
    ///
    /// The download step is injected so tests can exercise status handling,
    /// size limits and challenge detection without hitting the network. The
    /// same entry point serves the paste field, the URL field and catalog rows,
    /// so all three paths share one validation chain.
    @discardableResult
    func importSmartInputAsync(
        _ input: String,
        downloader: any SourceImportDownloading = SourceImportDownloader()
    ) async throws -> SourceSmartImportResult {
        let parsed = SourceImportLinkParser.parse(input)
        switch parsed.kind {
        case .empty:
            throw SourceImportError.empty
        case .json:
            let report = try await importJSONAsync(parsed.value)
            return SourceSmartImportResult(input: parsed, report: report, downloadedFrom: nil)
        case .url:
            let payload: SourceImportPayload
            switch await downloader.download(from: parsed.value) {
            case .success(let value):
                payload = value
            case .failure(let error):
                throw error
            }
            let report: SourceImportReport
            do {
                report = try await importJSONDataAsync(payload.data)
            } catch {
                // JSONDecoder only accepts UTF-8. GBK/Big5 exports arrive as
                // raw legacy bytes with a decoded text field alongside them, so
                // retry from the charset-decoded string before giving up.
                let textData = Data(payload.text.utf8)
                guard !payload.text.isEmpty, textData != payload.data else { throw error }
                report = try await importJSONDataAsync(textData)
            }
            return SourceSmartImportResult(input: parsed, report: report, downloadedFrom: payload.url)
        case .unsupportedScheme:
            throw SourceImportError.unsupportedScheme
        case .unknown:
            throw SourceImportError.unknownInput
        }
    }

    @discardableResult
    func importJSONData(_ data: Data) throws -> SourceImportReport {
        if let adapted = Self.specializedBookSources(from: data) {
            return try importAdaptedBookSources(adapted)
        }
        return try importItems(Self.decodeImportItems(from: data))
    }

    /// Shared JSON import decoder for the sync and async entry points.
    ///
    /// Order matters: a plain array, then an envelope, then the same two passes
    /// after byte-level trailing-comma repair, then text normalization. The
    /// envelope pass must precede the single-object fallback so nested shapes
    /// such as `{ "data": { "bookSources": [...] } }` are not mistaken for one
    /// source object. Keeping this in one place is what stops the sync and
    /// async paths from drifting apart.
    private nonisolated static func decodeImportItems(from data: Data) throws -> [AnySourceImportItem] {
        let cleanData = Self.utf8NormalizedImportData(Self.stripUTF8BOMStatic(data))
        let decoder = JSONDecoder()

        // 1. Fast path: direct parsing first (avoids megabytes of string allocation).
        if let items = try? decoder.decode([AnySourceImportItem].self, from: cleanData) {
            return items
        }
        if let wrapped = try? decoder.decode(WrappedSourceImportItems.self, from: cleanData),
           !wrapped.items.isEmpty {
            return wrapped.items
        }

        // 2. Fast byte-level trailing comma removal.
        let sanitizedData = sanitizeTrailingCommasData(cleanData)
        if let items = try? decoder.decode([AnySourceImportItem].self, from: sanitizedData) {
            return items
        }
        if let wrapped = try? decoder.decode(WrappedSourceImportItems.self, from: sanitizedData),
           !wrapped.items.isEmpty {
            return wrapped.items
        }

        // 3. Fallback: string normalization and substring extraction.
        let normalized = try normalizeDataStatic(cleanData)
        if let items = try? decoder.decode([AnySourceImportItem].self, from: normalized) {
            return items
        }
        if let wrapped = try? decoder.decode(WrappedSourceImportItems.self, from: normalized),
           !wrapped.items.isEmpty {
            return wrapped.items
        }
        let item = try decoder.decode(AnySourceImportItem.self, from: normalized)
        return [item]
    }

    @discardableResult
    func importJSONDataAsync(_ data: Data) async throws -> SourceImportReport {
        // Adapters are pure Sendable transforms. Run the whole dispatch off the
        // main actor so encrypted XBS payloads and large exports never hitch the UI.
        let adapted = await Task.detached(priority: .userInitiated) {
            SourceStore.specializedBookSources(from: data)
        }.value
        if let adapted {
            return try importAdaptedBookSources(adapted)
        }

        // Decode off the main actor; the same static decoder is used by the
        // sync path so wrappers, BOM handling, and sanitizing never drift.
        let decodedItems = try await Task.detached(priority: .userInitiated) {
            try SourceStore.decodeImportItems(from: data)
        }.value

        return try self.importItems(decodedItems)
    }

    /// Single source of truth for specialized import adapters.
    ///
    /// Sync and async imports must never drift: every adapter is probed here in
    /// the same order. `nil` means "no specialized format matched", so generic
    /// Legado JSON decoding still gets its chance.
    nonisolated static func specializedBookSources(from data: Data) -> [BookSource]? {
        if XbsBookSourceAdapter.isXbsData(data) {
            let adapted = XbsBookSourceAdapter.importSources(from: data)
            if !adapted.isEmpty { return adapted }
        }
        if HuaHuoBookSourceAdapter.isHuaHuoData(data) {
            let adapted = HuaHuoBookSourceAdapter.importSources(from: data)
            if !adapted.isEmpty { return adapted }
        }
        if HaiKuoShiJieSourceAdapter.isHaiKuoData(data) {
            let adapted = HaiKuoShiJieSourceAdapter.importSources(from: data)
            if !adapted.isEmpty { return adapted }
        }
        return nil
    }

    private func importAdaptedBookSources(_ adapted: [BookSource]) throws -> SourceImportReport {
        let existingCount = sources.count
        try importSources(adapted)
        let added = max(0, sources.count - existingCount)
        let updated = max(0, adapted.count - added)
        return SourceImportReport(addedBookSources: added, updatedBookSources: updated)
    }

    @discardableResult
    func importJSONAsync(_ text: String) async throws -> SourceImportReport {
        try await importJSONDataAsync(Data(text.utf8))
    }

    func importSources(_ imported: [BookSource]) throws {
        let valid = imported.filter {
            !$0.bookSourceUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !valid.isEmpty else {
            throw SourceImportError.empty
        }
        sources = merge(existing: sources, incoming: valid)
        try persist()
        lastError = nil
    }

    func upsertBookSourceJSON(_ text: String) throws -> BookSource {
        let decoder = JSONDecoder()
        let source = try decoder.decode(BookSource.self, from: Data(text.utf8))
        try importSources([source])
        return source
    }

    func importRSSSources(_ imported: [RSSSource]) throws {
        let valid = imported.filter {
            !$0.sourceUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !valid.isEmpty else {
            throw SourceImportError.empty
        }
        rssSources = mergeRSS(existing: rssSources, incoming: valid)
        try persist()
        lastError = nil
    }

    @discardableResult
    func upsertRSSSource(_ source: RSSSource) throws -> RSSSource {
        try importRSSSources([source])
        return source
    }

    func importCatalogs(_ imported: [SourceCatalog]) throws {
        let valid = imported.filter {
            !$0.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !valid.isEmpty else {
            throw SourceImportError.empty
        }
        catalogs = mergeCatalogs(existing: catalogs, incoming: valid)
        try persist()
        lastError = nil
    }

    func seedForDevelopment() {
        guard sources.isEmpty else { return }
        sources = [
            BookSource(
                bookSourceName: "Example HTML Source",
                bookSourceUrl: "https://example.com",
                searchUrl: "https://example.com/search?q={{keyword}}",
                ruleSearch: SourceRule(fields: [
                    "bookList": ".book",
                    "name": ".title@text",
                    "author": ".author@text",
                    "bookUrl": "a@href",
                    "coverUrl": "img@src"
                ])
            )
        ]
    }

    func source(for sourceUrl: String) -> BookSource? {
        if let exact = sources.first(where: { $0.bookSourceUrl == sourceUrl }) {
            return exact
        }
        let trimmed = sourceUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        if let match = sources.first(where: { $0.bookSourceUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")) == trimmed }) {
            return match
        }
        if let host = URL(string: sourceUrl)?.host?.lowercased(), !host.isEmpty {
            if let match = sources.first(where: { URL(string: $0.bookSourceUrl)?.host?.lowercased() == host }) {
                return match
            }
        }
        return nil
    }

    /// Portable export used by the all-data backup. Credentials and cookies
    /// are intentionally not part of the source library snapshot.
    func backupSnapshot() -> SourceLibrarySnapshot {
        SourceLibrarySnapshot(sources: sources, rssSources: rssSources, catalogs: catalogs)
    }

    @discardableResult
    func restore(_ snapshot: SourceLibrarySnapshot) -> Bool {
        let normalizedSources = snapshot.sources.filter { !$0.bookSourceUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let normalizedRSSSources = snapshot.rssSources.filter { !$0.sourceUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let normalizedCatalogs = snapshot.catalogs.filter { !$0.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        do {
            let normalized = SourceLibrarySnapshot(
                sources: normalizedSources,
                rssSources: normalizedRSSSources,
                catalogs: normalizedCatalogs
            )
            try persistence.save(normalized)
            sources = normalizedSources
            rssSources = normalizedRSSSources
            catalogs = normalizedCatalogs
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func sourceSwitchCandidates(for bookURL: String, excluding currentSourceURL: String) -> [BookSource] {
        let enabledSources = sources.filter {
            $0.enabled && $0.bookSourceUrl != currentSourceURL && $0.searchUrl != nil
        }
        let matched = enabledSources.filter { source in
            guard let pattern = source.raw["bookUrlPattern"]?.nilIfEmpty,
                  let regex = try? NSRegularExpression(pattern: pattern) else {
                return false
            }
            let range = NSRange(bookURL.startIndex..<bookURL.endIndex, in: bookURL)
            return regex.firstMatch(in: bookURL, range: range) != nil
        }
        let orderedMatched = matched.sorted {
            if $0.weight != $1.weight { return $0.weight > $1.weight }
            return $0.bookSourceName < $1.bookSourceName
        }
        let matchedURLs = Set(orderedMatched.map(\.bookSourceUrl))
        let fallback = enabledSources
            .filter { !matchedURLs.contains($0.bookSourceUrl) }
            .sorted {
                if $0.weight != $1.weight { return $0.weight > $1.weight }
                return $0.bookSourceName < $1.bookSourceName
            }
        return orderedMatched + fallback
    }

    func remove(_ source: BookSource) {
        sources.removeAll { $0.bookSourceUrl == source.bookSourceUrl }
        saveAfterMutation()
    }

    func remove(sourceURLs: Set<String>) {
        sources.removeAll { sourceURLs.contains($0.bookSourceUrl) }
        saveAfterMutation()
    }

    func removeRSS(sourceURLs: Set<String>) {
        rssSources.removeAll { sourceURLs.contains($0.sourceUrl) }
        saveAfterMutation()
    }

    func removeCatalogs(urls: Set<String>) {
        catalogs.removeAll { urls.contains($0.url) }
        saveAfterMutation()
    }

    func setEnabled(_ enabled: Bool, for sourceURLs: Set<String>) {
        sources = sources.map { source in
            sourceURLs.contains(source.bookSourceUrl) ? source.updatingEnabled(enabled) : source
        }
        saveAfterMutation()
    }

    func setRSSEnabled(_ enabled: Bool, for sourceURLs: Set<String>) {
        rssSources = rssSources.map { source in
            guard sourceURLs.contains(source.sourceUrl) else { return source }
            var updated = source
            updated.enabled = enabled
            return updated
        }
        saveAfterMutation()
    }

    func setCatalogsEnabled(_ enabled: Bool, for urls: Set<String>) {
        catalogs = catalogs.map { catalog in
            guard urls.contains(catalog.url) else { return catalog }
            var updated = catalog
            updated.enabled = enabled
            return updated
        }
        saveAfterMutation()
    }

    func recordCatalogImport(url: String, report: SourceImportReport) {
        guard let index = catalogs.firstIndex(where: { $0.url == url }) else { return }
        catalogs[index].importedCount = report.totalAdded + report.totalUpdated
        catalogs[index].lastStatus = report.userMessage
        catalogs[index].lastImportedAt = Date()
        saveAfterMutation()
    }

    private func saveAfterMutation() {
        do {
            try persist()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func persist() throws {
        try persistence.save(
            SourceLibrarySnapshot(
                sources: sources,
                rssSources: rssSources,
                catalogs: catalogs
            )
        )
    }

    private func importItems(_ items: [AnySourceImportItem]) throws -> SourceImportReport {
        var bookSources: [BookSource] = []
        var rss: [RSSSource] = []
        var sourceCatalogs: [SourceCatalog] = []
        var ignored = 0
        for item in items {
            switch item.kind {
            case .bookSource:
                if item.bookSource.bookSourceUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ignored += 1
                } else {
                    bookSources.append(item.bookSource)
                }
            case .rss:
                if item.rssSource.sourceUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ignored += 1
                } else {
                    rss.append(item.rssSource)
                }
            case .catalog:
                if item.catalog.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ignored += 1
                } else {
                    sourceCatalogs.append(item.catalog)
                }
            case .unknown:
                ignored += 1
            }
        }
        if bookSources.isEmpty && rss.isEmpty && sourceCatalogs.isEmpty {
            throw SourceImportError.empty
        }
        let report = SourceImportReport(
            addedBookSources: addedCount(existing: sources.map(\.bookSourceUrl), incoming: bookSources.map(\.bookSourceUrl)),
            updatedBookSources: updatedCount(existing: sources.map(\.bookSourceUrl), incoming: bookSources.map(\.bookSourceUrl)),
            addedRSSSources: addedCount(existing: rssSources.map(\.sourceUrl), incoming: rss.map(\.sourceUrl)),
            updatedRSSSources: updatedCount(existing: rssSources.map(\.sourceUrl), incoming: rss.map(\.sourceUrl)),
            addedCatalogs: addedCount(existing: catalogs.map(\.url), incoming: sourceCatalogs.map(\.url)),
            updatedCatalogs: updatedCount(existing: catalogs.map(\.url), incoming: sourceCatalogs.map(\.url)),
            ignored: ignored
        )
        if !bookSources.isEmpty {
            sources = merge(existing: sources, incoming: bookSources)
        }
        if !rss.isEmpty {
            rssSources = mergeRSS(existing: rssSources, incoming: rss)
        }
        if !sourceCatalogs.isEmpty {
            catalogs = mergeCatalogs(existing: catalogs, incoming: sourceCatalogs)
        }
        try persist()
        lastError = nil
        return report
    }

    private func addedCount(existing: [String], incoming: [String]) -> Int {
        Set(incoming).subtracting(Set(existing)).count
    }

    private func updatedCount(existing: [String], incoming: [String]) -> Int {
        Set(incoming).intersection(Set(existing)).count
    }

    private func merge(existing: [BookSource], incoming: [BookSource]) -> [BookSource] {
        var map = Dictionary(uniqueKeysWithValues: existing.map { ($0.bookSourceUrl, $0) })
        for item in incoming {
            map[item.bookSourceUrl] = item
        }
        return map.values.sorted { $0.bookSourceName < $1.bookSourceName }
    }

    private func mergeRSS(existing: [RSSSource], incoming: [RSSSource]) -> [RSSSource] {
        var map = Dictionary(uniqueKeysWithValues: existing.map { ($0.sourceUrl, $0) })
        for item in incoming {
            map[item.sourceUrl] = item
        }
        return map.values.sorted { $0.sourceName < $1.sourceName }
    }

    private func mergeCatalogs(existing: [SourceCatalog], incoming: [SourceCatalog]) -> [SourceCatalog] {
        var map = Dictionary(uniqueKeysWithValues: existing.map { ($0.url, $0) })
        for item in incoming {
            map[item.url] = item
        }
        return map.values.sorted { $0.name < $1.name }
    }

    private func stripUTF8BOM(_ data: Data) -> Data {
        Self.stripUTF8BOMStatic(data)
    }

    nonisolated static func stripUTF8BOMStatic(_ data: Data) -> Data {
        let bom = Data([0xEF, 0xBB, 0xBF])
        guard data.starts(with: bom) else { return data }
        return data.dropFirst(3)
    }

    /// Normalizes legacy-encoded import payloads to UTF-8 before the first
    /// JSON decode attempt.
    ///
    /// `JSONDecoder` is not a strict UTF-8 gate on every Foundation build: it
    /// can accept GBK bytes and discard the undecodable ones, which turns a
    /// source name into an empty string and imports it as "未命名书源" before
    /// the charset fallback ever runs. Checking validity up front keeps the
    /// fast path allocation-free for UTF-8 exports and makes the legacy path
    /// deterministic for both pasted data and downloaded files.
    nonisolated static func utf8NormalizedImportData(_ data: Data) -> Data {
        guard String(data: data, encoding: .utf8) == nil else { return data }
        let text = ResponseTextDecoder().decode(data: data, headers: [:])
        guard !text.isEmpty else { return data }
        return Data(text.utf8)
    }

    private func normalizeImportData(_ data: Data) throws -> Data {
        try Self.normalizeDataStatic(data)
    }

    nonisolated static func normalizeDataStatic(_ data: Data) throws -> Data {
        let normalizedData = Self.utf8NormalizedImportData(data)
        guard let decodedText = String(data: normalizedData, encoding: .utf8),
              !decodedText.isEmpty else { return data }
        var text = decodedText
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let decoded = try? JSONDecoder().decode(String.self, from: Data(text.utf8)) {
            text = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        text = Self.sanitizeTrailingCommas(text)
        if text.hasPrefix("{") || text.hasPrefix("[") {
            return Data(text.utf8)
        }
        if let extracted = extractFirstJSONValueStatic(from: text) {
            return Data(Self.sanitizeTrailingCommas(extracted).utf8)
        }
        return Data(text.utf8)
    }

    nonisolated static func sanitizeTrailingCommasData(_ data: Data) -> Data {
        // The scanner below only understands ASCII structure. Legacy CJK trail
        // bytes can be 0x5C/0x5D/0x7D, so scanning before UTF-8 normalization
        // can swallow a closing quote or a real bracket and corrupt the body.
        guard String(data: data, encoding: .utf8) != nil else { return data }
        var bytes = [UInt8](data)
        var inString = false
        var escaped = false
        var lastCommaIndex: Int? = nil

        for i in 0..<bytes.count {
            let byte = bytes[i]
            if inString {
                if escaped {
                    escaped = false
                } else if byte == 0x5C { // '\\'
                    escaped = true
                } else if byte == 0x22 { // '"'
                    inString = false
                }
            } else {
                if byte == 0x22 { // '"'
                    inString = true
                    lastCommaIndex = nil
                } else if byte == 0x2C { // ','
                    lastCommaIndex = i
                } else if byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D {
                    // whitespace: keep lastCommaIndex active
                } else if byte == 0x7D || byte == 0x5D { // '}' or ']'
                    if let commaIdx = lastCommaIndex {
                        bytes[commaIdx] = 0x20 // replace trailing comma with space
                        lastCommaIndex = nil
                    }
                } else {
                    lastCommaIndex = nil
                }
            }
        }
        return Data(bytes)
    }

    nonisolated static func sanitizeTrailingCommas(_ json: String) -> String {
        guard let data = json.data(using: .utf8) else { return json }
        let sanitized = sanitizeTrailingCommasData(data)
        return String(data: sanitized, encoding: .utf8) ?? json
    }

    nonisolated static func extractFirstJSONValueStatic(from text: String) -> String? {
        guard let start = text.firstIndex(where: { $0 == "{" || $0 == "[" }) else { return nil }
        let open = text[start]
        let close: Character = open == "{" ? "}" : "]"
        var depth = 0
        var inString = false
        var escaped = false
        var index = start
        while index < text.endIndex {
            let char = text[index]
            if inString {
                if escaped {
                    escaped = false
                } else if char == "\\" {
                    escaped = true
                } else if char == "\"" {
                    inString = false
                }
                index = text.index(after: index)
                continue
            }
            if char == "\"" {
                inString = true
            } else if char == open {
                depth += 1
            } else if char == close {
                depth -= 1
                if depth == 0 {
                    return String(text[start...index])
                }
            }
            index = text.index(after: index)
        }
        return nil
    }

    private func extractFirstJSONValue(from text: String) -> String? {
        Self.extractFirstJSONValueStatic(from: text)
    }
}

private enum SourceImportItemKind {
    case bookSource
    case rss
    case catalog
    case unknown
}

private struct AnySourceImportItem: Decodable {
    let kind: SourceImportItemKind
    let bookSource: BookSource
    let rssSource: RSSSource
    let catalog: SourceCatalog

    init(bookSource: BookSource) {
        self.kind = .bookSource
        self.bookSource = bookSource
        self.rssSource = RSSSource(sourceName: "", sourceUrl: "")
        self.catalog = SourceCatalog(name: "", url: "")
    }

    init(rssSource: RSSSource) {
        self.kind = .rss
        self.bookSource = BookSource(bookSourceName: "", bookSourceUrl: UUID().uuidString)
        self.rssSource = rssSource
        self.catalog = SourceCatalog(name: "", url: "")
    }

    init(catalog: SourceCatalog) {
        self.kind = .catalog
        self.bookSource = BookSource(bookSourceName: "", bookSourceUrl: UUID().uuidString)
        self.rssSource = RSSSource(sourceName: "", sourceUrl: "")
        self.catalog = catalog
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        let keys = Set(container.allKeys.map(\.stringValue))
        let loweredKeys = Set(keys.map { $0.lowercased() })
        let sourceUrl = (try? container.decode(String.self, forKey: DynamicCodingKey("sourceUrl"))) ?? ""
        let url = (try? container.decode(String.self, forKey: DynamicCodingKey("url"))) ?? ""
        let group = (try? container.decode(String.self, forKey: DynamicCodingKey("sourceGroup"))) ?? ""
        let comment = (try? container.decode(String.self, forKey: DynamicCodingKey("sourceComment"))) ?? ""
        let combined = [sourceUrl, url, group, comment].joined(separator: " ").lowercased()

        // RSS exports have their own rule vocabulary. Check them before the
        // generic `rule*` heuristic so a feed is never imported as a book
        // source just because it carries ruleTitle / ruleContent.
        let rssMarkers: Set<String> = [
            "rulearticles", "ruleartical", "sorturl", "rulenextpage",
            "rulepubdate", "ruledescription", "ruleimage", "rulelink"
        ]
        let hasRSSMarker = !loweredKeys.intersection(rssMarkers).isEmpty
        let looksLikeFeed = combined.contains("rss")
            || combined.contains("feed")
            || combined.contains("atom")

        // Any Legado book-source rule field is a stronger signal than `name`
        // or a URL that happens to end in `.json`. This list covers structured
        // rules, the legacy flat `ruleSearchList` family, and request/header
        // fields only book sources carry.
        let bookMarkers: Set<String> = [
            "booksourcename", "booksourceurl", "booksourcegroup", "booksourcetype",
            "searchurl", "searchurl2", "exploreurl", "rulebookinfo", "rulesbookinfo",
            "rulebook", "ruletoc", "rulestoc", "rulecontent", "rulescontent",
            "rulebookcontent", "rulebookcontentreplace", "ruleexplore", "rulesexplore",
            "rulesearch", "rulessearch", "rulesearchurl", "rulefindurl",
            "rulesearchlist", "rulesearchname", "rulesearchauthor", "rulesearchintroduce",
            "rulesearchkind", "rulesearchnoteurl", "rulesearchcoverurl", "rulesearchlastchapter",
            "rulebookname", "rulebookauthor", "ruleintroduce", "rulebookkind",
            "rulecoverurl", "rulebooklastchapter", "rulechapterurl",
            "rulechapterlist", "rulechaptername", "rulecontenturl", "rulechapterurlnext",
            "rulefindlist", "rulefindname", "rulefindauthor", "rulefindintroduce",
            "rulefindkind", "rulefindnoteurl", "rulefindcoverurl", "rulefindlastchapter",
            "loginurl", "logincheckjs", "loginui", "booksourceheader"
        ]
        let hasBookMarker = !loweredKeys.intersection(bookMarkers).isEmpty

        // Dialect tolerance: a source that pairs a name/URL with rule-shaped
        // keys (`ruleXxx`, `search`, `chapterList`, `toc`, ...) is still a book
        // source even when its exact field names are not in the list above.
        let hasNameOrUrl = loweredKeys.contains("booksourcename")
            || loweredKeys.contains("booksourceurl")
            || loweredKeys.contains("sourcename")
            || loweredKeys.contains("sourceurl")
            || loweredKeys.contains("name")
            || loweredKeys.contains("url")
        let hasRuleShapedKey = loweredKeys.contains { key in
            key.hasPrefix("rule")
                || key.hasPrefix("rules")
                || key.contains("searchurl")
                || key == "search"
                || key.contains("chapterlist")
                || key == "toc"
                || key.contains("bookinfo")
        }

        // Catalog objects are small and closed: name/url/importUrl plus display
        // metadata. Anything carrying rules or a request URL is not a catalog.
        let catalogKeys: Set<String> = [
            "name", "url", "sourcename", "sourceurl", "importurl", "singleurl",
            "icon", "sourceicon", "group", "sourcegroup", "comment", "sourcecomment",
            "enabled", "importedcount", "laststatus", "lastimportedat"
        ]
        let onlyCatalogKeys = loweredKeys.isSubset(of: catalogKeys)
        let jsonSuffixedURL = sourceUrl.lowercased().hasSuffix(".json")
            || url.lowercased().hasSuffix(".json")

        if hasRSSMarker || looksLikeFeed {
            kind = .rss
        } else if hasBookMarker || (hasRuleShapedKey && hasNameOrUrl) {
            kind = .bookSource
        } else if loweredKeys.contains("importurl")
            || loweredKeys.contains("singleurl")
            || combined.contains("shuyuan")
            || combined.contains("书源")
            || combined.contains("源仓库")
            || combined.contains("catalog")
            || (onlyCatalogKeys && hasNameOrUrl)
            || (jsonSuffixedURL && !hasRuleShapedKey) {
            kind = .catalog
        } else {
            kind = .unknown
        }

        bookSource = (try? BookSource(from: decoder)) ?? BookSource(
            bookSourceName: "",
            bookSourceUrl: UUID().uuidString
        )
        rssSource = (try? RSSSource(from: decoder)) ?? RSSSource(sourceName: "", sourceUrl: "")
        catalog = (try? SourceCatalog(from: decoder)) ?? SourceCatalog(name: "", url: "")
    }
}

private struct WrappedSourceImportItems: Decodable {
    let items: [AnySourceImportItem]

    /// Container keys seen in Legado exports, third-party repositories, and
    /// HTTP API responses. The first non-empty array wins, so mixed envelopes
    /// do not depend on JSON key order.
    private static let arrayKeys = [
        "sources", "bookSources", "bookSourceList", "sourceList",
        "list", "items", "rows", "records", "result", "data"
    ]
    /// Envelopes that wrap the real payload one or more levels deep.
    private static let nestedKeys = ["data", "result", "payload", "response"]
    /// Single-object wrappers (`{"bookSource": {...}}`).
    private static let singleKeys = [
        "bookSource", "source", "data", "sources", "bookSources", "items", "list"
    ]
    /// Guards against a maliciously deep `{data:{data:{...}}}` payload.
    private static let maxDepth = 4

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        items = Self.decodeItems(from: container, depth: 0)
    }

    private static func decodeItems(
        from container: KeyedDecodingContainer<DynamicCodingKey>,
        depth: Int
    ) -> [AnySourceImportItem] {
        for key in arrayKeys {
            if let values = try? container.decode([AnySourceImportItem].self, forKey: DynamicCodingKey(key)),
               !values.isEmpty {
                return values
            }
        }

        if depth < maxDepth {
            for key in nestedKeys {
                guard let nested = try? container.nestedContainer(
                    keyedBy: DynamicCodingKey.self,
                    forKey: DynamicCodingKey(key)
                ) else { continue }
                let values = decodeItems(from: nested, depth: depth + 1)
                if !values.isEmpty { return values }
            }
        }

        for key in singleKeys {
            if let value = try? container.decode(AnySourceImportItem.self, forKey: DynamicCodingKey(key)),
               value.kind != .unknown {
                return [value]
            }
        }
        return []
    }
}

enum SourceImportError: Error, LocalizedError, Equatable, Sendable {
    case empty
    case urlImportRequired(String)
    case unsupportedScheme
    case unknownInput
    case challengePage
    case invalidURL(String)
    case httpStatus(Int)
    case responseTooLarge(Int)
    case emptyResponse
    case notSourceJSON
    case network(String)

    var errorDescription: String? {
        switch self {
        case .empty:
            return "没有找到有效的书源。"
        case .urlImportRequired(let url):
            return "需要先下载该 URL：\(url)"
        case .unsupportedScheme:
            return "识别到导入链接，但没有找到 src/url 参数。"
        case .unknownInput:
            return "输入无法识别：既不是 JSON、HTTP URL，也不是阅读导入链接。"
        case .challengePage:
            return "下载到的是 Cloudflare/JavaScript 验证页，不是书源 JSON。请在浏览器完成验证后复制 JSON 内容导入。"
        case .invalidURL(let raw):
            return "URL 无效：\(raw)"
        case .httpStatus(let code):
            return "服务器返回 HTTP \(code)，没有返回书源内容。"
        case .responseTooLarge(let bytes):
            return "响应过大（\(bytes) 字节），已拒绝导入。"
        case .emptyResponse:
            return "服务器返回空内容。"
        case .notSourceJSON:
            return "下载内容是网页而不是书源 JSON，可能是错误页、登录页或需要验证。"
        case .network(let message):
            return "下载失败：\(message)"
        }
    }
}
