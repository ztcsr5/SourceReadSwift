import XCTest
@testable import SourceReadSwift

final class JSONRuleExtractorTests: XCTestCase {
    func testExtractListAndFieldsByRule() throws {
        let object: [String: Any] = [
            "data": [
                "books": [
                    ["title": "斗破苍穹", "writer": "天蚕土豆", "id": "765"]
                ]
            ]
        ]
        let extractor = JSONRuleExtractor()
        let list = extractor.list(from: object, rule: "data.books")

        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(extractor.string(from: list[0], rule: "title", fallbackKeys: []), "斗破苍穹")
        XCTAssertEqual(extractor.string(from: list[0], rule: "writer", fallbackKeys: []), "天蚕土豆")
    }

    func testNormalizeLegadoAndRule() throws {
        let object: [String: Any] = [
            "Data": [
                "Books": [
                    ["Name": "斗破苍穹", "BookId": 1209977]
                ]
            ]
        ]
        let extractor = JSONRuleExtractor()
        let list = extractor.list(from: object, rule: "Data&&Books")

        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(extractor.string(from: list[0], rule: "Name", fallbackKeys: []), "斗破苍穹")
        XCTAssertEqual(extractor.string(from: list[0], rule: "BookId", fallbackKeys: []), "1209977")
    }

    func testSameLevelAndRulesKeepMergeSemantics() throws {
        let object: [String: Any] = ["a": "A", "b": "B"]
        let extractor = JSONRuleExtractor()

        XCTAssertEqual(extractor.stringList(from: object, rule: "a&&b"), ["A", "B"])
    }

    func testExtractBracketNotationPath() throws {
        let title = "\u{6597}\u{7834}\u{82cd}\u{7a79}"
        let object: [String: Any] = [
            "data": [
                "books": [
                    ["title": title]
                ]
            ]
        ]

        let value = JSONRuleExtractor().value(from: object, path: "$.data.books[0].title") as? String

        XCTAssertEqual(value, title)
    }

    func testExtractQuotedBracketPath() throws {
        let title = "\u{6597}\u{7834}\u{82cd}\u{7a79}"
        let object: [String: Any] = [
            "data": [
                "book-list": [
                    ["title": title]
                ]
            ]
        ]

        let value = JSONRuleExtractor().value(from: object, path: "$['data']['book-list'][0]['title']") as? String

        XCTAssertEqual(value, title)
    }

    func testExtractArrayIndexPath() throws {
        let extractor = JSONRuleExtractor()
        let object: [String: Any] = [
            "data": [
                "items": [
                    ["title": "First"],
                    ["title": "Second"]
                ]
            ]
        ]

        let value = extractor.value(from: object, path: "$.data.items[1].title") as? String
        XCTAssertEqual(value, "Second")
    }

    func testExtractWildcardPathReturnsFieldArray() throws {
        let extractor = JSONRuleExtractor()
        let object: [String: Any] = [
            "data": [
                "items": [
                    ["title": "First"],
                    ["title": "Second"]
                ]
            ]
        ]

        let value = extractor.value(from: object, path: "$.data.items[*].title") as? [Any]
        XCTAssertEqual(value as? [String], ["First", "Second"])
    }

    func testExtractNegativeArrayIndex() throws {
        let extractor = JSONRuleExtractor()
        let object: [String: Any] = [
            "data": [
                "items": [
                    ["title": "First"],
                    ["title": "Second"]
                ]
            ]
        ]

        let value = extractor.value(from: object, path: "$.data.items[-1].title") as? String
        XCTAssertEqual(value, "Second")
    }

    func testExtractAtSuffixAsPathSegment() throws {
        let extractor = JSONRuleExtractor()
        let object: [String: Any] = [
            "data": [
                "book": [
                    "name": "Title"
                ]
            ]
        ]

        let value = extractor.value(from: object, path: "$.data.book@name") as? String
        XCTAssertEqual(value, "Title")
    }

    func testRegexTransformCleansJSONValue() throws {
        let extractor = JSONRuleExtractor()
        let object: [String: Any] = [
            "data": [
                "intro": "<p>Hello</p>"
            ]
        ]

        let value = extractor.value(from: object, path: "$.data.intro##<[^>]+>##") as? String
        XCTAssertEqual(value, "Hello")
    }

    func testArrayFieldIsFlattenedWhenTraversing() throws {
        let extractor = JSONRuleExtractor()
        let object: [String: Any] = [
            "data": [
                "groups": [
                    ["books": [["title": "A"], ["title": "B"]]],
                    ["books": [["title": "C"]]]
                ]
            ]
        ]

        let value = extractor.value(from: object, path: "$.data.groups.books.title") as? [Any]
        XCTAssertEqual(value as? [String], ["A", "B", "C"])
    }

    func testFallbackOperatorIgnoresNestedQuotedOperatorText() throws {
        let extractor = JSONRuleExtractor()
        let object: [String: Any] = [
            "data": [
                "a||b": "Primary",
                "fallback": "Fallback"
            ]
        ]

        let value = extractor.value(from: object, path: "$['data']['a||b'] || $.data.fallback") as? String
        XCTAssertEqual(value, "Primary")
    }

    func testMergeOperatorCombinesJSONArraysForStringExtraction() throws {
        let extractor = JSONRuleExtractor()
        let object: [String: Any] = [
            "data": [
                "free": [["title": "A"], ["title": "C"]],
                "vip": [["title": "B"], ["title": "D"]]
            ]
        ]

        let value = extractor.string(
            from: object,
            rule: "$.data.free.title%%$.data.vip.title",
            fallbackKeys: []
        )

        XCTAssertEqual(value, "A\nB\nC\nD")
    }

    func testPutAndGetDirectivesShareJSONValuesAcrossRules() throws {
        let extractor = JSONRuleExtractor()
        let object: [String: Any] = [
            "data": [
                "prefix": "book",
                "book": [
                    "title": "Title"
                ]
            ]
        ]

        _ = extractor.value(from: object, path: "@put:{key:$.data.prefix}$.data.prefix")
        let value = extractor.value(from: object, path: "$.data.@get:{key}.title") as? String

        XCTAssertEqual(value, "Title")
    }

    func testDirectGetDirectiveReturnsStoredJSONValue() throws {
        let extractor = JSONRuleExtractor()
        let object: [String: Any] = [
            "data": [
                "items": [
                    ["title": "A"],
                    ["title": "B"]
                ]
            ]
        ]

        _ = extractor.value(from: object, path: "@put:{items:$.data.items}$.data.items")
        let value = extractor.value(from: object, path: "@get:{items}") as? [[String: Any]]

        XCTAssertEqual(value?.count, 2)
        XCTAssertEqual(value?.first?["title"] as? String, "A")
    }

    func testPutDirectiveSplitsQuotedJSONRuleSafely() throws {
        let extractor = JSONRuleExtractor()
        let object: [String: Any] = [
            "data": [
                "a,b:c": "Primary"
            ]
        ]

        _ = extractor.value(from: object, path: #"@put:{"key":"$['data']['a,b:c']"}$.data"#)
        let value = extractor.value(from: object, path: "@get:{key}") as? String

        XCTAssertEqual(value, "Primary")
    }

    func testFilterPredicatesSelectTruthyEqualAndNotEqualNodes() throws {
        let extractor = JSONRuleExtractor()
        let object: [String: Any] = [
            "data": [
                "list": [
                    ["title": "A", "hasContent": 1, "source": "free"],
                    ["title": "B", "hasContent": 0, "source": "vip"],
                    ["title": "C", "hasContent": true, "source": "free"]
                ]
            ]
        ]

        let truthy = extractor.list(from: object, rule: "$.data.list[?(@.hasContent)]")
        let equals = extractor.list(from: object, rule: "$.data.list[?(@.hasContent==1)]")
        let notEquals = extractor.list(from: object, rule: #"$.data.list[?(@.source!="vip")]"#)

        XCTAssertEqual(truthy.compactMap { $0["title"] as? String }, ["A", "C"])
        XCTAssertEqual(equals.compactMap { $0["title"] as? String }, ["A"])
        XCTAssertEqual(notEquals.compactMap { $0["title"] as? String }, ["A", "C"])
    }

    func testFilterPredicatesSupportGreaterLessAndMissingValues() throws {
        let extractor = JSONRuleExtractor()
        let object: [String: Any] = [
            "data": [
                "list": [
                    ["title": "Low", "score": 2],
                    ["title": "High", "score": 10],
                    ["title": "Missing", "score": NSNull()]
                ]
            ]
        ]

        let high = extractor.list(from: object, rule: "$.data.list[?(@.score>=10)]")
        let low = extractor.list(from: object, rule: "$.data.list[?(@.score<10)]")

        XCTAssertEqual(high.compactMap { $0["title"] as? String }, ["High"])
        XCTAssertEqual(low.compactMap { $0["title"] as? String }, ["Low"])
    }

    func testFilterPredicateSupportsNestedArrayPathAndScalarList() throws {
        let extractor = JSONRuleExtractor()
        let object: [String: Any] = [
            "payload": [
                "items": [
                    ["meta": ["kind": "book"], "name": "A"],
                    ["meta": ["kind": "note"], "name": "B"]
                ],
                "tags": ["one", "two"]
            ]
        ]

        let books = extractor.list(from: object, rule: "$.payload.items[?(@.meta.kind=='book')]")
        XCTAssertEqual(books.compactMap { $0["name"] as? String }, ["A"])
        XCTAssertEqual(extractor.string(from: object, rule: "$.payload.tags[*]", fallbackKeys: []), "one\ntwo")
    }

    func testRecursiveDescentFindsNestedBookLists() throws {
        let object: [String: Any] = [
            "payload": [
                "nested": [
                    "bookList": [
                        ["name": "A"],
                        ["name": "B"]
                    ]
                ]
            ]
        ]

        let list = JSONRuleExtractor().list(from: object, rule: "$..bookList[*]")

        XCTAssertEqual(list.compactMap { $0["name"] as? String }, ["A", "B"])
    }

    func testMultiVolumeChapterListFlattening() throws {
        let object: [String: Any] = [
            "data": [
                "chapterListWithVolume": [
                    [
                        ["chapter_title": "第一章 初始", "chapter_id": "101"],
                        ["chapter_title": "第二章 进阶", "chapter_id": "102"]
                    ],
                    [
                        ["chapter_title": "第三章 终局", "chapter_id": "103"]
                    ]
                ]
            ]
        ]

        let extractor = JSONRuleExtractor()
        let list = extractor.list(from: object, rule: "$.data.chapterListWithVolume[*].*")

        XCTAssertEqual(list.count, 3)
        XCTAssertEqual(list.compactMap { $0["chapter_title"] as? String }, ["第一章 初始", "第二章 进阶", "第三章 终局"])
    }

    func testURLTemplateInterpolationNotTreatedAsJSONPath() throws {
        let item: [String: Any] = [
            "id": "7549045718187510846",
            "source": "fanqie"
        ]
        let extractor = JSONRuleExtractor()
        let rule = "https://www.mowan.lol/api/book/detail?source={{$.source}}&book_id={{$.id}}##comment"
        let result = extractor.string(from: item, rule: rule, fallbackKeys: ["id"])
        XCTAssertEqual(result, "https://www.mowan.lol/api/book/detail?source=fanqie&book_id=7549045718187510846")
    }

    func testCaseInsensitiveFallbackKey() throws {
        let item: [String: Any] = [
            "chaptername": "第一章 初始"
        ]
        let extractor = JSONRuleExtractor()
        let result = extractor.string(from: item, rule: nil, fallbackKeys: ["chapterName"])
        XCTAssertEqual(result, "第一章 初始")
    }

    func testRegexTransformReplaceAllKeepsLegadoSemantics() throws {
        let extractor = JSONRuleExtractor()
        let object: [String: Any] = ["text": "a a a"]

        XCTAssertEqual(extractor.value(from: object, path: "$.text##a##b") as? String, "b b b")
        XCTAssertEqual(extractor.value(from: object, path: "$.text##xyz##b") as? String, "a a a")
        XCTAssertEqual(extractor.value(from: object, path: "$.text##a##b###") as? String, "b")
        XCTAssertEqual(extractor.value(from: object, path: "$.text##xyz##b###") as? String, "")
    }

    func testInvalidRegexTransformFallsBackLikeLegado() throws {
        let extractor = JSONRuleExtractor()
        let object: [String: Any] = ["text": "a(b"]

        // Invalid pattern, replace-all: literal replacement.
        XCTAssertEqual(extractor.value(from: object, path: "$.text##a(##X") as? String, "Xb")
        // Invalid pattern, replace-first: return the replacement.
        XCTAssertEqual(extractor.value(from: object, path: "$.text##a(##X###") as? String, "X")
    }

    func testFilterExpressionKeepsNestedLogicalOperators() throws {
        let extractor = JSONRuleExtractor()
        let object: [String: Any] = [
            "list": [
                ["a": 1, "b": 2, "name": "match"],
                ["a": 1, "b": 3, "name": "miss"],
                ["a": 2, "b": 2, "name": "miss2"]
            ]
        ]

        let value = extractor.value(from: object, path: "$.list[?(@.a==1&&@.b==2)].name") as? String
        XCTAssertEqual(value, "match")
    }

    func testListReturnsEmptyForMissingPath() throws {
        let extractor = JSONRuleExtractor()
        let object: [String: Any] = ["data": ["books": [["title": "A"]]]]

        XCTAssertTrue(extractor.list(from: object, rule: "$.data.missing").isEmpty)
    }

    func testEvaluateRawJSPreservesObjectAsResult() throws {
        let item: [String: Any] = [
            "source_id": "42078"
        ]
        let extractor = JSONRuleExtractor()
        let rule = "$.source_id@js:\"https://www.duokan.com/hs/v0/android/fiction/book/\"+result"
        let result = extractor.string(from: item, rule: rule, fallbackKeys: [], variables: ["result": "{\"total\": 100}"])
        XCTAssertEqual(result, "https://www.duokan.com/hs/v0/android/fiction/book/42078")
    }

    func testUnionSelectorAndQuotedKeys() throws {
        let extractor = JSONRuleExtractor()
        let object: [String: Any] = [
            "data": [
                "a": ["title": "A"],
                "b": ["title": "B"],
                "a,b": ["title": "Comma"],
                "a.b:c": ["title": "Dotted"],
                "a@b": ["title": "At"]
            ]
        ]

        XCTAssertEqual(extractor.value(from: object, path: "$.data[a,b].title") as? [String], ["A", "B"])
        XCTAssertEqual(extractor.value(from: object, path: "$.data['a,b'].title") as? String, "Comma")
        XCTAssertEqual(extractor.value(from: object, path: "$.data['a.b:c'].title") as? String, "Dotted")
        XCTAssertEqual(extractor.value(from: object, path: "$.data['a@b'].title") as? String, "At")
        XCTAssertEqual(extractor.value(from: object, path: "$.data.a@title") as? String, "A")
    }

    func testFilterFunctionsAndNestedLogicalExpressions() throws {
        let extractor = JSONRuleExtractor()
        let object: [String: Any] = [
            "list": [
                ["title": "Alpha", "name": "A", "tags": ["x", "y"], "a": 1, "b": 2, "c": 3],
                ["title": "Beta", "name": "B", "tags": ["x"], "a": 1, "b": 0, "c": 3],
                ["title": "Gamma", "name": "C", "tags": ["x", "y", "z"], "a": 0, "b": 2, "c": 4]
            ]
        ]

        XCTAssertEqual(
            extractor.value(from: object, path: "$.list[?((@.a==1||@.b==2)&&@.c==3)].name") as? [String],
            ["A", "B"]
        )
        XCTAssertEqual(
            extractor.value(from: object, path: "$.list[?(length(@.tags)>=2)].name") as? [String],
            ["A", "C"]
        )
        XCTAssertEqual(
            extractor.value(from: object, path: "$.list[?(match(@.title,'^A'))].title") as? String,
            "Alpha"
        )
        XCTAssertEqual(
            extractor.value(from: object, path: "$.list[?(match(@.title,'/^b/i'))].title") as? String,
            "Beta"
        )
    }

    func testFilterNumericStringComparisonAndStrictNotEquals() throws {
        let extractor = JSONRuleExtractor()
        let object: [String: Any] = [
            "list": [
                ["n": "10", "name": "string-ten"],
                ["n": 9, "name": "number-nine"],
                ["n": "1", "name": "string-one"],
                ["n": 1, "name": "number-one"]
            ]
        ]

        XCTAssertEqual(
            extractor.value(from: object, path: "$.list[?(@.n>=10)].name") as? [String],
            ["string-ten"]
        )
        XCTAssertEqual(
            extractor.value(from: object, path: "$.list[?(@.n!=1)].name") as? [String],
            ["string-ten", "number-nine", "string-one"]
        )
    }

    func testSliceSelectorSupportsNegativeStep() throws {
        let extractor = JSONRuleExtractor()
        let object: [String: Any] = ["list": ["a", "b", "c", "d"]]

        XCTAssertEqual(extractor.value(from: object, path: "$.list[1:3]") as? [String], ["b", "c"])
        XCTAssertEqual(extractor.value(from: object, path: "$.list[::-1]") as? [String], ["d", "c", "b", "a"])
    }

    func testJSONPrefixDecodesEmbeddedPayloadBeforeFiltering() throws {
        let extractor = JSONRuleExtractor()
        let object: [String: Any] = [
            "payload": "{\"items\":[{\"ok\":true,\"name\":\"A\"},{\"ok\":false,\"name\":\"B\"}]}"
        ]

        XCTAssertEqual(
            extractor.value(from: object, path: "@json:$.payload.items[?(@.ok==true)].name") as? String,
            "A"
        )
    }

    func testJaywayFilterWordOperators() throws {
        let extractor = JSONRuleExtractor()
        let object: [String: Any] = [
            "list": [
                ["name": "Alpha", "type": "a", "tags": ["x", "y"]],
                ["name": "Beta", "type": "b", "tags": ["y"]],
                ["name": "Gamma", "type": "c", "tags": []]
            ]
        ]

        XCTAssertEqual(
            extractor.value(from: object, path: "$.list[?(@.type in ['a','b'])].name") as? [String],
            ["Alpha", "Beta"]
        )
        XCTAssertEqual(
            extractor.value(from: object, path: "$.list[?(@.type nin ['a'])].name") as? [String],
            ["Beta", "Gamma"]
        )
        XCTAssertEqual(
            extractor.value(from: object, path: "$.list[?(@.tags subsetof ['x','y'])].name") as? [String],
            ["Alpha", "Beta", "Gamma"]
        )
        XCTAssertEqual(
            extractor.value(from: object, path: "$.list[?(@.tags anyof ['x'])].name") as? [String],
            ["Alpha"]
        )
        XCTAssertEqual(
            extractor.value(from: object, path: "$.list[?(@.tags noneof ['x'])].name") as? [String],
            ["Beta", "Gamma"]
        )
        XCTAssertEqual(
            extractor.value(from: object, path: "$.list[?(@.name contains 'a')].name") as? [String],
            ["Alpha", "Beta", "Gamma"]
        )
        XCTAssertEqual(
            extractor.value(from: object, path: "$.list[?(@.tags size 2)].name") as? [String],
            ["Alpha"]
        )
        XCTAssertEqual(
            extractor.value(from: object, path: "$.list[?(@.tags empty true)].name") as? [String],
            ["Gamma"]
        )
        XCTAssertEqual(
            extractor.value(from: object, path: "$.list[?(@.type exists true)].name") as? [String],
            ["Alpha", "Beta", "Gamma"]
        )
    }

    func testUnknownDictionaryStringifiesAsCompactJSON() throws {
        let extractor = JSONRuleExtractor()
        let item: [String: Any] = [
            "meta": ["b": "x", "a": 1],
            "plain": "text"
        ]

        XCTAssertEqual(extractor.string(from: item, rule: "$.meta"), #"{"a":1,"b":"x"}"#)
        XCTAssertEqual(extractor.string(from: item, rule: "$.plain"), "text")
    }

    func testDoubleBraceTemplateEvaluatesJavaScriptExpression() throws {
        let extractor = JSONRuleExtractor()
        let item: [String: Any] = ["price": 10, "name": "A"]

        XCTAssertEqual(extractor.string(from: item, rule: "价格:{{result.price*2}}"), "价格:20")
        XCTAssertEqual(extractor.string(from: item, rule: "{{result.name}}"), "A")
    }
}
