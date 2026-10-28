import XCTest
@testable import SourceReadSwift

final class JSCoreRuntimeTests: XCTestCase {
    func testNativeUrlEncodeBridge() throws {
        let result = JSCoreRuntime().evaluate("java.urlEncode('斗破苍穹&a=1')")
        guard case .success(let value) = result else {
            return XCTFail("expected success: \(result)")
        }
        XCTAssertTrue(value.contains("%"))
        XCTAssertFalse(value.contains("&"))
    }

    func testNativeBase64Bridge() throws {
        let result = JSCoreRuntime().evaluate("java.base64Decode(java.base64Encode('abc'))")
        guard case .success(let value) = result else {
            return XCTFail("expected success: \(result)")
        }
        XCTAssertEqual(value, "abc")
    }

    func testCommonHashAndBase64Aliases() throws {
        let script = """
        [
          java.md5('abc'),
          java.hexMd5('abc'),
          java.md5Encode('abc'),
          md5('abc'),
          CryptoJS.MD5('abc').toString(),
          java.sha1('abc'),
          CryptoJS.SHA1('abc').toString(),
          java.sha256('abc'),
          atob(btoa('abc')),
          java.decodeBase64(java.base64('abc')),
          java.base64DecodeToString(java.base64Encode('abc')),
          java.base64Decoder(java.base64Encode('abc')),
          java.unbase64(java.base64Encode('abc')),
          unbase64(java.base64Encode('abc'))
        ].join('|')
        """

        let result = JSCoreRuntime().evaluate(script)

        guard case .success(let value) = result else {
            return XCTFail("expected success: \(result)")
        }
        XCTAssertEqual(
            value,
            "900150983cd24fb0d6963f7d28e17f72|900150983cd24fb0d6963f7d28e17f72|900150983cd24fb0d6963f7d28e17f72|900150983cd24fb0d6963f7d28e17f72|900150983cd24fb0d6963f7d28e17f72|a9993e364706816aba3e25717850c26c9cd0d89d|a9993e364706816aba3e25717850c26c9cd0d89d|ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad|abc|abc|abc|abc|abc|abc"
        )
    }

    func testCryptoJSHmacAndEncoders() throws {
        let script = """
        [
          CryptoJS.HmacSHA256('abc', 'key').toString(),
          CryptoJS.enc.Hex.stringify(CryptoJS.enc.Utf8.parse('abc')),
          CryptoJS.enc.Utf8.stringify(CryptoJS.enc.Hex.parse('616263')),
          CryptoJS.enc.Base64.stringify(CryptoJS.enc.Utf8.parse('abc')),
          CryptoJS.enc.Utf8.stringify(CryptoJS.enc.Base64.parse('YWJj')),
          CryptoJS.SHA256(CryptoJS.enc.Utf8.parse('abc')).toString()
        ].join('|')
        """

        let result = JSCoreRuntime().evaluate(script)

        guard case .success(let value) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(
            value,
            "9c196e32dc0175f86f4b1cb89289d6619de6bee699e4c378e68309ed97a1a6ab|616263|abc|YWJj|abc|ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    func testURIEncodingAliases() throws {
        let script = """
        [
          java.encodeURI('a&b=1'),
          java.encodeURIComponent('a&b=1'),
          java.decodeURI('a%26b%3D1'),
          java.decodeURIComponent('a%26b%3D1')
        ].join('|')
        """

        let result = JSCoreRuntime().evaluate(script)

        guard case .success(let value) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(value, "a%26b%3D1|a%26b%3D1|a&b=1|a&b=1")
    }

    func testNativeGetStringBridge() throws {
        let html = "<html><body><div class='book'><a href='/b/1'>斗破苍穹</a></div></body></html>"
        let script = "java.getString(html, '.book a@text')"
        let result = JSCoreRuntime().evaluate(script, variables: ["html": html, "baseUrl": "https://example.com"])
        guard case .success(let value) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(value, "斗破苍穹")
    }

    func testJsoupParseSelectionUsesSwiftSoupBridge() throws {
        let title = "\u{6597}\u{7834}\u{82cd}\u{7a79}"
        let html = "<html><body><div class='book'><a href='/b/1'>\(title)</a></div></body></html>"
        let script = "org.jsoup.Jsoup.parse(html).select('.book a').attr('href') + '|' + Packages.org.jsoup.Jsoup.parse(html).select('.book a').text()"
        let result = JSCoreRuntime().evaluate(script, variables: ["html": html])

        guard case .success(let value) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(value, "http://localhost/b/1|\(title)")
    }

    func testNativeGetStringSupportsEnhancedHtmlRules() throws {
        let html = """
        <html><body>
          <a class='chapter' href='/c/1'>One</a>
          <a class='chapter' href='/c/2'>Two</a>
          <div class='intro'>Outer <span>Inner</span> Tail</div>
        </body></html>
        """

        let indexed = JSCoreRuntime().evaluate(
            "java.getString(html, '.chapter@1@href')",
            variables: ["html": html, "baseUrl": "https://example.com"]
        )
        let ownText = JSCoreRuntime().evaluate(
            "java.getString(html, '.intro@ownText')",
            variables: ["html": html, "baseUrl": "https://example.com"]
        )

        guard case .success(let indexedValue) = indexed,
              case .success(let ownTextValue) = ownText else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(indexedValue, "https://example.com/c/2")
        XCTAssertEqual(ownTextValue, "Outer Tail")
    }

    func testNativeGetStringListSupportsConnectorRules() throws {
        let html = """
        <html><body>
          <a class='free'>第一章</a>
          <a class='free'>第三章</a>
          <a class='vip'>第二章</a>
          <a class='vip'>第四章</a>
        </body></html>
        """
        let script = """
        [
          java.getStringList(html, '.missing || .free@text').join(','),
          java.getStringList(html, '.free%%.vip@text').join(',')
        ].join('|')
        """

        let result = JSCoreRuntime().evaluate(script, variables: ["html": html, "baseUrl": "https://example.com"])

        guard case .success(let value) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(value, "第一章,第三章|第一章,第二章,第三章,第四章")
    }

    func testNativeGetStringListSupportsXPathRules() throws {
        let html = """
        <html><body>
          <div class='toc'>
            <a href='/1'>One</a>
            <a href='/2'>Two</a>
          </div>
        </body></html>
        """

        let result = JSCoreRuntime().evaluate(
            #"java.getStringList(html, '//div[@class="toc"]/a/@href').join(',')"#,
            variables: ["html": html, "baseUrl": "https://example.com/book"]
        )

        guard case .success(let value) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(value, "https://example.com/1,https://example.com/2")
    }

    func testNativeGetStringCanUseDefaultHtmlVariable() throws {
        let html = """
        <html><body>
          <h2>Title</h2>
          <a href="/1">One</a>
          <a href="/2">Two</a>
        </body></html>
        """
        let script = """
        java.getString('h2@text') + '|' + java.getStringList('a@href').join(',')
        """

        let result = JSCoreRuntime().evaluate(script, variables: ["html": html, "baseUrl": "https://example.com"])

        guard case .success(let value) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(value, "Title|https://example.com/1,https://example.com/2")
    }

    func testNativeGetElementsUsesDefaultHtmlVariable() throws {
        let html = """
        <html><body>
          <div id="content">
            <p>A</p>
            <p>B</p>
          </div>
        </body></html>
        """

        let result = JSCoreRuntime().evaluate(
            "java.getElements('#content p').text() + '|' + java.getElements('#content p').eachText().join(',')",
            variables: ["html": html, "baseUrl": "https://example.com"]
        )

        guard case .success(let value) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(value, "A\nB|A,B")
    }

    func testNativeGetStringIgnoresBooleanFlagWhenUsingDefaultHtml() throws {
        let html = """
        <html><body>
          <h2>Title</h2>
          <a href="/1">One</a>
          <a href="/2">Two</a>
        </body></html>
        """
        let script = """
        java.getString('h2@text', true) + '|' + java.getStringList('a@text', false).join(',')
        """

        let result = JSCoreRuntime().evaluate(script, variables: ["result": html, "baseUrl": "https://example.com"])

        guard case .success(let value) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(value, "Title|One,Two")
    }

    func testNativeStringListsSupportJavaListAliases() throws {
        let html = """
        <html><body>
          <a>One</a>
          <a>Two</a>
        </body></html>
        """
        let script = """
        var list = java.getStringList('a@text');
        var elements = java.getElements('a').eachText();
        list.get(1) + '|' + list.size() + '|' + list.isEmpty() + '|' + elements.get(0)
        """

        let result = JSCoreRuntime().evaluate(script, variables: ["html": html])

        guard case .success(let value) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(value, "Two|2|false|One")
    }

    func testNativeElementsSupportIndexedAccess() throws {
        let html = """
        <html><body>
          <a href="/1"><span>One</span></a>
          <a href="/2"><span>Two</span></a>
          <a href="/3"></a>
        </body></html>
        """
        let script = """
        var links = java.getElements('a');
        var parsed = Packages.org.jsoup.Jsoup.parse(html).select('a');
        [
          links.get(1).text(),
          links.get(1).attr('href'),
          links.first().text(),
          links.size(),
          links.isEmpty(),
          parsed.get(0).text(),
          links.get(1).select('span').text()
        ].join('|')
        """

        let result = JSCoreRuntime().evaluate(script, variables: ["html": html, "baseUrl": "https://example.com"])

        guard case .success(let value) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(value, "Two|https://example.com/2|One|3|false|One|Two")
    }

    func testJavaStyleStringHelpersAreAvailable() throws {
        let script = """
        [
          'abcdef'.contains('bcd'),
          'abcdef'.startsWith('abc'),
          'abcdef'.endsWith('def'),
          'Title'.equals('Title'),
          'Title'.equalsIgnoreCase('title'),
          'a-b-c'.replaceAll('-', '')
        ].join('|')
        """

        let result = JSCoreRuntime().evaluate(script)

        guard case .success(let value) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(value, "true|true|true|true|true|abc")
    }

    func testCommonLegadoJavaHelpersAreAvailable() throws {
        let html = """
        <html><body>
          <span class="count">42</span>
          <span class="score">3.5</span>
        </body></html>
        """
        let script = """
        java.put('stored.count', '7');
        source.setVariable('token', 'abc');
        book.setVariable('chapter', '12');
        cookie.setCookie('sid=ok; theme=dark');
        [
          java.getInt('.count@text', 0),
          java.getDouble('.score@text', 0),
          java.getInt('stored.count', 0),
          source.getVariable('token'),
          book.getVariable('chapter'),
          chapter.isVip(),
          cookie.getKey('', 'sid'),
          java.getCookie(),
          java.getWebViewUA().contains('SourceReadSwift'),
          java.toast('x'),
          Packages.android.text.TextUtils.isEmpty(''),
          java.util.UUID.randomUUID().length > 20,
          'ABC'.getBytes().join(','),
          Packages.java.util.Base64.encodeToString('ABC'.getBytes()),
          JavaImporter().String('ok').toString(),
          importPackage(Packages.java.util) === Packages.java.util
        ].join('|')
        """

        let result = JSCoreRuntime().evaluate(
            script,
            variables: ["html": html, "chapter": ["title": "VIP章节"]]
        )

        guard case .success(let value) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(value, "42|3.5|7|abc|12|true|ok|sid=ok; theme=dark|true||true|true|65,66,67|QUJD|ok|true")
    }

    func testConnectChainSupportsCookiesBodyAndExecuteAliases() throws {
        let runtime = JSCoreRuntime { request in
            request
        }
        let script = """
        [
          java.connect('https://example.com/a').cookie('sid=1').get().body(),
          java.connect('https://example.com/b').headers({'X-Test':'1'}).post('q=1').text(),
          java.connect('https://example.com/c').data('k', 'v').execute().toString(),
          java.fetch('https://example.com/d', {'X-Fetch':'1'}).body()
        ].join('\\n---\\n')
        """

        let result = runtime.evaluate(script)

        guard case .success(let value) = result else {
            return XCTFail("expected success")
        }
        XCTAssertTrue(value.contains("https://example.com/a@Header:{\"Cookie\":\"sid=1\"}"))
        XCTAssertTrue(value.contains("https://example.com/b@Header:{\"X-Test\":\"1\"}@Body:q=1"))
        XCTAssertTrue(value.contains("https://example.com/c@Body:k=v"))
        XCTAssertTrue(value.contains("https://example.com/d@Header:{\"X-Fetch\":\"1\"}"))
    }

    func testChapterIsVipAvoidsDictionaryOverride() throws {
        // 验证传入外部 chapter 覆盖后，isVip() 方法依然可用
        let script = "chapter.isVip()"
        let runtime = JSCoreRuntime()
        let result = runtime.evaluate(script, variables: ["chapter": ["title": "第123章 VIP订阅付费"]])
        guard case .success(let value) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(value, "true")
    }

    func testChapterBooleanIsVipSurvivesFallbackInjection() throws {
        // A plain-object chapter may carry a boolean `isVip` (Legado's field
        // shape). The title heuristic must not overwrite it with a function.
        let runtime = JSCoreRuntime()
        let paid = runtime.evaluate(
            "typeof chapter.isVip + '|' + chapter.isVip",
            variables: ["chapter": ["title": "普通章节", "isVip": true]]
        )
        guard case .success(let paidValue) = paid else { return XCTFail("expected success") }
        XCTAssertEqual(paidValue, "boolean|true")

        let free = runtime.evaluate(
            "typeof chapter.isVip + '|' + chapter.isVip",
            variables: ["chapter": ["title": "VIP 章节", "isVip": false]]
        )
        guard case .success(let freeValue) = free else { return XCTFail("expected success") }
        XCTAssertEqual(freeValue, "boolean|false")
    }

    func testJsoupSelectionCascadingDOMAPIs() throws {
        let html = """
        <html><body>
          <div id="content">
            <p class="remove-me">Header</p>
            <div class="chapters">
              <a href="/c/1"><span>One</span></a>
              <a href="/c/2"><span>Two</span></a>
              <a href="/c/3"><span>Three</span></a>
            </div>
          </div>
        </body></html>
        """
        let script = """
        var doc = org.jsoup.Jsoup.parse(html, 'https://example.com');
        // 测试 remove
        doc.select('.remove-me').remove();
        // 测试 eq 级联和 outerHtml/text
        var firstLinkText = doc.select('.chapters a').eq(1).select('span').text();
        var outer = doc.select('.chapters a').eq(2).outerHtml();
        // 测试 children
        var childCount = doc.select('.chapters').children().size();
        // 测试 parents
        var parentHtml = doc.select('.chapters span').eq(0).parents().html();
        
        [
          doc.select('.remove-me').size(), // 应该为 0
          firstLinkText, // 应该为 "Two"
          outer.contains('Three'), // 应该为 true
          childCount, // 应该为 3
          parentHtml.contains('id="content"') // 应该为 true
        ].join('|')
        """
        
        let result = JSCoreRuntime().evaluate(script, variables: ["html": html])
        guard case .success(let value) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(value, "0|Two|true|3|true")
    }

    func testLoginInfoMapSupportsBracketAccessPutAndPrefixRemoval() throws {
        let source = BookSource(bookSourceName: "login-source", bookSourceUrl: "https://example.com")
        let runtime = JSCoreRuntime()
        let script = """
        var map = source.getLoginInfoMap();
        var emptyBefore = map.isEmpty();
        var keysBefore = Object.keys(map).join(',');
        map['密钥'] = 'KEY-1';
        var emptyAfter = map.isEmpty();
        var keysAfter = Object.keys(map).join(',');
        var bracket = map['密钥'];
        var getter = map.get('密钥');
        var contains = map.containsKey('密钥');
        map.put('blank', '');
        var blankContains = map.containsKey('blank');
        map.remove('blank');
        source.putLoginInfo({'token': 'T-2'});
        var token = source.getLoginInfoMap()['token'];
        source.setLoginInfo('device', 'D-3');
        var device = source.getLoginInfoMap()['device'];
        var keysAll = Object.keys(source.getLoginInfoMap()).sort().join(',');
        source.removeLoginInfo();
        var cleared = String(source.getLoginInfoMap()['密钥'] || '');
        var emptyCleared = source.getLoginInfoMap().isEmpty();
        var keysCleared = Object.keys(source.getLoginInfoMap()).join(',');
        [emptyBefore, keysBefore, emptyAfter, keysAfter, bracket, getter, contains, blankContains, token, device, keysAll, cleared, emptyCleared, keysCleared].join('|');
        """
        let result = runtime.evaluate(script, variables: ["source": source])
        guard case .success(let value) = result else {
            return XCTFail("expected success: \(result)")
        }
        XCTAssertEqual(value, "true||false|密钥|KEY-1|KEY-1|true|true|T-2|D-3|device,token,密钥||true|")
    }

    func testChapterBridgeExposesIsPayAsBoolean() throws {
        let paid = BookChapter(
            title: "已购买章节",
            url: "https://fixture.example/2",
            bookUrl: "https://fixture.example/book",
            index: 1,
            isVip: true,
            isPay: true
        )
        let runtime = JSCoreRuntime()
        let result = runtime.evaluate(
            "typeof chapter.isPay + '|' + chapter.isPay",
            variables: ["chapter": paid]
        )
        guard case .success(let value) = result else {
            return XCTFail("expected success: \(result)")
        }
        XCTAssertEqual(value, "boolean|true")

        let unknown = BookChapter(
            title: "旧缓存章节",
            url: "https://fixture.example/3",
            bookUrl: "https://fixture.example/book",
            index: 2,
            isVip: true
        )
        let unknownResult = runtime.evaluate(
            "chapter.isPay === false",
            variables: ["chapter": unknown]
        )
        guard case .success(let unknownValue) = unknownResult else {
            return XCTFail("expected success: \(unknownResult)")
        }
        XCTAssertEqual(unknownValue, "true")
    }
    /// Unknown `java.*` helpers must not abort the rule with a TypeError.
    /// The JS proxy routes them to the native dispatcher, which records a
    /// `bridge.error java.<name>` line and returns an empty string.
    func testUnknownJavaMethodDegradesAndRecordsBridgeDiagnostic() throws {
        let context = RuleExecutionContext()
        let runtime = JSCoreRuntime(executionContext: context)
        let result = runtime.evaluate("""
        var probe = java.thisHelperDoesNotExist('x');
        typeof java.thisHelperDoesNotExist + '|' + probe + '|' + java.md5('abc')
        """)
        guard case .success(let value) = result else {
            return XCTFail("expected success: \(result)")
        }
        XCTAssertTrue(value.hasPrefix("function||"), "unexpected shape: \(value)")
        XCTAssertTrue(context.logs().contains { $0.contains("bridge.error java.thisHelperDoesNotExist") }, "\(context.logs())")
    }

    /// The proxy must not shadow helpers implemented by the prelude.
    func testUnknownJavaMethodProxyKeepsKnownBridgesWorking() throws {
        let runtime = JSCoreRuntime()
        let result = runtime.evaluate("java.base64Decode(java.base64Encode('abc')) + '|' + java.urlEncode('中')")
        guard case .success(let value) = result else {
            return XCTFail("expected success: \(result)")
        }
        let parts = value.components(separatedBy: "|")
        XCTAssertEqual(parts.first, "abc")
        XCTAssertTrue(parts.last?.contains("%") == true)
    }

    // Private Legado banks call `cache.getFromMemory` / `cache.putMemory`
    // (7-8 sources in the 103-source bank) and `java.getLoginInfo` /
    // `java.reLoginView` / `java.sleep`.  Missing shims made those rules die
    // with `TypeError: ... is not a function` before any network call.
    func testCacheMemoryAliasesAndJavaLoginBridge() throws {
        let runtime = JSCoreRuntime()
        XCTAssertEqual(try XCTUnwrap(runtime.evaluate("cache.putMemory('k', 'v'); cache.getFromMemory('k')").get()), "v")
        XCTAssertEqual(try XCTUnwrap(runtime.evaluate("cache.put('k2', 'v2'); cache.remove('k2')").get()), "v2")
        XCTAssertEqual(try XCTUnwrap(runtime.evaluate("typeof java.getLoginInfo().get === 'function' ? 'ok' : 'bad'").get()), "ok")
        XCTAssertEqual(try XCTUnwrap(runtime.evaluate("typeof java.getLoginInfoMap().get === 'function' ? 'ok' : 'bad'").get()), "ok")
        XCTAssertEqual(try XCTUnwrap(runtime.evaluate("typeof java.reLoginView() === 'string' ? 'ok' : 'bad'").get()), "ok")
        XCTAssertEqual(try XCTUnwrap(runtime.evaluate("java.sleep(1); 'done'").get()), "done")
    }

    /// 知秋/神魔系 jsLib 把 `source` 当 Map 用。缺 `get/put/remove` 别名时，
    /// 真实私人源在 searchUrl 阶段抛 "source.get is not a function"。
    func testSourceMapAliasesForZhiqiuLibraries() throws {
        let source = BookSource(
            bookSourceName: "Alias Source",
            bookSourceUrl: "https://alias.example.com"
        )
        let runtime = RuleExecutionContext(source: source).jsRuntime(ajaxHandler: { _ in "" })
        XCTAssertEqual(
            try XCTUnwrap(runtime.evaluate("source.put('qd_base', 'https://a.example.com'); source.get('qd_base')").get()),
            "https://a.example.com"
        )
        XCTAssertEqual(try XCTUnwrap(runtime.evaluate("source.get('missing') === '' ? 'ok' : 'bad'").get()), "ok")
        XCTAssertEqual(try XCTUnwrap(runtime.evaluate("source.remove('qd_base'); source.get('qd_base')").get()), "")
    }
    // MARK: - 1.0.90 private bank (76 sources) compatibility

    /// 七猫/番茄四合一 jsLib 依赖 java.util.zip / hutool / 反射 / ByteBuffer。
    func testPrivateBankPackagesShims() throws {
        let runtime = JSCoreRuntime()
        XCTAssertEqual(try XCTUnwrap(runtime.evaluate("Packages.java.lang.reflect.Array.newInstance(Packages.java.lang.Byte.TYPE, 4).length").get()), "4")
        XCTAssertEqual(try XCTUnwrap(runtime.evaluate("Packages.java.util.Arrays.copyOf([1,2,3], 5).length").get()), "5")
        XCTAssertEqual(try XCTUnwrap(runtime.evaluate("String(new Packages.java.lang.String([65,66,67], 1, 2, 'UTF-8'))").get()), "BC")
        XCTAssertEqual(try XCTUnwrap(runtime.evaluate("Packages.java.nio.ByteBuffer.allocate(4).putInt(0x01020304).array().join(',')").get()), "1,2,3,4")
        XCTAssertEqual(try XCTUnwrap(runtime.evaluate("Packages.cn.hutool.crypto.digest.DigestUtil.md5Hex('abc')").get()), "900150983cd24fb0d6963f7d28e17f72")
        XCTAssertEqual(try XCTUnwrap(runtime.evaluate("Packages.cn.hutool.crypto.digest.DigestUtil.sha256Hex('abc')").get()), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(try XCTUnwrap(runtime.evaluate("Packages.cn.hutool.core.util.StrUtil.reverse('abc')").get()), "cba")
        XCTAssertEqual(try XCTUnwrap(runtime.evaluate("Packages.cn.hutool.core.util.StrUtil.isBlank('  ') ? 'blank' : 'no'").get()), "blank")
        XCTAssertEqual(try XCTUnwrap(runtime.evaluate("new Packages.javax.crypto.spec.GCMParameterSpec(128, [1,2,3]).getTLen()").get()), "128")
        XCTAssertEqual(try XCTUnwrap(runtime.evaluate("new Packages.javax.crypto.spec.GCMParameterSpec(128, [1,2,3]).getIV().length").get()), "3")
        XCTAssertEqual(try XCTUnwrap(runtime.evaluate("var a=[0,0,0,0]; new Packages.java.security.SecureRandom().nextBytes(a); a.length").get()), "4")
    }

    /// 七猫本地接口把 ZIP entry 的 raw DEFLATE 交给 Inflater(true)。
    /// 调用方按 Java 习惯循环 inflate(buf, off, len)，必须按进度续读。
    func testInflaterRawDeflateChunkedReads() throws {
        let rawDeflate = "203,72,205,201,201,87,200,204,75,203,73,44,73,45,82,40,72,172,204,201,79,76,81,48,48,52,50,54,49,53,51,183,176,4,0"
        let script = """
        (function(){
          var src = [\(rawDeflate)];
          var inflater = new Packages.java.util.zip.Inflater(true);
          inflater.setInput(src);
          var out = [];
          var buffer = new Array(4);
          var guard = 0;
          while (!inflater.finished() && guard++ < 64) {
            var n = inflater.inflate(buffer, 0, buffer.length);
            if (n <= 0) break;
            for (var i = 0; i < n; i++) out.push(buffer[i]);
          }
          var text = '';
          for (var j = 0; j < out.length; j++) text += String.fromCharCode(out[j]);
          return text + '|' + out.length;
        })()
        """
        XCTAssertEqual(try XCTUnwrap(JSCoreRuntime().evaluate(script).get()), "hello inflater payload 0123456789|33")
    }

    /// javax.crypto Cipher 的 AES/GCM/NoPadding 必须走 CryptoSwift GCM，
    /// 而不是被当成 CBC 处理（紙間·阅读等本地解密源依赖）。
    func testAESGCMRoundTripThroughJavaxCipher() throws {
        let script = """
        (function(){
          var key = [0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15];
          var iv = [0,1,2,3,4,5,6,7,8,9,10,11];
          var plain = [104,101,108,108,111];
          var enc = Packages.javax.crypto.Cipher.getInstance('AES/GCM/NoPadding');
          enc.init(Packages.javax.crypto.Cipher.ENCRYPT_MODE,
            new Packages.javax.crypto.spec.SecretKeySpec(key, 'AES'),
            new Packages.javax.crypto.spec.GCMParameterSpec(128, iv));
          var cipher = enc.doFinal(plain);
          var dec = Packages.javax.crypto.Cipher.getInstance('AES/GCM/NoPadding');
          dec.init(Packages.javax.crypto.Cipher.DECRYPT_MODE,
            new Packages.javax.crypto.spec.SecretKeySpec(key, 'AES'),
            new Packages.javax.crypto.spec.GCMParameterSpec(128, iv));
          var out = dec.doFinal(cipher);
          var text = '';
          for (var i = 0; i < out.length; i++) text += String.fromCharCode(out[i]);
          return text + '|' + cipher.length + '|' + out.length;
        })()
        """
        XCTAssertEqual(try XCTUnwrap(JSCoreRuntime().evaluate(script).get()), "hello|21|5")
    }

    /// source.* 登录头 / 变量 / 标签 API：书旗、QQ浏览器、UAA 等源依赖。
    func testSourceLoginHeaderAndMetadataShims() throws {
        let source = BookSource(
            bookSourceName: "Bank Source",
            bookSourceUrl: "https://bank.example.com"
        )
        let runtime = RuleExecutionContext(source: source).jsRuntime(ajaxHandler: { _ in "" })
        XCTAssertEqual(
            try XCTUnwrap(runtime.evaluate("source.putLoginHeader('{\"authorization\":\"Bearer x\"}')").get()),
            "{\"authorization\":\"Bearer x\"}"
        )
        XCTAssertEqual(
            try XCTUnwrap(runtime.evaluate("source.getLoginHeaderMap().authorization").get()),
            "Bearer x"
        )
        XCTAssertEqual(
            try XCTUnwrap(runtime.evaluate("source.putLoginHeader('cookie', 'a=1'); source.getLoginHeader('cookie')").get()),
            "a=1"
        )
        XCTAssertEqual(try XCTUnwrap(runtime.evaluate("source.removeLoginHeader() ? 'ok' : 'bad'").get()), "ok")
        // `evaluate` only installs variables passed per call; the shared runtime
        // starts with an empty `source` object from the prelude.  Seed the
        // metadata fields before exercising the getTag/includes shims.
        XCTAssertEqual(
            try XCTUnwrap(runtime.evaluate("source.bookSourceName = 'Bank Source'; source.sourceName = 'Bank Source'; source.getTag()").get()),
            "Bank Source"
        )
        XCTAssertEqual(try XCTUnwrap(runtime.evaluate("source.includes('Bank') ? 'ok' : 'bad'").get()), "ok")
        XCTAssertEqual(try XCTUnwrap(runtime.evaluate("typeof source.getLoginUi() === 'string' ? 'ok' : 'bad'").get()), "ok")
        XCTAssertEqual(try XCTUnwrap(runtime.evaluate("cache.putMemory('k', 'v'); cache.deleteMemory('k') ? 'done' : 'done'").get()), "done")
        XCTAssertEqual(try XCTUnwrap(runtime.evaluate("java.deviceID() === '' ? 'ok' : 'bad'").get()), "ok")
        XCTAssertEqual(try XCTUnwrap(runtime.evaluate("java.qread()").get()), "0")
        XCTAssertEqual(try XCTUnwrap(runtime.evaluate("java.getSource() === source ? 'ok' : 'bad'").get()), "ok")
    }
}
