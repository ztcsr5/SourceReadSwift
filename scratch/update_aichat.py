path = r"D:\Gemini反重力\SourceReadSwift2\SourceReadSwift\Features\Settings\AIChatView.swift"
with open(path, "r", encoding="utf-8") as f:
    text = f.read().replace("\r\n", "\n")

# Check imports
import_target = "import SwiftUI\nimport UniformTypeIdentifiers"
import_replacement = "import SwiftUI\nimport UniformTypeIdentifiers\nimport WebKit"

assert import_target in text, "import_target not found"
text = text.replace(import_target, import_replacement, 1)

# Check state variables in AIChatView
state_target = """    @AppStorage("settings.ai.configuration") private var storedConfiguration = Data()
    @StateObject private var session = AIChatSession()"""

state_replacement = """    @AppStorage("settings.ai.configuration") private var storedConfiguration = Data()
    @AppStorage("settings.ai.assistant_mode") private var selectedModeRaw = "api"
    @StateObject private var session = AIChatSession()"""

assert state_target in text, "state_target not found"
text = text.replace(state_target, state_replacement, 1)

# Check body in AIChatView
body_target = """    var body: some View {
        VStack(spacing: 0) {
            transcript
            if let status = session.status {
                Text(status).font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.vertical, 6)
            }
            composer
        }
        .pageBackground()
        .navigationTitle("AI 助手")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button { showClear = true } label: { Image(systemName: "trash") }.accessibilityLabel("清空本次会话")
                Button { showConfiguration = true } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("AI 接口配置")
            }
            ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完成") { composing = false } }
        }"""

# Note: The file might have different chinese or encoding in the navigationTitle/accessibilityLabels,
# so let's locate the body bounds dynamically.
body_start = text.find("    var body: some View {")
assert body_start != -1, "body_start not found"
on_appear_idx = text.find("        .onAppear {", body_start)
assert on_appear_idx != -1, "onAppear not found"

original_body = text[body_start:on_appear_idx]

new_body = """    private var currentMode: AIAssistantMode {
        AIAssistantMode(rawValue: selectedModeRaw) ?? .api
    }

    var body: some View {
        VStack(spacing: 0) {
            modeSelector
            if currentMode == .api {
                transcript
                if let status = session.status {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.vertical, 6)
                }
                composer
            } else if let targetURL = currentMode.serviceURL {
                AIWebAssistantView(targetURL: targetURL, serviceName: currentMode.title)
            }
        }
        .pageBackground()
        .navigationTitle(currentMode == .api ? "AI 助手" : currentMode.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if currentMode == .api {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { showClear = true } label: { Image(systemName: "trash") }.accessibilityLabel("清空本次会话")
                    Button { showConfiguration = true } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("AI 接口配置")
                }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完成") { composing = false } }
            }
        }
"""

text = text[:body_start] + new_body + text[on_appear_idx:]

# Now add modeSelector helper in AIChatView
mode_selector_helper = """
    private var modeSelector: some View {
        Picker("AI 模式", selection: $selectedModeRaw) {
            ForEach(AIAssistantMode.allCases) { mode in
                Text(mode.title).tag(mode.rawValue)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
"""

transcript_anchor = "    private var transcript: some View {"
assert transcript_anchor in text, "transcript_anchor not found"
text = text.replace(transcript_anchor, mode_selector_helper + "\n" + transcript_anchor, 1)

# Now append AIAssistantMode and AIWebAssistantView, AIWebState, AIWebViewContainer to the end of file
trailing_code = """

// MARK: - AI Assistant Multi-Mode & Web AI Integration

enum AIAssistantMode: String, CaseIterable, Identifiable {
    case api = "api"
    case doubao = "doubao"
    case kimi = "kimi"
    case deepseek = "deepseek"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .api: return "接口"
        case .doubao: return "豆包"
        case .kimi: return "Kimi"
        case .deepseek: return "DeepSeek"
        }
    }

    var serviceURL: URL? {
        switch self {
        case .api: return nil
        case .doubao: return URL(string: "https://www.doubao.com/chat/")
        case .kimi: return URL(string: "https://kimi.moonshot.cn/")
        case .deepseek: return URL(string: "https://chat.deepseek.com/")
        }
    }
}

struct AIWebAssistantView: View {
    let targetURL: URL
    let serviceName: String
    @Environment(\\.openURL) private var openURL
    @StateObject private var webState = AIWebState()

    var body: some View {
        VStack(spacing: 0) {
            if webState.isLoading && webState.progress < 1.0 {
                ProgressView(value: webState.progress, total: 1.0)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
                    .frame(height: 2)
            }
            AIWebViewContainer(targetURL: targetURL, state: webState)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            webToolbar
        }
    }

    private var webToolbar: some View {
        HStack(spacing: 18) {
            Button {
                webState.webView?.goBack()
            } label: {
                Image(systemName: "chevron.backward")
            }
            .disabled(!webState.canGoBack)

            Button {
                webState.webView?.goForward()
            } label: {
                Image(systemName: "chevron.forward")
            }
            .disabled(!webState.canGoForward)

            Button {
                webState.webView?.reload()
            } label: {
                Image(systemName: "arrow.clockwise")
            }

            Button {
                webState.webView?.load(URLRequest(url: targetURL))
            } label: {
                Image(systemName: "house")
            }

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "lock.shield.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
                Text(webState.currentHost.isEmpty ? serviceName : webState.currentHost)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                if let url = webState.currentURL ?? Optional(targetURL) {
                    openURL(url)
                }
            } label: {
                Image(systemName: "safari")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

@MainActor
final class AIWebState: ObservableObject {
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var isLoading: Bool = false
    @Published var progress: Double = 0.0
    @Published var currentURL: URL?
    @Published var currentHost: String = ""
    weak var webView: WKWebView?
}

struct AIWebViewContainer: UIViewRepresentable {
    let targetURL: URL
    @ObservedObject var state: AIWebState

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        context.coordinator.setupObservation(for: webView)
        state.webView = webView
        let request = URLRequest(url: targetURL)
        webView.load(request)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        state.webView = uiView
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        coordinator.cleanup()
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let state: AIWebState
        private var progressObservation: NSKeyValueObservation?
        private var canGoBackObservation: NSKeyValueObservation?
        private var canGoForwardObservation: NSKeyValueObservation?
        private var urlObservation: NSKeyValueObservation?

        init(state: AIWebState) {
            self.state = state
        }

        func setupObservation(for webView: WKWebView) {
            progressObservation = webView.observe(\\.estimatedProgress, options: [.new]) { [weak self] view, _ in
                Task { @MainActor in
                    self?.state.progress = view.estimatedProgress
                }
            }
            canGoBackObservation = webView.observe(\\.canGoBack, options: [.new]) { [weak self] view, _ in
                Task { @MainActor in
                    self?.state.canGoBack = view.canGoBack
                }
            }
            canGoForwardObservation = webView.observe(\\.canGoForward, options: [.new]) { [weak self] view, _ in
                Task { @MainActor in
                    self?.state.canGoForward = view.canGoForward
                }
            }
            urlObservation = webView.observe(\\.url, options: [.new]) { [weak self] view, _ in
                Task { @MainActor in
                    self?.state.currentURL = view.url
                    self?.state.currentHost = view.url?.host ?? ""
                }
            }
        }

        func cleanup() {
            progressObservation?.invalidate()
            canGoBackObservation?.invalidate()
            canGoForwardObservation?.invalidate()
            urlObservation?.invalidate()
            progressObservation = nil
            canGoBackObservation = nil
            canGoForwardObservation = nil
            urlObservation = nil
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            Task { @MainActor in
                state.isLoading = true
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                state.isLoading = false
                state.canGoBack = webView.canGoBack
                state.canGoForward = webView.canGoForward
                state.currentURL = webView.url
                state.currentHost = webView.url?.host ?? ""
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                state.isLoading = false
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                state.isLoading = false
            }
        }
    }
}
"""

text = text.rstrip() + trailing_code + "\n"

with open(path, "w", encoding="utf-8", newline="\n") as f:
    f.write(text)

print("SUCCESS: AIChatView.swift updated!")
