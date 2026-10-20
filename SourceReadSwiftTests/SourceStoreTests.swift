import XCTest
@testable import SourceReadSwift

@MainActor
final class SourceStoreTests: XCTestCase {
    func testRestoresCompleteSourceLibrarySnapshot() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = SourceStore(persistence: SourcePersistence(fileManager: .default, rootURL: root))
        let source = BookSource(bookSourceName: "恢复源", bookSourceUrl: "https://restore.example")
        let rss = RSSSource(sourceName: "恢复 RSS", sourceUrl: "https://restore.example/rss")
        let catalog = SourceCatalog(name: "恢复仓库", url: "https://restore.example/catalog.json")
        XCTAssertTrue(store.restore(SourceLibrarySnapshot(sources: [source], rssSources: [rss], catalogs: [catalog])))
        let reloaded = SourceStore(persistence: SourcePersistence(fileManager: .default, rootURL: root))
        XCTAssertEqual(reloaded.sources.map(\.bookSourceUrl), [source.bookSourceUrl])
        XCTAssertEqual(reloaded.rssSources.map(\.sourceUrl), [rss.sourceUrl])
        XCTAssertEqual(reloaded.catalogs.map(\.url), [catalog.url])
        try? FileManager.default.removeItem(at: root)
    }

    func testImportSingleSource() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = SourceStore(persistence: SourcePersistence(fileManager: .default, rootURL: root))
        let json = """
        {
          "bookSourceName": "测试源",
          "bookSourceUrl": "https://example.test",
          "searchUrl": "https://example.test/search?q={{keyword}}"
        }
        """

        try store.importJSON(json)

        XCTAssertNotNil(store.source(for: "https://example.test"))
        try? FileManager.default.removeItem(at: root)
    }

    func testImportsSourcesFromItemsWrapper() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = SourceStore(persistence: SourcePersistence(fileManager: .default, rootURL: root))
        let json = """
        {
          "items": [
            {
              "bookSourceName": "Items wrapped source",
              "bookSourceUrl": "https://items.example.com",
              "searchUrl": "/search?q={{key}}",
              "ruleSearch": { "bookList": "data.list", "name": "title" }
            }
          ]
        }
        """

        try store.importJSON(json)

        XCTAssertEqual(store.sources.count, 1)
        XCTAssertEqual(store.sources.first?.bookSourceName, "Items wrapped source")
        try? FileManager.default.removeItem(at: root)
    }

    func testImportsSingleBookSourceFromWrapper() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = SourceStore(persistence: SourcePersistence(fileManager: .default, rootURL: root))
        let json = """
        {
          "bookSource": {
            "bookSourceName": "Single wrapped source",
            "bookSourceUrl": "https://single-wrapper.example.com",
            "searchUrl": "/search?q={{key}}"
          }
        }
        """

        try store.importJSON(json)

        XCTAssertEqual(store.sources.count, 1)
        XCTAssertEqual(store.sources.first?.bookSourceName, "Single wrapped source")
        try? FileManager.default.removeItem(at: root)
    }

    func testImportsJSONExtractedFromBrowserText() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = SourceStore(persistence: SourcePersistence(fileManager: .default, rootURL: root))
        let json = """
        header text
        [
          {
            "bookSourceName": "Browser extracted source",
            "bookSourceUrl": "https://browser.example.com",
            "searchUrl": "/search?q={{key}}",
            "ruleSearch": { "bookList": "data.list", "name": "title" }
          }
        ]
        footer text
        """

        try store.importJSON(json)

        XCTAssertEqual(store.sources.count, 1)
        XCTAssertEqual(store.sources.first?.bookSourceName, "Browser extracted source")
        try? FileManager.default.removeItem(at: root)
    }

    func testImportsBookSourceAliasesFromSharedJSON() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = SourceStore(persistence: SourcePersistence(fileManager: .default, rootURL: root))
        let json = """
        [
          {
            "sourceName": "Alias Source",
            "sourceUrl": "https://alias.example.com",
            "sourceGroup": "Group A",
            "rulesSearch": {
              "bookList": "$.data.list[*]",
              "name": "title",
              "bookUrl": "/detail?id={{bookId}}"
            },
            "rulesToc": {
              "chapterList": "chapters",
              "chapterName": "name",
              "chapterUrl": "url"
            },
            "ruleBookContent": { "content": "data.content" }
          }
        ]
        """

        try store.importJSON(json)

        let source = try XCTUnwrap(store.sources.first)
        XCTAssertEqual(source.bookSourceName, "Alias Source")
        XCTAssertEqual(source.bookSourceGroup, "Group A")
        XCTAssertEqual(source.ruleSearch?.fields["bookList"], "$.data.list[*]")
        XCTAssertEqual(source.ruleContent?.fields["content"], "data.content")
        try? FileManager.default.removeItem(at: root)
    }

    func testImportsExtendedBookSourceFieldsForSwiftEngine() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = SourceStore(persistence: SourcePersistence(fileManager: .default, rootURL: root))

        try store.importJSON("""
        [
          {
            "bookSourceName": "Extended Source",
            "bookSourceUrl": "https://extended.example.com",
            "bookSourceType": 0,
            "enabled": "false",
            "weight": 7,
            "searchUrl": "/search?q={{key}}",
            "exploreUrl": "/rank/{{page}}",
            "ruleExplore": { "bookList": "data.books", "name": "title" },
            "header": "{\\"User-Agent\\":\\"UnitTest\\"}",
            "customConfig": "{\\"charset\\":\\"gbk\\"}"
          }
        ]
        """)

        let source = try XCTUnwrap(store.sources.first)
        XCTAssertEqual(source.bookSourceType, 0)
        XCTAssertFalse(source.enabled)
        XCTAssertEqual(source.weight, 7)
        XCTAssertEqual(source.exploreUrl, "/rank/{{page}}")
        XCTAssertEqual(source.ruleExplore?.fields["bookList"], "data.books")
        XCTAssertEqual(source.header, "{\"User-Agent\":\"UnitTest\"}")
        XCTAssertEqual(source.customConfig, "{\"charset\":\"gbk\"}")
        try? FileManager.default.removeItem(at: root)
    }

    func testUpdatesDuplicateBookSourceByURL() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = SourceStore(persistence: SourcePersistence(fileManager: .default, rootURL: root))

        try store.importJSON("""
        [
          {
            "bookSourceName": "Old Name",
            "bookSourceUrl": "https://dup.example.com",
            "searchUrl": "/old?q={{key}}",
            "ruleSearch": { "bookList": "data.list", "name": "title" }
          }
        ]
        """)
        try store.importJSON("""
        [
          {
            "bookSourceName": "New Name",
            "bookSourceUrl": "https://dup.example.com",
            "searchUrl": "/new?q={{key}}",
            "ruleSearch": { "bookList": "data.items", "name": "name" }
          }
        ]
        """)

        XCTAssertEqual(store.sources.count, 1)
        XCTAssertEqual(store.sources.first?.bookSourceName, "New Name")
        XCTAssertEqual(store.sources.first?.searchUrl, "/new?q={{key}}")
        try? FileManager.default.removeItem(at: root)
    }

    func testImportReportCountsAddedAndUpdatedItems() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = SourceStore(persistence: SourcePersistence(fileManager: .default, rootURL: root))

        let first = try store.importJSON("""
        [
          {
            "bookSourceName": "First",
            "bookSourceUrl": "https://report.example.com/one",
            "searchUrl": "/search?q={{key}}"
          }
        ]
        """)

        let second = try store.importJSON("""
        [
          {
            "bookSourceName": "First Updated",
            "bookSourceUrl": "https://report.example.com/one",
            "searchUrl": "/new?q={{key}}"
          },
          {
            "bookSourceName": "Second",
            "bookSourceUrl": "https://report.example.com/two",
            "searchUrl": "/search?q={{key}}"
          }
        ]
        """)

        XCTAssertEqual(first.addedBookSources, 1)
        XCTAssertEqual(first.updatedBookSources, 0)
        XCTAssertEqual(second.addedBookSources, 1)
        XCTAssertEqual(second.updatedBookSources, 1)
        XCTAssertEqual(store.sources.count, 2)
        try? FileManager.default.removeItem(at: root)
    }

    func testUpsertsBookSourceFromEditedJSON() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = SourceStore(persistence: SourcePersistence(fileManager: .default, rootURL: root))

        try store.importJSON("""
        {
          "bookSourceName": "Before Edit",
          "bookSourceUrl": "https://edit.example.com",
          "searchUrl": "/old?q={{key}}"
        }
        """)

        let updated = try store.upsertBookSourceJSON("""
        {
          "bookSourceName": "After Edit",
          "bookSourceUrl": "https://edit.example.com",
          "searchUrl": "/new?q={{key}}",
          "ruleSearch": { "bookList": ".book", "name": ".title" }
        }
        """)

        XCTAssertEqual(updated.bookSourceName, "After Edit")
        XCTAssertEqual(store.sources.count, 1)
        XCTAssertEqual(store.sources.first?.bookSourceName, "After Edit")
        XCTAssertEqual(store.sources.first?.ruleSearch?.fields["bookList"], ".book")
        try? FileManager.default.removeItem(at: root)
    }

    func testSmartImportParsesPastedJSON() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = SourceStore(persistence: SourcePersistence(fileManager: .default, rootURL: root))

        let parsed = try store.importSmartInput("""
        [
          {
            "bookSourceName": "Smart Source",
            "bookSourceUrl": "https://smart.example.com",
            "searchUrl": "/search?q={{key}}"
          }
        ]
        """)

        XCTAssertEqual(parsed.kind, .json)
        XCTAssertEqual(store.sources.count, 1)
        XCTAssertEqual(store.sources.first?.bookSourceName, "Smart Source")
        try? FileManager.default.removeItem(at: root)
    }

    func testImportsCatalogSeparatelyFromRSS() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = SourceStore(persistence: SourcePersistence(fileManager: .default, rootURL: root))

        try store.importJSON("""
        [
          {
            "sourceName": "Yiove Catalog",
            "sourceUrl": "https://shuyuan.yiove.com",
            "sourceGroup": "Sources",
            "sourceComment": "Catalog home"
          }
        ]
        """)

        XCTAssertEqual(store.catalogs.count, 1)
        XCTAssertEqual(store.rssSources.count, 0)
        XCTAssertEqual(store.sources.count, 0)
        XCTAssertEqual(store.catalogs.first?.name, "Yiove Catalog")
        try? FileManager.default.removeItem(at: root)
    }

    func testRecordsCatalogImportStatus() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = SourceStore(persistence: SourcePersistence(fileManager: .default, rootURL: root))

        try store.importJSON("""
        {
          "name": "Catalog",
          "url": "https://catalog.example.com/list.json",
          "importUrl": "https://catalog.example.com/sources.json"
        }
        """)

        store.recordCatalogImport(
            url: "https://catalog.example.com/list.json",
            report: SourceImportReport(addedBookSources: 2, updatedBookSources: 1)
        )

        let catalog = try XCTUnwrap(store.catalogs.first)
        XCTAssertEqual(catalog.importedCount, 3)
        XCTAssertTrue(catalog.lastStatus?.contains("新增 2") == true)
        XCTAssertNotNil(catalog.lastImportedAt)

        let reloaded = SourceStore(persistence: SourcePersistence(fileManager: .default, rootURL: root))
        let persisted = try XCTUnwrap(reloaded.catalogs.first)
        XCTAssertEqual(persisted.importedCount, 3)
        XCTAssertEqual(persisted.lastStatus, catalog.lastStatus)
        XCTAssertNotNil(persisted.lastImportedAt)
        try? FileManager.default.removeItem(at: root)
    }

    func testImportsMixedBookSourceRSSAndCatalog() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = SourceStore(persistence: SourcePersistence(fileManager: .default, rootURL: root))

        try store.importJSON("""
        {
          "items": [
            {
              "bookSourceName": "Book Source",
              "bookSourceUrl": "https://book.example.com",
              "searchUrl": "/search?q={{key}}",
              "ruleSearch": { "bookList": "data.list", "name": "title" }
            },
            {
              "sourceName": "RSS Source",
              "sourceUrl": "https://news.example.com/feed.xml",
              "ruleArticles": "channel.item",
              "ruleTitle": "title"
            },
            {
              "sourceName": "Catalog Source",
              "sourceUrl": "https://catalog.example.com/sources.json",
              "importUrl": "https://catalog.example.com/sources.json"
            }
          ]
        }
        """)

        XCTAssertEqual(store.sources.count, 1)
        XCTAssertEqual(store.rssSources.count, 1)
        XCTAssertEqual(store.catalogs.count, 1)
        XCTAssertEqual(store.sources.first?.bookSourceName, "Book Source")
        XCTAssertEqual(store.rssSources.first?.sourceName, "RSS Source")
        XCTAssertEqual(store.catalogs.first?.name, "Catalog Source")
        try? FileManager.default.removeItem(at: root)
    }

    func testPersistsRSSAndCatalogsWithBookSources() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = SourceStore(persistence: SourcePersistence(fileManager: .default, rootURL: root))

        try store.importJSON("""
        [
          {
            "bookSourceName": "Book Source",
            "bookSourceUrl": "https://book.example.com",
            "searchUrl": "/search?q={{key}}"
          },
          {
            "sourceName": "RSS Source",
            "sourceUrl": "https://news.example.com/rss",
            "ruleArticles": "items"
          },
          {
            "sourceName": "Catalog Source",
            "sourceUrl": "https://shuyuan.example.com"
          }
        ]
        """)

        let reloaded = SourceStore(persistence: SourcePersistence(fileManager: .default, rootURL: root))

        XCTAssertEqual(reloaded.sources.count, 1)
        XCTAssertEqual(reloaded.rssSources.count, 1)
        XCTAssertEqual(reloaded.catalogs.count, 1)
        try? FileManager.default.removeItem(at: root)
    }

    func testClassifiesPlainFeedURLAsRSS() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = SourceStore(persistence: SourcePersistence(fileManager: .default, rootURL: root))

        try store.importJSON("""
        [
          {
            "sourceName": "Plain Feed",
            "sourceUrl": "https://example.com/feed.xml"
          }
        ]
        """)

        XCTAssertEqual(store.rssSources.count, 1)
        XCTAssertEqual(store.catalogs.count, 0)
        try? FileManager.default.removeItem(at: root)
    }

    func testClassifiesPlainSourceNameAsCatalogInsteadOfRSS() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = SourceStore(persistence: SourcePersistence(fileManager: .default, rootURL: root))

        try store.importJSON("""
        [
          {
            "sourceName": "Plain Catalog",
            "sourceUrl": "https://catalog.example.com"
          }
        ]
        """)

        XCTAssertEqual(store.catalogs.count, 1)
        XCTAssertEqual(store.rssSources.count, 0)
        try? FileManager.default.removeItem(at: root)
    }

    func testSourceSwitchCandidatesPrioritizePatternAndWeight() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = SourceStore(persistence: SourcePersistence(fileManager: .default, rootURL: root))

        try store.importJSON("""
        [
          {
            "bookSourceName": "Fallback",
            "bookSourceUrl": "https://fallback.example.com",
            "searchUrl": "/search?q={{key}}",
            "weight": 100
          },
          {
            "bookSourceName": "Low Pattern",
            "bookSourceUrl": "https://low.example.com",
            "searchUrl": "/search?q={{key}}",
            "weight": 1,
            "bookUrlPattern": "books\\\\.example/\\\\d+"
          },
          {
            "bookSourceName": "High Pattern",
            "bookSourceUrl": "https://high.example.com",
            "searchUrl": "/search?q={{key}}",
            "weight": 10,
            "bookUrlPattern": "books\\\\.example/\\\\d+"
          }
        ]
        """)

        let candidates = store.sourceSwitchCandidates(
            for: "https://books.example/123",
            excluding: "https://current.example.com"
        )

        XCTAssertEqual(candidates.map(\.bookSourceName), ["High Pattern", "Low Pattern", "Fallback"])
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Specialized adapter dispatch (sync/async parity)

    func testAsyncImportHuaHuoSourceUsesSpecializedAdapter() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = SourceStore(persistence: SourcePersistence(fileManager: .default, rootURL: root))
        let json = """
        [
          {
            "sourceName": "花火测试源",
            "sourceUrl": "https://huahuo.test.org",
            "sourceGroup": "精品推荐",
            "searchUrl": "https://huahuo.test.org/search?q={{key}}",
            "ruleSearch": {
              "searchBookList": "ul.list li",
              "searchName": ".name@text",
              "searchAuthor": ".author@text",
              "searchBookUrl": ".link@href"
            },
            "ruleToc": {
              "tocList": "#chapters a",
              "tocName": "text",
              "tocUrl": "href"
            },
            "ruleContent": {
              "content": "#art-content@text"
            }
          }
        ]
        """

        let report = try await store.importJSONDataAsync(Data(json.utf8))

        XCTAssertEqual(report.addedBookSources, 1)
        let source = try XCTUnwrap(store.source(for: "https://huahuo.test.org"))
        XCTAssertEqual(source.sourceFormat, .huahuo)
        XCTAssertEqual(source.ruleSearch?.fields["bookList"], "ul.list li")
        XCTAssertEqual(source.ruleToc?.fields["chapterList"], "#chapters a")
        XCTAssertEqual(source.ruleContent?.fields["content"], "#art-content@text")
        try? FileManager.default.removeItem(at: root)
    }

    func testAsyncImportHaiKuoSourceUsesSpecializedAdapter() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = SourceStore(persistence: SourcePersistence(fileManager: .default, rootURL: root))
        let json = """
        [
          {
            "title": "海阔小说源",
            "url": "https://haikuo.novel.org",
            "group": "海阔影视",
            "search_url": "https://haikuo.novel.org/s?wd={{key}}",
            "search_rule": ".search-results li",
            "find_url": "https://haikuo.novel.org/category",
            "find_rule": ".category-list li",
            "ua": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)"
          }
        ]
        """

        let report = try await store.importJSONDataAsync(Data(json.utf8))

        XCTAssertEqual(report.addedBookSources, 1)
        let source = try XCTUnwrap(store.source(for: "https://haikuo.novel.org"))
        XCTAssertEqual(source.sourceFormat, .haikuo)
        XCTAssertEqual(source.searchUrl, "https://haikuo.novel.org/s?wd={{key}}")
        XCTAssertEqual(source.ruleSearch?.fields["bookList"], ".search-results li")
        XCTAssertEqual(source.ruleExplore?.fields["bookList"], ".category-list li")
        XCTAssertTrue(source.header?.contains("iPhone") == true)
        try? FileManager.default.removeItem(at: root)
    }

    func testSyncAndAsyncImportsProduceIdenticalSpecializedSources() async throws {
        let rootA = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let rootB = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let syncStore = SourceStore(persistence: SourcePersistence(fileManager: .default, rootURL: rootA))
        let asyncStore = SourceStore(persistence: SourcePersistence(fileManager: .default, rootURL: rootB))
        let json = """
        [
          {
            "sourceName": "花火对等源",
            "sourceUrl": "https://huahuo.parity.org",
            "sourceGroup": "对等",
            "searchUrl": "https://huahuo.parity.org/search?q={{key}}",
            "ruleSearch": {
              "searchBookList": ".item",
              "searchName": ".title@text",
              "searchBookUrl": "a@href"
            },
            "ruleToc": {
              "tocList": ".chapter a",
              "tocName": "text",
              "tocUrl": "href"
            },
            "ruleContent": {
              "content": "#content@text"
            }
          }
        ]
        """

        try syncStore.importJSON(json)
        _ = try await asyncStore.importJSONDataAsync(Data(json.utf8))

        XCTAssertEqual(syncStore.sources.map(\.bookSourceUrl), asyncStore.sources.map(\.bookSourceUrl))
        XCTAssertEqual(syncStore.sources.map(\.sourceFormat), asyncStore.sources.map(\.sourceFormat))
        XCTAssertEqual(syncStore.sources.map(\.ruleSearch), asyncStore.sources.map(\.ruleSearch))
        XCTAssertEqual(syncStore.sources.map(\.ruleToc), asyncStore.sources.map(\.ruleToc))
        XCTAssertEqual(syncStore.sources.map(\.ruleContent), asyncStore.sources.map(\.ruleContent))
        try? FileManager.default.removeItem(at: rootA)
        try? FileManager.default.removeItem(at: rootB)
    }

    func testAsyncImportGenericLegadoJSONKeepsLegadoFormat() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = SourceStore(persistence: SourcePersistence(fileManager: .default, rootURL: root))
        let json = """
        [
          {
            "bookSourceName": "通用 Legado 源",
            "bookSourceUrl": "https://legado.async.example",
            "bookSourceGroup": "普通分组",
            "searchUrl": "/search?q={{key}}",
            "ruleSearch": {
              "bookList": "data.list",
              "name": "title",
              "bookUrl": "url"
            }
          }
        ]
        """

        _ = try await store.importJSONDataAsync(Data(json.utf8))

        let source = try XCTUnwrap(store.source(for: "https://legado.async.example"))
        XCTAssertEqual(source.sourceFormat, .legado)
        XCTAssertEqual(source.ruleSearch?.fields["bookList"], "data.list")
        try? FileManager.default.removeItem(at: root)
    }

    func testImportsNestedDataBookSourcesEnvelope() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = SourceStore(persistence: SourcePersistence(fileManager: .default, rootURL: root))
        let json = """
        {
          "code": 0,
          "message": "ok",
          "data": {
            "bookSources": [
              {
                "bookSourceName": "Nested Data Source",
                "bookSourceUrl": "https://nested-data.example",
                "searchUrl": "/search?q={{key}}"
              }
            ]
          }
        }
        """

        try store.importJSON(json)

        XCTAssertEqual(store.sources.map(\.bookSourceName), ["Nested Data Source"])
        XCTAssertEqual(store.catalogs.count, 0)
        try? FileManager.default.removeItem(at: root)
    }

    func testImportsBookSourceListAndSourceListEnvelopes() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = SourceStore(persistence: SourcePersistence(fileManager: .default, rootURL: root))
        let json = """
        {
          "bookSourceList": [
            { "bookSourceName": "List A", "bookSourceUrl": "https://list-a.example" }
          ],
          "sourceList": [
            { "bookSourceName": "List B", "bookSourceUrl": "https://list-b.example" }
          ]
        }
        """

        try store.importJSON(json)

        XCTAssertEqual(store.sources.count, 1)
        XCTAssertEqual(store.sources.first?.bookSourceName, "List A")
        try? FileManager.default.removeItem(at: root)
    }

    func testImportsResultRowsEnvelope() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = SourceStore(persistence: SourcePersistence(fileManager: .default, rootURL: root))
        let json = """
        {
          "result": {
            "rows": [
              {
                "bookSourceName": "Row Source",
                "bookSourceUrl": "https://rows.example",
                "ruleToc": { "chapterList": "ul li" }
              }
            ]
          }
        }
        """

        try store.importJSON(json)

        XCTAssertEqual(store.sources.map(\.bookSourceName), ["Row Source"])
        XCTAssertNotNil(store.sources.first?.ruleToc)
        try? FileManager.default.removeItem(at: root)
    }

    func testImportsNestedSingleBookSourceEnvelope() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = SourceStore(persistence: SourcePersistence(fileManager: .default, rootURL: root))
        let json = """
        {
          "data": {
            "bookSource": {
              "bookSourceName": "Nested Single",
              "bookSourceUrl": "https://nested-single.example"
            }
          }
        }
        """

        try store.importJSON(json)

        XCTAssertEqual(store.sources.map(\.bookSourceName), ["Nested Single"])
        try? FileManager.default.removeItem(at: root)
    }

    func testClassifiesAliasOnlyBookSourceInsteadOfCatalog() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = SourceStore(persistence: SourcePersistence(fileManager: .default, rootURL: root))
        let json = """
        [
          {
            "name": "Alias Source",
            "url": "https://alias.example",
            "searchUrl": "/search?q={{key}}",
            "ruleSearch": { "bookList": "data.list", "name": "title" }
          }
        ]
        """

        try store.importJSON(json)

        XCTAssertEqual(store.sources.map(\.bookSourceName), ["Alias Source"])
        XCTAssertEqual(store.catalogs.count, 0)
        XCTAssertNotNil(store.sources.first?.ruleSearch)
        try? FileManager.default.removeItem(at: root)
    }

    func testClassifiesGenericDialectRuleObjectAsBookSource() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = SourceStore(persistence: SourcePersistence(fileManager: .default, rootURL: root))
        let json = """
        [
          {
            "name": "Dialect Source",
            "url": "https://dialect.example",
            "search": { "path": "/search", "list": "data" }
          }
        ]
        """

        try store.importJSON(json)

        XCTAssertEqual(store.sources.map(\.bookSourceName), ["Dialect Source"])
        XCTAssertEqual(store.catalogs.count, 0)
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Legacy encoding normalization

    func testNormalizeDataStaticDecodesGBKToUTF8() throws {
        let json = #"[{"bookSourceName":"中文书源","bookSourceUrl":"https://gbk.example","searchUrl":"https://gbk.example/s?q={{keyword}}"}]"#
        let gbkData = try XCTUnwrap(LegadoCharset.encode(json, charset: "gbk"))
        XCTAssertNil(String(data: gbkData, encoding: .utf8))

        let normalized = try SourceStore.normalizeDataStatic(gbkData)
        XCTAssertEqual(String(data: normalized, encoding: .utf8), json)
    }

    func testSanitizeTrailingCommasLeavesLegacyEncodedBytesUntouched() throws {
        let json = #"[{"bookSourceName":"中文书源"}]"#
        let gbkData = try XCTUnwrap(LegadoCharset.encode(json, charset: "gbk"))
        XCTAssertEqual(SourceStore.sanitizeTrailingCommasData(gbkData), gbkData)
    }

    func testStoreImportsGBKDataDirectly() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = SourceStore(persistence: SourcePersistence(fileManager: .default, rootURL: root))
        let json = #"[{"bookSourceName":"中文书源","bookSourceUrl":"https://gbk.example","searchUrl":"https://gbk.example/s?q={{keyword}}"}]"#
        let gbkData = try XCTUnwrap(LegadoCharset.encode(json, charset: "gbk"))

        _ = try await store.importJSONDataAsync(gbkData)

        XCTAssertEqual(store.sources.map(\.bookSourceName), ["中文书源"])
        XCTAssertEqual(store.sources.map(\.bookSourceUrl), ["https://gbk.example"])
        try? FileManager.default.removeItem(at: root)
    }
}
