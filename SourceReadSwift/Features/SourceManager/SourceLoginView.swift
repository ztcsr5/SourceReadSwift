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
    @State private var feedback: SourceLoginFeedback?
    @State private var sourceMessages: [String] = []
    @State private var persistenceWarning: String?
    @State private var input: [String: String] = [:]
    @State private var busy = false
    @State private var resolvedFields: [SourceLoginField]?
    @State private var browserPresentation: SourceLoginPresentation?
    @State private var isBrowserPresented = false
    @State private var presentedBrowserRequestID: UUID?
    @State private var pendingBrowserPresentation: SourceLoginPresentation?
    @State private var operation: Task<Void, Never>?
    @ObservedObject private var browserCoordinator = SourceBrowserLoginCoordinator.shared
    @StateObject private var readingSession = WebReadingSession()
    @StateObject private var cookieScope = SourceLoginCookieScope()

    private var fields: [SourceLoginField] {
        resolvedFields ?? SourceLoginFieldParser.parse(source.loginUi)
    }

    private var hasConfiguredForm: Bool {
        !(source.loginUi ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var primarySubmissionTitle: String {
        if SourceLoginFieldParser.primarySignInAction(in: fields) != nil { return "登录" }
        return SourceLoginScript.dynamicUI(from: source.loginUi) == nil ? "提交表单" : "保存配置"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                statusBar
                if let feedback { feedbackBanner(feedback) }
                if !sourceMessages.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("书源提示", systemImage: "text.bubble").font(.caption.weight(.semibold))
                        ScrollView {
                            Text(sourceMessages.joined(separator: "\n"))
                                .font(.caption)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 100)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.secondary.opacity(0.08))
                    .accessibilityIdentifier("source-login-authored-messages")
                }
                if let persistenceWarning {
                    Text(persistenceWarning).font(.caption).foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12)
                        .accessibilityIdentifier("source-login-persistence-warning")
                }
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
            .pageBackground()
            .navigationTitle(source.bookSourceName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { cancelOperation(); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if !hasConfiguredForm {
                        Button("完成") { finishWebLogin() }
                            .disabled(busy)
                    } else {
                        Button(primarySubmissionTitle) { submit() }
                            .disabled(busy || fields.isEmpty)
                    }
                }
            }
        }
        .presentationDetents([.large])
        .sheet(item: $browserPresentation, onDismiss: browserDidDismiss) { presentation in
            SourceLoginDestinationView(
                destination: presentation.destination, cookieStore: cookieStore,
                browserTitle: presentation.title,
                onCompleted: { completeBrowser(presentation, response: $0) },
                onCancelled: {
                    if let id = presentation.requestID { browserCoordinator.cancel(id: id) }
                })
        }
        .onReceive(browserCoordinator.$request) { receiveBrowserRequest($0) }
        .onDisappear {
            readingSession.cancelExtraction()
            if !isBrowserPresented { cancelOperation() }
        }
        .task {
            if !hasConfiguredForm, loginTarget?.usedBookSourceFallback == true {
                status = "该书源未配置 loginUrl，已打开书源主页，请登录后点完成"
            } else if hasConfiguredForm, resolvedFields == nil, !busy {
                await loadFields()
            }
        }
    }

    private func feedbackBanner(_ feedback: SourceLoginFeedback) -> some View {
        let color: Color = switch feedback.tone {
        case .information: .secondary
        case .success: .green
        case .warning: .orange
        case .failure: .red
        }
        let icon = switch feedback.tone {
        case .information: "info.circle.fill"
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .failure: "xmark.circle.fill"
        }
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundStyle(color)
                Text(feedback.title).font(.subheadline.weight(.semibold))
            }
            Text(feedback.message).font(.caption).textSelection(.enabled)
        }
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(color.opacity(0.10))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("source-login-feedback")
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
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.08))
    }

    @ViewBuilder
    private var pageContent: some View {
        if let target = loginTarget {
            SourceLoginWebView(url: target.url, cookieStore: cookieStore, readingSession: readingSession,
                               cookieScope: cookieScope) { message in
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
                VStack(alignment: .leading, spacing: 6) {
                    Text("账号、注册与书源配置").font(.headline)
                    Text("请使用书源提供的登录、注册或仪表盘按钮。需要 API Key 时，先在作者网页获取，再回到此处保存；部分书源无需登录。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let update = fields.first(where: {
                    $0.type == .button && ($0.name.contains("更新书源") || $0.name.contains("書源更新") || $0.name.contains("书源更新"))
                }) {
                    Button {
                        executeAction(update.action)
                    } label: {
                        Label("检查书源更新", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(busy)
                    .accessibilityIdentifier("source-check-publisher-update")
                }
                ForEach(fields) { field in
                    fieldRow(field)
                }
                if !busy {
                    Button {
                        submit()
                    } label: {
                        Text(primarySubmissionTitle)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
                    .disabled(fields.isEmpty)
                }
                Button("验证登录状态") { checkLogin() }
                    .buttonStyle(.bordered)
                    .disabled(busy)
                    .accessibilityIdentifier("source-login-verify")
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
                executeAction(field.action,
                    verifiesLogin: field.action == SourceLoginFieldParser.primarySignInAction(in: fields))
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
                reportFailure("阅读引擎尚未就绪，无法加载动态登录表单")
            }
            return
        }
        busy = true
        status = "正在加载书源登录与配置表单…"
        let result = await engine.loginFields(source: source)
        guard !Task.isCancelled else { return }
        busy = false
        switch result {
        case .success(let loaded):
            applyFields(loaded)
            status = loaded.isEmpty ? "书源没有返回表单，请检查书源版本" : "可输入登录信息，或点击书源提供的操作按钮"
        case .failure(let error):
            status = "表单加载失败：\(error.displayMessage)"
            feedback = SourceLoginFeedback(title: "无法加载登录表单", message: error.displayMessage, tone: .failure)
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

    private func executeAction(_ action: String?, verifiesLogin: Bool = false) {
        guard !busy else { return }
        persistenceWarning = nil
        feedback = nil
        sourceMessages = []
        guard let action = action?.trimmingCharacters(in: .whitespacesAndNewlines), !action.isEmpty else {
            reportFailure("该按钮未配置操作")
            return
        }
        if let url = SourceLoginBrowserAction.loginWebURL(action) {
            presentBrowser(SourceLoginPresentation(destination: .web(url, waitsForAndroidResult: false)))
            return
        }
        // URL(string:) also accepts login() as a relative URL. Only explicit
        // external app schemes go to openURL; web login stays in the shared cookie store.
        if let url = URL(string: action), let scheme = url.scheme?.lowercased(),
           !["javascript", "data", "file", "http", "https"].contains(scheme) {
            openURL(url)
            return
        }
        guard let engine else {
            reportFailure("阅读引擎尚未就绪，无法执行书源操作")
            return
        }
        busy = true
        status = "正在执行书源操作…"
        let credentials = input
        operation = Task { @MainActor in
            let result = await engine.performLoginInteraction(source: source, action: action, credentials: credentials)
            guard !Task.isCancelled else { return }
            switch result {
            case .success(let interaction):
                sourceMessages = interaction.messages
                if let destination = interaction.destination {
                    presentBrowser(SourceLoginPresentation(destination: destination))
                    status = "书源请求打开网页，请在弹出的界面确认"
                } else {
                    applyFields(interaction.fields)
                    status = "书源操作已执行"
                    if verifiesLogin {
                        await showVerification(using: engine)
                    } else {
                        feedback = SourceLoginFeedback(title: "书源操作已执行", message: "请查看书源提示。保存配置或打开网页不代表账号已通过验证。", tone: .information)
                    }
                }
                persistenceWarning = interaction.persistenceWarning
            case .failure(let error):
                reportFailure(error.displayMessage)
            }
            busy = false
        }
    }

    private func binding(for name: String) -> Binding<String> {
        Binding(
            get: { input[name] ?? "" },
            set: { input[name] = $0 }
        )
    }

    private func submit() {
        guard !busy else { return }
        persistenceWarning = nil
        // Extended Legado sources expose the real login entry as a button.
        // Evaluating loginUrl alone merely declares login(), it does not call
        // that function or authenticate the user.
        if let action = SourceLoginFieldParser.primarySignInAction(in: fields) {
            executeAction(action, verifiesLogin: true)
            return
        }
        let isDynamicForm = SourceLoginScript.dynamicUI(from: source.loginUi) != nil
        // Legacy inline loginUrl already runs while the interaction context loads.
        // Only dynamic configuration forms need an additional authored save call.
        let action = isDynamicForm ? "if (typeof login === 'function') { login(); }" : "void 0"
        executeAction(action, verifiesLogin: !isDynamicForm)
    }

    private func checkLogin() {
        guard !busy else { return }
        guard let engine else { reportFailure("阅读引擎尚未就绪，无法验证登录"); return }
        feedback = nil
        busy = true
        status = "正在验证登录状态…"
        operation = Task { @MainActor in
            await showVerification(using: engine)
            guard !Task.isCancelled else { return }
            busy = false
        }
    }

    @MainActor
    private func showVerification(using engine: SourceEngine) async {
        let result = await engine.verifyLogin(source: source)
        guard !Task.isCancelled else { return }
        switch result {
        case .success(let verification):
            feedback = SourceLoginFeedback(verification: verification)
            status = "登录状态校验已完成"
        case .failure(let error):
            reportFailure(error.displayMessage)
        }
    }

    private func reportFailure(_ message: String) {
        status = "操作未完成"
        feedback = SourceLoginFeedback(title: "操作失败", message: message, tone: .failure)
    }

    /// The in-app browser is the only sign-in path for sources without
    /// `loginUi`.  Cookies set by XHR after the final navigation never reach
    /// `SourceCookieStore` by themselves, so read the WKWebView cookie jar when
    /// the reader taps 完成 and persist everything before dismissing.
    private func finishWebLogin() {
        guard !busy, let webView = readingSession.webView else { return }
        busy = true
        status = "正在保存登录状态…"
        operation = Task { @MainActor in
            do {
                let count = try await SourceLoginBrowserCookies.synchronizePersistently(from: webView, into: cookieStore, scope: cookieScope)
                guard !Task.isCancelled else { return }
                if count == 0 {
                    feedback = SourceLoginFeedback(title: "尚未读取到网页会话", message: "网页没有返回 Cookie。部分书源改用 API Key 或 Token，请按作者说明完成配置。", tone: .warning)
                    status = "网页会话同步已完成"
                } else {
                    status = "已保存网页会话"
                    feedback = SourceLoginFeedback(title: "网页会话已保存", message: "已保存网页 Cookie，账号是否有效仍需书源校验。", tone: .information)
                }
                if let engine { await showVerification(using: engine) }
                guard !Task.isCancelled else { return }
                busy = false
            } catch {
                guard !Task.isCancelled else { return }
                busy = false
                reportFailure(error.localizedDescription)
            }
        }
    }

    private func receiveBrowserRequest(_ request: SourceBrowserLoginRequest?) {
        guard let request else {
            if pendingBrowserPresentation?.requestID != nil { pendingBrowserPresentation = nil }
            if browserPresentation?.requestID != nil { browserPresentation = nil }
            return
        }
        guard busy, presentedBrowserRequestID != request.id else { return }
        presentBrowser(SourceLoginPresentation(
            destination: .web(request.url, waitsForAndroidResult: true),
            title: request.title.isEmpty ? "书源登录" : request.title, requestID: request.id))
    }

    private func presentBrowser(_ presentation: SourceLoginPresentation) {
        guard !isBrowserPresented else {
            pendingBrowserPresentation = presentation
            return
        }
        isBrowserPresented = true
        presentedBrowserRequestID = presentation.requestID
        browserPresentation = presentation
    }

    private func completeBrowser(_ presentation: SourceLoginPresentation, response: SourceResponse) {
        if let id = presentation.requestID {
            browserCoordinator.submit(id: id, response: response)
        } else {
            status = "已保存网页会话"
            feedback = SourceLoginFeedback(title: "已返回书源表单", message: "网页会话已同步。若作者要求 API Key，请填入表单后保存，再验证登录状态。", tone: .information)
        }
    }

    private func browserDidDismiss() {
        if let id = presentedBrowserRequestID { browserCoordinator.cancel(id: id) }
        presentedBrowserRequestID = nil
        isBrowserPresented = false
        guard let pending = pendingBrowserPresentation else { return }
        pendingBrowserPresentation = nil
        if let id = pending.requestID, browserCoordinator.request?.id != id { return }
        presentBrowser(pending)
    }

    private func cancelOperation() {
        operation?.cancel()
        operation = nil
        if let id = presentedBrowserRequestID { browserCoordinator.cancel(id: id) }
        if let id = pendingBrowserPresentation?.requestID { browserCoordinator.cancel(id: id) }
        pendingBrowserPresentation = nil
        busy = false
        browserPresentation = nil
    }

    private struct SourceLoginPresentation: Identifiable {
        let id = UUID()
        let destination: SourceLoginDestination
        var title: String = "书源登录"
        var requestID: UUID? = nil
    }

    private var loginTarget: SourceLoginURLResolver.Target? {
        SourceLoginURLResolver.resolve(
            loginUrl: source.loginUrl,
            bookSourceUrl: source.networkBaseURL
        )
    }
}
