import XCTest
@testable import SourceReadSwift

final class Stage33ReaderExperienceTests: XCTestCase {

    // MARK: - 1. SourceRead Txt TOC Regular Expression Rules (txtTocRule.json)

    func testTxtChapterHeadingMatchingLegadoPatterns() {
        // Standard Chinese numerals
        XCTAssertTrue(LocalTextBookParser.matchesChapterHeading("第1章 降临"))
        XCTAssertTrue(LocalTextBookParser.matchesChapterHeading("第一章 初出茅庐"))
        XCTAssertTrue(LocalTextBookParser.matchesChapterHeading("第一千零二十四章 终极之战"))
        XCTAssertTrue(LocalTextBookParser.matchesChapterHeading("第十二卷 风起云涌"))
        XCTAssertTrue(LocalTextBookParser.matchesChapterHeading("第一百二十八回 封神之役"))
        XCTAssertTrue(LocalTextBookParser.matchesChapterHeading("第3节 突破"))
        XCTAssertTrue(LocalTextBookParser.matchesChapterHeading("第5篇 觉醒"))

        // English Chapter / Section / Episode
        XCTAssertTrue(LocalTextBookParser.matchesChapterHeading("Chapter 1 The Journey Begins"))
        XCTAssertTrue(LocalTextBookParser.matchesChapterHeading("chapter 42"))
        XCTAssertTrue(LocalTextBookParser.matchesChapterHeading("Chapter XIV The Gathering"))
        XCTAssertTrue(LocalTextBookParser.matchesChapterHeading("Section 2 The Protocol"))

        // Pure numbers or Number + separator + title
        XCTAssertTrue(LocalTextBookParser.matchesChapterHeading("1. 引子"))
        XCTAssertTrue(LocalTextBookParser.matchesChapterHeading("12、 新的征程"))
        XCTAssertTrue(LocalTextBookParser.matchesChapterHeading("105 - 决战时刻"))
        XCTAssertTrue(LocalTextBookParser.matchesChapterHeading("一 、 宿命之战"))
        XCTAssertTrue(LocalTextBookParser.matchesChapterHeading("四十二、 天道酬勤"))

        // Special brackets and symbols
        XCTAssertTrue(LocalTextBookParser.matchesChapterHeading("【第一章】 归来"))
        XCTAssertTrue(LocalTextBookParser.matchesChapterHeading("〔第2卷〕 潜龙在渊"))
        XCTAssertTrue(LocalTextBookParser.matchesChapterHeading("〖Chapter 10〗 破局"))
        XCTAssertTrue(LocalTextBookParser.matchesChapterHeading("「第一章」 起始之风"))
        XCTAssertTrue(LocalTextBookParser.matchesChapterHeading("『第3章』 破晓"))
        XCTAssertTrue(LocalTextBookParser.matchesChapterHeading("☆第一卷 苍穹变☆"))

        // Prefaces, Prologues, Epilogues
        XCTAssertTrue(LocalTextBookParser.matchesChapterHeading("序章"))
        XCTAssertTrue(LocalTextBookParser.matchesChapterHeading("楔子"))
        XCTAssertTrue(LocalTextBookParser.matchesChapterHeading("正文 第一章 开始"))
        XCTAssertTrue(LocalTextBookParser.matchesChapterHeading("终章 黎明的曙光"))
        XCTAssertTrue(LocalTextBookParser.matchesChapterHeading("后记"))
        XCTAssertTrue(LocalTextBookParser.matchesChapterHeading("尾声"))
        XCTAssertTrue(LocalTextBookParser.matchesChapterHeading("番外 往事如烟"))
        XCTAssertTrue(LocalTextBookParser.matchesChapterHeading("大结局(一)"))
        XCTAssertTrue(LocalTextBookParser.matchesChapterHeading("大结局（二）"))

        // Negative assertions: ordinary body text MUST NOT be recognized as chapters
        XCTAssertFalse(LocalTextBookParser.matchesChapterHeading("第1次来到这个地方，心中感慨万千。"))
        XCTAssertFalse(LocalTextBookParser.matchesChapterHeading("今天阳光明媚，微风吹拂着面颊。"))
        XCTAssertFalse(LocalTextBookParser.matchesChapterHeading("这是一段非常长的小说正文内容，超过了四十八个字符的限制，绝对不能被判定为章节标题，因为读者在看书时不能随便被截断。"))
    }

    func testLocalTextBookParserSplitsChaptersCorrectly() {
        let rawContent = """
        序章 命运的起点
        很久很久以前，大陆上发生了一场风暴。
        第一章 少年出山
        阳光穿过森林，照在一座茅草屋上。
        第二章 试炼之路
        前方是崇山峻岭，险象环生。
        尾声
        故事暂告一个段落。
        """
        let parser = LocalTextBookParser()
        let book = parser.parse(data: Data(rawContent.utf8), fileName: "test_novel.txt")

        XCTAssertEqual(book.title, "test_novel")
        XCTAssertEqual(book.chapters.count, 4)
        XCTAssertEqual(book.chapters[0].title, "序章 命运的起点")
        XCTAssertEqual(book.chapters[1].title, "第一章 少年出山")
        XCTAssertEqual(book.chapters[2].title, "第二章 试炼之路")
        XCTAssertEqual(book.chapters[3].title, "尾声")
    }

    // MARK: - 2. SourceRead Native Palettes (readConfig.json)

    func testSourceReadNativePalettesConfiguration() {
        // Verify all 8 background palettes exist
        let allCases = ReaderBackground.allCases
        XCTAssertEqual(allCases.count, 8)

        // 1. 羊皮纸
        let paper = ReaderBackground.paper
        XCTAssertEqual(paper.dayBackgroundHex, 0xEBD9BB)
        XCTAssertEqual(paper.dayTextHex, 0x63543C)
        XCTAssertEqual(paper.nightBackgroundHex, 0x1E2021)
        XCTAssertEqual(paper.nightTextHex, 0xDCDFE1)
        XCTAssertTrue(paper.darkStatusIcon(isNight: false))
        XCTAssertFalse(paper.darkStatusIcon(isNight: true))

        // 2. 复古牛皮
        let kraft = ReaderBackground.kraft
        XCTAssertEqual(kraft.dayBackgroundHex, 0xDDC090)
        XCTAssertEqual(kraft.dayTextHex, 0x3E3422)
        XCTAssertEqual(kraft.nightBackgroundHex, 0x3C3F43)

        // 3. 豆沙青绿
        let green = ReaderBackground.green
        XCTAssertEqual(green.dayBackgroundHex, 0xC2D8AA)
        XCTAssertEqual(green.dayTextHex, 0x596C44)
        XCTAssertEqual(green.nightTextHex, 0x88C16F)

        // 4. 淡雅黛紫
        let lavender = ReaderBackground.lavender
        XCTAssertEqual(lavender.dayBackgroundHex, 0xDBB8E2)
        XCTAssertEqual(lavender.dayTextHex, 0x68516C)
        XCTAssertEqual(lavender.nightTextHex, 0xF6AEAE)

        // 5. 晴空天蓝
        let azure = ReaderBackground.azure
        XCTAssertEqual(azure.dayBackgroundHex, 0xABCEE0)
        XCTAssertEqual(azure.dayTextHex, 0x3D4C54)
        XCTAssertEqual(azure.nightTextHex, 0x90BFF5)

        // 6. 极夜纯黑
        let dark = ReaderBackground.dark
        XCTAssertEqual(dark.dayBackgroundHex, 0x000000)
        XCTAssertEqual(dark.dayTextHex, 0xFFFFFF)
        XCTAssertEqual(dark.nightBackgroundHex, 0x000000)
        XCTAssertEqual(dark.nightTextHex, 0xFFFFFF)
        XCTAssertFalse(dark.darkStatusIcon(isNight: false))
    }

    // MARK: - 3. SourceRead Online HTTP TTS Voice Engine (httpTTS.json)

    func testHttpTTSVoiceTemplateEvaluationWithJSCoreRuntime() {
        guard let voice = HttpTTSVoice.defaultVoices.first(where: { $0.id == -1 }) else {
            return XCTFail("Default voice not found")
        }
        XCTAssertTrue(voice.isPost)

        let runtime = JSCoreRuntime()
        let request = voice.resolveRequest(speakText: "天道酬勤", speakSpeed: 5, runtime: runtime)
        XCTAssertNotNil(request)
        guard let request else { return }

        XCTAssertEqual(request.url.absoluteString, "http://tts.baidu.com/text2audio")
        XCTAssertEqual(request.headers["Content-Type"], "application/x-www-form-urlencoded")

        guard let body = request.body else {
            return XCTFail("POST body was nil")
        }
        // Double URI encoding should produce %25...
        XCTAssertTrue(body.contains("tex="), "body: (body)")
        XCTAssertTrue(body.contains("&spd=5"), "body: (body)")
        XCTAssertTrue(body.contains("&per=4"), "body: (body)")
        XCTAssertTrue(body.contains("&cuid=baidu_speech_demo"), "body: (body)")
    }

    // MARK: - 4. 120Hz ProMotion Frame Rate & Performance Policies

    func testProMotionFrameRatePlan() {
        // ProMotion 120Hz displays
        let plan120 = ReaderPerformancePolicy.frameRatePlan(maximumFramesPerSecond: 120)
        XCTAssertEqual(plan120.maximum, 120)
        XCTAssertEqual(plan120.preferred, 120)

        // Standard 60Hz displays
        let plan60 = ReaderPerformancePolicy.frameRatePlan(maximumFramesPerSecond: 60)
        XCTAssertEqual(plan60.maximum, 60)
        XCTAssertEqual(plan60.preferred, 60)

        // Capped ceiling
        XCTAssertEqual(ReaderPerformancePolicy.preferredRefreshRate(maximumFramesPerSecond: 144), 120)
    }

    // MARK: - 5. Reader Automation & Chapter Advance Decision

    func testReaderAdvanceDecisionStateMachine() {
        // Mid-chapter step: advance to next target
        let step = ReaderAutomationPolicy.decision(currentTarget: 2, maximumTarget: 10, canAdvanceChapter: true)
        XCTAssertEqual(step, .advance(to: 3))

        // Chapter end with next chapter available
        let nextChapter = ReaderAutomationPolicy.decision(currentTarget: 10, maximumTarget: 10, canAdvanceChapter: true)
        XCTAssertEqual(nextChapter, .nextChapter)

        // Book end: stop
        let stop = ReaderAutomationPolicy.decision(currentTarget: 10, maximumTarget: 10, canAdvanceChapter: false)
        XCTAssertEqual(stop, .stop)
    }

    func testReaderSpeechQueueSequence() {
        var queue = ReaderSpeechQueue()
        queue.reset(title: "第一章", paragraphs: ["段落一", "段落二", "段落三"], startParagraphIndex: 0, includeTitle: true)

        XCTAssertFalse(queue.isFinished)
        let first = queue.dequeue()
        XCTAssertEqual(first?.index, -1)
        XCTAssertEqual(first?.text, "第一章")

        let second = queue.dequeue()
        XCTAssertEqual(second?.index, 0)
        XCTAssertEqual(second?.text, "段落一")

        let third = queue.dequeue()
        XCTAssertEqual(third?.index, 1)
        XCTAssertEqual(third?.text, "段落二")

        let fourth = queue.dequeue()
        XCTAssertEqual(fourth?.index, 2)
        XCTAssertEqual(fourth?.text, "段落三")

        XCTAssertTrue(queue.isFinished)
        XCTAssertNil(queue.dequeue())
    }
}
