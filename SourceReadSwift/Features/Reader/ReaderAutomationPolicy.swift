import Combine
import Foundation
import CoreGraphics

/// Deterministic chrome state for the reader.  The previous implementation
/// kept `showOverlay` and `showSettings` as two independent booleans; a
/// delayed SwiftUI update could therefore leave the settings sheet visible
/// after the menu had been dismissed (or vice versa).  A single state makes
/// every exit path converge on one transition and is straightforward to test
/// without rendering UIKit.
enum ReaderChromeMode: Equatable {
    case hidden
    case overlay
    case settings
}

struct ReaderChromeStateMachine: Equatable {
    private(set) var mode: ReaderChromeMode = .hidden

    var isOverlayVisible: Bool { mode != .hidden }
    var isSettingsVisible: Bool { mode == .settings }

    mutating func setInitialOverlayVisible(_ visible: Bool) {
        mode = visible ? .overlay : .hidden
    }

    mutating func toggleOverlay() {
        mode = mode == .hidden ? .overlay : .hidden
    }

    mutating func openSettings() {
        mode = .settings
    }

    /// Closing settings intentionally returns to the reader menu.  This keeps
    /// the reader action bar available while ensuring the settings surface is
    /// never stranded above a hidden overlay.
    mutating func closeSettings() {
        if mode == .settings { mode = .overlay }
    }

    mutating func closeAll() {
        mode = .hidden
    }
}

/// Deterministic decisions for automatic reader advancement.
/// Kept independent from SwiftUI so chapter-boundary behavior is testable on CI.
enum ReaderAdvanceDecision: Equatable {
    case advance(to: Int)
    case nextChapter
    case stop
}

/// Keeps the reader settings sheet inside the visible viewport. The old
/// `max(height * 0.84, 560)` clause exceeded a landscape iPhone (about 390pt
/// tall) and clipped the tabs and the close button off-screen.
enum ReaderSettingsLayoutPolicy {
    static func maxPanelHeight(viewportHeight: CGFloat, bottomInset: CGFloat) -> CGFloat {
        let available = max(viewportHeight - max(bottomInset, 14) - 24, 320)
        return min(max(viewportHeight * 0.84, 420), min(760, available))
    }

    /// Menu panels share one gutter with the top/bottom bars: 16pt per side on
    /// phones, capped at a 560pt reading width on tablets and landscape.
    static func maxPanelWidth(viewportWidth: CGFloat) -> CGFloat {
        min(560, max(viewportWidth - 32, 0))
    }
}

/// The chapter label is independent from the user's clock/battery placement.
/// One geometry controls both the opaque top band and the initial body inset.
enum ReaderScrollChromePolicy {
    static func headerVisible(chapterStyle: ReaderPageChromeLayout, statusPosition: String) -> Bool {
        chapterStyle != .hidden || statusPosition == "top" || statusPosition == "both"
    }
}

struct ReaderScrollChromeGeometry: Equatable {
    static let bodyGap: CGFloat = 6
    let safeTop: CGFloat
    let headerVisible: Bool
    let fontSize: CGFloat
    let topGap: CGFloat

    init(safeTop: CGFloat, headerVisible: Bool, showSystemStatusBar: Bool,
         fontSize: CGFloat = 12, topGap: CGFloat = ReaderPageChrome.headerTopGap) {
        let finiteTop = safeTop.isFinite ? max(safeTop, 0) : 0
        self.safeTop = max(finiteTop, showSystemStatusBar ? 20 : 0)
        self.headerVisible = headerVisible
        self.fontSize = CGFloat(ReaderHeadingPreferences.headerSize(Double(fontSize)))
        self.topGap = CGFloat(ReaderHeadingPreferences.headerGap(Double(topGap)))
    }

    var headerTop: CGFloat { safeTop + topGap }
    var bandHeight: CGFloat { max(ReaderPageChrome.scrollHeaderBandHeight, fontSize + 6) }
    var protectedHeight: CGFloat {
        headerVisible
            ? headerTop + bandHeight + Self.bodyGap
            : safeTop
    }
}

struct ReaderAutomationPolicy {
    public static let minDelay: Double = 0.25
    public static let maxDelay: Double = 60.0

    /// Keep automation responsive without allowing a malformed persisted value
    /// to create a busy loop (or an animation that effectively never moves).
    static func clampedDelay(_ rawValue: Double) -> Double {
        guard rawValue.isFinite else { return 2.0 }
        return min(max(rawValue, minDelay), maxDelay)
    }

    static func decision(
        currentTarget: Int,
        maximumTarget: Int,
        canAdvanceChapter: Bool
    ) -> ReaderAdvanceDecision {
        guard maximumTarget >= 0 else {
            return canAdvanceChapter ? .nextChapter : .stop
        }
        guard currentTarget < maximumTarget else {
            return canAdvanceChapter ? .nextChapter : .stop
        }
        return .advance(to: currentTarget + 1)
    }

    /// Snapshot the reader cursor before automation starts.
    /// The first auto-scroll tick should begin from what the user can see now,
    /// not from a stale automation target left behind by a prior session.
    static func startingAutoScrollTarget(
        mode: ReaderMode,
        visibleParagraphIndex: Int,
        pagedPageIndex: Int,
        maximumTarget: Int
    ) -> Int {
        let rawTarget: Int
        switch mode {
        case .scroll:
            rawTarget = visibleParagraphIndex
        case .pageTurn, .cover, .pageCurl:
            rawTarget = pagedPageIndex
        }
        return min(max(rawTarget, 0), maximumTarget)
    }
}

enum ReaderPagedSwipeDecision: Equatable {
    case previous
    case next
}

enum ReaderPagedSwipePolicy {
    static func decision(
        horizontal: CGFloat,
        vertical: CGFloat,
        minimumDistance: CGFloat = 40,
        axisBias: CGFloat = 1.15
    ) -> ReaderPagedSwipeDecision? {
        guard abs(horizontal) >= minimumDistance else { return nil }
        guard abs(horizontal) > abs(vertical) * axisBias else { return nil }
        return horizontal < 0 ? .next : .previous
    }
}

struct ReaderCoverSwipeState: Equatable {
    var translation: CGFloat = 0
    var isHorizontal: Bool = false
}

/// The small, deterministic state machine shared by the reader's automation
/// controls.  Keeping the transitions outside SwiftUI prevents an old timer,
/// speech callback, or scene lifecycle event from reviving a newer session.
enum ReaderPlaybackMode: Equatable {
    case idle
    case autoScroll(generation: Int)
    case speech(generation: Int)
    case pausedSpeech(generation: Int)
}

struct ReaderPlaybackStateMachine: Equatable {
    private(set) var mode: ReaderPlaybackMode = .idle
    private(set) var generation: Int = 0

    mutating func beginAutoScroll() -> Int {
        generation &+= 1
        mode = .autoScroll(generation: generation)
        return generation
    }

    mutating func beginSpeech() -> Int {
        generation &+= 1
        mode = .speech(generation: generation)
        return generation
    }

    mutating func pauseSpeech() {
        if case .speech(let token) = mode {
            mode = .pausedSpeech(generation: token)
        }
    }

    mutating func resumeSpeech() {
        if case .pausedSpeech(let token) = mode {
            mode = .speech(generation: token)
        }
    }

    mutating func stop() {
        generation &+= 1
        mode = .idle
    }

    func accepts(_ token: Int, for expectedMode: ReaderPlaybackMode) -> Bool {
        guard token == generation else { return false }
        switch (mode, expectedMode) {
        case (.autoScroll(let active), .autoScroll):
            return active == token
        case (.speech(let active), .speech), (.pausedSpeech(let active), .pausedSpeech):
            return active == token
        default:
            return false
        }
    }
}

final class ReaderPlaybackCoordinator: ObservableObject {
    @Published private(set) var state = ReaderPlaybackStateMachine()

    var mode: ReaderPlaybackMode { state.mode }

    func beginAutoScroll() -> Int { state.beginAutoScroll() }
    func beginSpeech() -> Int { state.beginSpeech() }
    func pauseSpeech() { state.pauseSpeech() }
    func resumeSpeech() { state.resumeSpeech() }
    func stop() { state.stop() }

    func accepts(_ token: Int, for expectedMode: ReaderPlaybackMode) -> Bool {
        state.accepts(token, for: expectedMode)
    }
}

/// Deterministic segment queue used by the AVSpeech controller.
struct ReaderSpeechQueue: Equatable {
    private(set) var segments: [String] = []
    private(set) var paragraphIndexes: [Int] = []
    private(set) var nextIndex = 0

    var isFinished: Bool { nextIndex >= segments.count }

    mutating func reset(
        title: String,
        paragraphs: [String],
        startParagraphIndex: Int = 0,
        includeTitle: Bool = true
    ) {
        segments = []
        paragraphIndexes = []
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeStart = min(max(startParagraphIndex, 0), max(paragraphs.count - 1, 0))
        // The chapter title is useful only when playback starts at the actual
        // chapter beginning. Starting TTS from a visible page must never jump
        // back to the title or earlier paragraphs.
        if includeTitle, safeStart == 0, !trimmedTitle.isEmpty {
            segments.append(trimmedTitle)
            paragraphIndexes.append(-1)
        }
        for (index, paragraph) in paragraphs.enumerated() where index >= safeStart {
            let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            segments.append(trimmed)
            paragraphIndexes.append(index)
        }
        nextIndex = 0
    }

    mutating func dequeue() -> (index: Int, text: String)? {
        guard segments.indices.contains(nextIndex) else { return nil }
        let index = nextIndex
        nextIndex += 1
        return (paragraphIndexes[index], segments[index])
    }

    var totalSegments: Int { segments.count }
    var currentSegmentPosition: Int { nextIndex }

    mutating func stepBack() -> (index: Int, text: String)? {
        guard nextIndex > 1 else {
            nextIndex = 0
            return dequeue()
        }
        nextIndex = max(nextIndex - 2, 0)
        return dequeue()
    }

    func lookaheadSegments(count: Int) -> [(index: Int, text: String)] {
        guard count > 0, nextIndex < segments.count else { return [] }
        let upperBound = min(nextIndex + count, segments.count)
        return (nextIndex..<upperBound).map { (paragraphIndexes[$0], segments[$0]) }
    }

    mutating func clear() {
        segments = []
        paragraphIndexes = []
        nextIndex = 0
    }
}

/// Expands word-level `AVSpeechSynthesizerDelegate` ranges to clean sentence boundaries
/// so read-aloud highlighting stays calm and legible without flickering per character.
enum ReaderSpeechSentenceLocator {
    private static let terminators = CharacterSet(charactersIn: "。！？；!?;…\n\r")
    private static let trailingClosers = CharacterSet(charactersIn: "”’」』》）\"')]")

    static func sentenceRange(in paragraph: String, around wordRange: NSRange) -> NSRange? {
        let nsText = paragraph as NSString
        let totalLength = nsText.length
        guard totalLength > 0,
              wordRange.location != NSNotFound,
              wordRange.location < totalLength else {
            return nil
        }

        let safeLocation = max(0, min(wordRange.location, totalLength - 1))
        let safeEnd = max(safeLocation + 1, min(totalLength, wordRange.location + max(wordRange.length, 1)))

        var start = safeLocation
        while start > 0 {
            let prevUnit = nsText.character(at: start - 1)
            if let scalar = UnicodeScalar(prevUnit), terminators.contains(scalar) {
                break
            }
            start -= 1
        }
        while start < safeEnd {
            let unit = nsText.character(at: start)
            if let scalar = UnicodeScalar(unit),
               CharacterSet.whitespacesAndNewlines.contains(scalar) || trailingClosers.contains(scalar) {
                start += 1
            } else {
                break
            }
        }

        var end = safeEnd
        while end < totalLength {
            let unit = nsText.character(at: end)
            end += 1
            if let scalar = UnicodeScalar(unit), terminators.contains(scalar) {
                while end < totalLength,
                      let nextScalar = UnicodeScalar(nsText.character(at: end)),
                      terminators.contains(nextScalar) || trailingClosers.contains(nextScalar) {
                    end += 1
                }
                break
            }
        }

        let length = max(0, min(totalLength - start, end - start))
        guard length > 0 else {
            return NSRange(location: 0, length: totalLength)
        }
        return NSRange(location: start, length: length)
    }
}

/// An online HTTP TTS voice configuration model compatible with Legado/SourceRead httpTTS.json
struct HttpTTSVoice: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: Int
    let name: String
    let url: String
    var contentType: String?
    var loginUrl: String?
    var concurrentRate: String?
    var header: String?

    init(
        id: Int,
        name: String,
        url: String,
        contentType: String? = nil,
        loginUrl: String? = nil,
        concurrentRate: String? = nil,
        header: String? = nil
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.contentType = contentType
        self.loginUrl = loginUrl
        self.concurrentRate = concurrentRate
        self.header = header
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case url
        case contentType
        case loginUrl
        case concurrentRate
        case header
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedName = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        let decodedURL = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
        self.name = decodedName
        self.url = decodedURL
        self.contentType = try container.decodeIfPresent(String.self, forKey: .contentType)
        self.loginUrl = try container.decodeIfPresent(String.self, forKey: .loginUrl)
        self.concurrentRate = try container.decodeIfPresent(String.self, forKey: .concurrentRate)
        self.header = try container.decodeIfPresent(String.self, forKey: .header)

        if let intID = try? container.decode(Int.self, forKey: .id) {
            self.id = intID
        } else if let int64ID = try? container.decode(Int64.self, forKey: .id) {
            self.id = Int(truncatingIfNeeded: int64ID)
        } else if let strID = try? container.decode(String.self, forKey: .id),
                  let parsed = Int(strID.trimmingCharacters(in: .whitespacesAndNewlines)) {
            self.id = parsed
        } else {
            let seed = "\(decodedName)|\(decodedURL)".utf8.reduce(5381) { (($0 << 5) &+ $0) &+ Int($1) }
            self.id = abs(seed % 900_000) + 10_000
        }
    }

    /// Stable default used by `@AppStorage("reader.httpTTSVoiceID")` before
    /// the user picks a preset.
    static let defaultVoiceID = -1

    var isPost: Bool {
        url.contains("\"method\": \"POST\"") || url.contains("\"method\":\"POST\"")
    }

    /// Default production preset voices extracted from SourceRead httpTTS.json
    static let defaultVoices: [HttpTTSVoice] = [
        HttpTTSVoice(
            id: -1,
            name: "度丫丫 (亲切女声)",
            url: #"http://tts.baidu.com/text2audio,{"method":"POST","body":"tex={{java.encodeURI(java.encodeURI(speakText))}}&spd={{(speakSpeed + 5) / 10 + 4}}&per=4&cuid=baidu_speech_demo&idx=1&cod=2&lan=zh&ctp=1&pdt=301&vol=5&aue=6&pit=5&_res_tag_=audio"}"#
        ),
        HttpTTSVoice(
            id: -6,
            name: "度小宇 (质感男声)",
            url: #"http://tts.baidu.com/text2audio,{"method":"POST","body":"tex={{java.encodeURI(java.encodeURI(speakText))}}&spd={{(speakSpeed + 5) / 10 + 4}}&per=2&cuid=baidu_speech_demo&idx=1&cod=2&lan=zh&ctp=1&pdt=301&vol=5&aue=6&pit=5&_res_tag_=audio"}"#
        ),
        HttpTTSVoice(
            id: -90,
            name: "标准女声 (播音)",
            url: #"http://tts.baidu.com/text2audio,{"method":"POST","body":"tex={{java.encodeURI(java.encodeURI(speakText))}}&spd={{(speakSpeed + 5) / 10 + 4}}&per=100&cuid=baidu_speech_demo&idx=1&cod=2&lan=zh&ctp=1&pdt=160&vol=5&aue=6&pit=5&_res_tag_=audio"}"#
        ),
        HttpTTSVoice(
            id: -86,
            name: "百度解说 (影视旁白)",
            url: #"http://tts.baidu.com/text2audio,{"method":"POST","body":"tex={{java.encodeURI(java.encodeURI(speakText))}}&spd={{(speakSpeed + 5) / 10 + 4}}&per=4123&cuid=baidu_speech_demo&idx=1&cod=2&lan=zh&ctp=1&pdt=12&vol=5&aue=6&pit=5&_res_tag_=audio"}"#
        )
    ] + AzureTTSVoice.presets

    /// Resolves the Legado HTTP TTS request template by evaluating embedded JS expressions.
    func resolveRequest(
        speakText: String,
        speakSpeed: Int = 5,
        runtime: JSCoreRuntime = JSCoreRuntime()
    ) -> (url: URL, method: String, body: String?, headers: [String: String])? {
        var evaluated = url
        let pattern = #"\{\{([^\}]+)\}\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsString = evaluated as NSString
        let matches = regex.matches(in: evaluated, range: NSRange(location: 0, length: nsString.length))

        var replacements: [(range: NSRange, replacement: String)] = []
        for match in matches {
            let exprRange = match.range(at: 1)
            let expr = nsString.substring(with: exprRange)
            let escapedText = speakText
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\r", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
            let jsScript = "var speakText = '\(escapedText)'; var speakSpeed = \(speakSpeed); \(expr);"
            guard case .success(let value) = runtime.evaluate(jsScript) else { return nil }
            replacements.append((match.range, value))
        }
        for rep in replacements.reversed() {
            evaluated = (evaluated as NSString).replacingCharacters(in: rep.range, with: rep.replacement)
        }

        let parts = evaluated.components(separatedBy: ",{")
        guard let base = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines),
              let targetURL = URL(string: base) else { return nil }

        var method = "GET"
        var body: String? = nil
        var headers: [String: String] = ["User-Agent": "Mozilla/5.0 SourceReadSwift iOS"]
        if let customHeader = header?.trimmingCharacters(in: .whitespacesAndNewlines),
           !customHeader.isEmpty,
           let headerData = customHeader.data(using: .utf8),
           let headerDict = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any] {
            for (key, value) in headerDict {
                if let stringValue = value as? String {
                    headers[key] = stringValue
                } else {
                    headers[key] = "\(value)"
                }
            }
        }

        if parts.count > 1, let jsonData = ("{" + parts[1]).data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
            if let rawMethod = dict["method"] as? String, rawMethod.uppercased() == "POST" {
                method = "POST"
            }
            if let postBody = dict["body"] as? String {
                body = postBody
                headers["Content-Type"] = "application/x-www-form-urlencoded"
            }
            if let rawHeaders = dict["headers"] as? [String: Any] {
                for (key, value) in rawHeaders {
                    if let stringValue = value as? String {
                        headers[key] = stringValue
                    }
                }
            }
        }
        return (targetURL, method, body, headers)
    }
}
