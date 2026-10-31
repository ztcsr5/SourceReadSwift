import SwiftUI
import Foundation
import WebKit

/// Native login/verification surface for sources that cannot be exercised by URLSession alone.
///
/// Two modes, mirroring Legado:
/// - `loginUi` non-empty → a configured form (`RowUi` rows).  Submitting stores
///   the values where `source.getLoginInfoMap()` reads them and runs `loginUrl`
///   as JS (`BaseSource.login()`, BaseSource.kt L47-51).
/// - otherwise → an in-app browser; cookies are copied into the same actor used
///   by the Legado engine when navigation finishes.
struct SourceLoginView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let source: BookSource
    let cookieStore: SourceCookieStore
    var engine: SourceEngine?

    @State private var status = "正在打开登录页…"
    @State private var input: [String: String] = [:]
    @State private var busy = false
    @State private var resolvedFields: [SourceLoginField]?
    @StateObject private var readingSession = WebReadingSession()

    private var fields: [SourceLoginField] {
        resolvedFields ?? SourceLoginFieldParser.parse(source.loginUi)
    }

    private var hasConfiguredForm: Bool {
        !(source.loginUi ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                statusBar
                if !hasConfiguredForm {
                    pageContent
                        .overlay {
                            if let article = readingSession.article { ExtractedArticleView(article: article) }
                        }
                        .safeAreaInset(edge: .bottom) {
                            VStack(spacing: 6) {
                                if let error = readingSession.errorMessage { Text(error).font(.caption).foregroundStyle(.red) }
                                Button {
                                    if readingSession.article != nil { readingSession.article = nil }
                                    else { readingSession.extractCurrentPage() }
                                } label: {
                                    Label(readingSession.article != nil ? "返回登录网页" : (readingSession.isExtracting ? "提取中…" : "提取当前页正文并阅读"), systemImage: "doc.text.magnifyingglass")
                                }
                                .buttonStyle(.bordered).disabled(readingSession.isExtracting)
                            }.padding(10).background(.regularMaterial)
                        }
                } else {
                    formContent
                }
            }
            .navigationTitle(source.bookSourceName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if !hasConfiguredForm {
                        Button("完成") { finishWebLogin() }
                            .disabled(busy)
                    } else {
                        Button("登录") { submit() }
                            .disabled(busy)
                    }
                }
            }
        }
        .presentationDetents([.large])
        .onDisappear { readingSession.cancelExtraction() }
        .task {
            if !hasConfiguredForm, loginTarget?.usedBookSourceFallback == true {
                status = "该书源未配置 loginUrl，已打开书源主页，请登录后点完成"
            } else if hasConfiguredForm {
                await loadFields()
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            if busy {
                ProgressView().controlSize(.mini)
            } else {
                Image(systemName: fields.isEmpty ? "lock.open" : "person.badge.key")
            }
            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.08))
    }

    @ViewBuilder
    private var pageContent: some View {
        if let target = loginTarget {
            SourceLoginWebView(url: target.url, cookieStore: cookieStore, readingSession: readingSession) { message in
                status = message
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title)
                    .foregroundStyle(.orange)
                Text("该书源没有可打开的页面")
                    .font(.headline)
                Text("书源 JSON 既没有 loginUrl，也没有合法的 bookSourceUrl。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var formContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(fields) { field in
                    fieldRow(field)
                }
                if !busy {
                    Button {
                        submit()
                    } label: {
                        Text("登录")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
                }
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func fieldRow(_ field: SourceLoginField) -> some View {
        switch field.type {
        case .text:
            VStack(alignment: .leading, spacing: 6) {
                Text(field.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(field.name, text: binding(for: field.name))
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(busy)
            }
        case .password:
            VStack(alignment: .leading, spacing: 6) {
                Text(field.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SecureField(field.name, text: binding(for: field.name))
                    .textFieldStyle(.roundedBorder)
                    .disabled(busy)
            }
        case .button:
            Button {
                executeAction(field.action)
            } label: {
                Text(field.name).frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(busy)
        case .toggle:
            if field.choices.isEmpty {
                Toggle(field.name, isOn: Binding(
                    get: { ["true", "1", "on"].contains((input[field.name] ?? "").lowercased()) },
                    set: { input[field.name] = $0 ? "true" : "false" }
                ))
                .disabled(busy)
            } else {
                Picker(field.name, selection: binding(for: field.name)) {
                    ForEach(field.choices, id: \.self) { choice in
                        Text(choice).tag(choice)
                    }
                }
                .disabled(busy)
            }
        }
    }

    @MainActor
    private func loadFields() async {
        guard let engine else {
            if SourceLoginScript.dynamicUI(from: source.loginUi) != nil {
                status = "阅读引擎尚未就绪，无法加载动态登录表单"
            }
            return
        }
        busy = true
        status = "正在加载书源登录与配置表单…"
        let result = await engine.loginFields(source: source)
        busy = false
        switch result {
        case .success(let loaded):
            applyFields(loaded)
            status = "可输入登录信息，或点击书源提供的操作按钮"
        case .failure(let error):
            status = "表单加载失败：\(error.displayMessage)"
        }
    }

    private func applyFields(_ loaded: [SourceLoginField]) {
        resolvedFields = loaded
        for field in loaded {
            if let value = field.defaultValue {
                input[field.name] = value
            } else if input[field.name] == nil, let first = field.choices.first {
                input[field.name] = first
            }
        }
    }

    private func executeAction(_ action: String?) {
        guard let action = action?.trimmingCharacters(in: .whitespacesAndNewlines), !action.isEmpty else {
            status = "该按钮未配置操作"
            return
        }
        // URL(string:) also accepts login() as a relative URL. Only an
        // explicit external scheme may go to openURL; JS goes to the engine.
        if let url = URL(string: action), let scheme = url.scheme?.lowercased(),
           !["javascript", "data", "file"].contains(scheme) {
            openURL(url)
            return
        }
        guard let engine else {
            status = "阅读引擎尚未就绪，无法执行书源操作"
            return
        }
        busy = true
        status = "正在执行书源操作…"
        let credentials = input
        Task {
            let result = await engine.performLoginAction(source: source, action: action, credentials: credentials)
            await MainActor.run {
                busy = false
                switch result {
                case .success(let loaded):
                    applyFields(loaded)
                    status = "操作已执行，表单已刷新；书源可用性仍以搜索与正文验证为准"
                case .failure(let error):
                    status = "操作失败：\(error.displayMessage)"
                }
            }
        }
    }

    private func binding(for name: String) -> Binding<String> {
        Binding(
            get: { input[name] ?? "" },
            set: { input[name] = $0 }
        )
    }

    private func submit() {
        // Extended Legado sources expose the real login entry as a button.
        // Evaluating loginUrl alone merely declares login(), it does not call
        // that function or authenticate the user.
        if let loginButton = fields.first(where: {
            $0.type == .button && ($0.action?.trimmingCharacters(in: .whitespacesAndNewlines) == "login()"
                || ["登录", "登入", "登錄", "立即登录"].contains($0.name))
        }), let action = loginButton.action {
            executeAction(action)
            return
        }
        guard let engine else {
            status = "阅读引擎尚未就绪，无法提交登录"
            return
        }
        busy = true
        status = "正在登录…"
        let credentials = input
        Task {
            let result = await engine.login(source: source, credentials: credentials)
            await MainActor.run {
                busy = false
                switch result {
                case .success(let verification):
                    status = verification.message
                    if verification.status == .passed || verification.status == .notConfigured {
                        dismiss()
                    }
                case .failure(let error):
                    status = "登录失败：\(error.displayMessage)"
                }
            }
        }
    }

    /// The in-app browser is the only sign-in path for sources without
    /// `loginUi`.  Cookies set by XHR after the final navigation never reach
    /// `SourceCookieStore` by themselves, so read the WKWebView cookie jar when
    /// the reader taps 完成 and persist everything before dismissing.
    private func finishWebLogin() {
        guard !busy else { return }
        busy = true
        status = "正在保存登录状态…"
        Task {
            let cookies = await collectWebViewCookies()
            await cookieStore.storeWebViewCookies(cookies)
            await MainActor.run {
                busy = false
                if cookies.isEmpty {
                    status = "没有读到 Cookie：请确认网页里已登录成功，再点完成"
                } else {
                    status = "已保存 \(cookies.count) 个 Cookie"
                    dismiss()
                }
            }
        }
    }

    /// Reads the shared WKWebView jar.  `SourceLoginWebView` always uses
    /// `WKWebsiteDataStore.default()`, so this is the same store it writes to.
    private func collectWebViewCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }

    private var loginTarget: SourceLoginURLResolver.Target? {
        SourceLoginURLResolver.resolve(
            loginUrl: source.loginUrl,
            bookSourceUrl: source.networkBaseURL
        )
    }
}

private struct SourceLoginWebView: UIViewRepresentable {
    let url: URL
    let cookieStore: SourceCookieStore
    let readingSession: WebReadingSession
    let onStatus: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(cookieStore: cookieStore, onStatus: onStatus)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        readingSession.webView = webView
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let cookieStore: SourceCookieStore
        let onStatus: (String) -> Void

        init(cookieStore: SourceCookieStore, onStatus: @escaping (String) -> Void) {
            self.cookieStore = cookieStore
            self.onStatus = onStatus
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            onStatus("正在加载…")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                let cookies: [HTTPCookie] = await withCheckedContinuation { continuation in
                    webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                        continuation.resume(returning: cookies)
                    }
                }
                await cookieStore.storeWebViewCookies(cookies)
                onStatus(cookies.isEmpty
                    ? "页面已加载，尚未获取到 Cookie"
                    : "页面已加载，已同步 \(cookies.count) 个 Cookie")
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onStatus("页面加载失败：\(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            onStatus("页面加载失败：\(error.localizedDescription)")
        }
    }
}
