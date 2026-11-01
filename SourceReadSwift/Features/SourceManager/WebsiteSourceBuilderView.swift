import SwiftUI
import WebKit

struct WebsiteSourceBuilderView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var browser = WebReadingSession()
    @State private var address = "https://"
    @State private var destination: URL?
    @State private var catalog: WebsitePageSample?
    @State private var chapter: WebsitePageSample?
    @State private var name = ""
    @State private var tocCSS = ""
    @State private var contentCSS = ""
    @State private var draft: WebsiteSourceDraft?
    @State private var status = "打开书籍目录页，可先在网页内登录。"
    @State private var working = false
    @State private var validated = false
    @State private var worker: Task<Void, Never>?
    @State private var showPreview = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("输入站点地址", text: $address).keyboardType(.URL)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.go)
                    .onSubmit(openPage)
                Button("打开", action: openPage).disabled(working)
            }.padding(12).background(AppTheme.card)
            if let destination {
                ReadableWebView(url: destination, session: browser)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "globe.badge.chevron.backward").font(.largeTitle)
                    Text("网页 → 本地书源").font(.headline)
                    Text("先采集完整目录，再打开其中一章采集正文。支持渲染后的 HTML 或直接 JSON 响应；不会猜测隐藏接口。\n样本在本机分析，不调用 AI，不上传网页或登录信息。")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                HStack {
                    Button(catalog == nil ? "① 采集目录" : "① 重采目录") { capture(isCatalog: true) }
                    Button(chapter == nil ? "② 采集正文" : "② 重采正文") { capture(isCatalog: false) }
                    Spacer(minLength: 0)
                    Button(working ? "处理中…" : "③ 生成预览") { build() }
                        .disabled(catalog == nil || chapter == nil)
                }.font(.subheadline.weight(.medium)).buttonStyle(.bordered).disabled(working || browser.webView == nil)
            }.padding(12).background(AppTheme.card)
        }
        .pageBackground().navigationTitle("网页本地解析").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
        }
        .onDisappear { worker?.cancel(); browser.cancelExtraction() }
        .sheet(isPresented: $showPreview) { preview }
    }

    private var preview: some View {
        NavigationStack {
            Form {
                Section("规则草稿") {
                    TextField("书源名称", text: $name)
                    TextField("目录容器 CSS / JSONPath", text: $tocCSS).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("正文容器 CSS / JSONPath", text: $contentCSS).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("按当前选择器重新生成") { build() }.disabled(working)
                }.disabled(working)
                if let draft {
                    Section("本地样本已解析：\(draft.chapterCount) 章") {
                        Text(draft.example.name).font(.headline)
                        ForEach(draft.preview.indices, id: \.self) { Text(draft.preview[$0]).font(.subheadline).lineLimit(4) }
                    }
                    Section("验证后导入") {
                        Text("仅验证已采集的目录与正文模板，不代表整站兼容。HTML 提供此书发现入口；直接 JSON 仅生成已提供的接口规则，不猜搜索、发现、签名或加密接口。分页、付费与验证码需另行处理。")
                            .font(.footnote).foregroundStyle(.secondary)
                        Text(status).font(.caption)
                        Button(working ? "验证中…" : "联网验证目录和正文") { validate(draft) }.disabled(working)
                        Button("导入书源管理") { importDraft(draft) }.disabled(!validated || working)
                    }
                    Section("将保存的 JSON（不包含浏览器 Cookie）") {
                        Text(json(draft.source)).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: name) { _ in validated = false }
            .onChange(of: tocCSS) { _ in validated = false }
            .onChange(of: contentCSS) { _ in validated = false }
            .navigationTitle("本地规则预览").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("返回网页") { showPreview = false } } }
        }
    }

    private func openPage() {
        guard let url = WebsiteSourceInference.validURL(address) else { status = "请输入有效 HTTP/HTTPS 地址。"; return }
        destination = url
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func capture(isCatalog: Bool) {
        guard let web = browser.webView, let url = web.url, !web.isLoading,
              WebsiteSourceInference.validURL(url.absoluteString) != nil else { status = "请等目录或正文网页加载完成。"; return }
        worker?.cancel(); working = true; validated = false
        let generation = browser.documentGeneration
        worker = Task { @MainActor in
            defer { working = false }
            do {
                let value = try await web.evaluateJavaScript(WebsitePageCapture.script)
                guard !Task.isCancelled, browser.documentGeneration == generation, web.url == url,
                      let html = value as? String else { status = "页面已切换，请重新采集。"; return }
                let sample = WebsitePageSample(url: url, html: html)
                if isCatalog { catalog = sample; tocCSS = "" } else { chapter = sample; contentCSS = "" }
                draft = nil
                status = isCatalog ? "目录样本已采集。请点击其中一章，再采集正文。" : "正文样本已采集。可生成本地规则预览。"
            } catch { if !Task.isCancelled { status = error.localizedDescription } }
        }
    }

    private func build() {
        guard let catalog, let chapter else { return }
        worker?.cancel(); working = true; validated = false
        let sourceName = name, toc = tocCSS, content = contentCSS
        worker = Task { @MainActor in
            defer { working = false }
            let result = await Task.detached(priority: .userInitiated) {
                Result { try WebsiteSourceInference.infer(catalog: catalog, chapter: chapter, name: sourceName, tocCSS: toc, contentCSS: content) }
            }.value
            guard !Task.isCancelled else { return }
            switch result {
            case .success(let value):
                draft = value; name = value.source.bookSourceName
                tocCSS = value.tocSelector; contentCSS = value.contentSelector
                status = "本地样本解析通过，尚未联网验证。"; showPreview = true
            case .failure(let error): status = error.localizedDescription
            }
        }
    }

    private func validate(_ draft: WebsiteSourceDraft) {
        guard draft.source.bookSourceName == name, draft.tocSelector == tocCSS,
              draft.contentSelector == contentCSS else { status = "选择器或名称已变更，请先重新生成。"; return }
        working = true; validated = false
        worker?.cancel()
        worker = Task { @MainActor in
            defer { working = false }
            do {
                if let web = browser.webView {
                    let cookies: [HTTPCookie] = await withCheckedContinuation { continuation in
                        web.configuration.websiteDataStore.httpCookieStore.getAllCookies { continuation.resume(returning: $0) }
                    }
                    await appState.sourceCookieStore.storeWebViewCookies(cookies)
                }
                let detail = try await appState.engine.getBookDetail(source: draft.source, book: draft.example).get()
                let chapters = try await appState.engine.getChapterList(source: draft.source, book: detail, maxPages: 1).get()
                guard let first = chapters.first else { throw WebsiteSourceInference.Failure.noCatalog }
                let body = try await appState.engine.getContent(source: draft.source, chapter: first, maxPages: 1).get()
                guard !Task.isCancelled else { return }
                guard body.paragraphs.joined().count >= 80 else { throw WebsiteSourceInference.Failure.noContent }
                validated = true; status = "真实引擎验证通过：\(chapters.count) 章，首章 \(body.paragraphs.joined().count) 字。请复核后导入。"
            } catch { if !Task.isCancelled { status = "联网验证失败：\(error.localizedDescription)" } }
        }
    }

    private func importDraft(_ draft: WebsiteSourceDraft) {
        guard validated, draft.source.bookSourceName == name, draft.tocSelector == tocCSS,
              draft.contentSelector == contentCSS else { return }
        do { try appState.sourceStore.importSources([draft.source]); dismiss() }
        catch { status = "导入失败：\(error.localizedDescription)" }
    }

    private func json(_ source: BookSource) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(source)).flatMap { String(data: $0, encoding: .utf8) } ?? "JSON 编码失败"
    }
}
