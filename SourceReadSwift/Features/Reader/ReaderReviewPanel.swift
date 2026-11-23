import SwiftUI

struct ReaderReviewSelection: Identifiable {
    let id = UUID()
    let title: String
    let links: [ReaderSourceReview]
}

struct ReaderReviewStyleSettings: View {
    @AppStorage("reader.reviews.enabled") private var enabled = false
    @AppStorage("reader.reviews.web") private var web = false
    @AppStorage("reader.reviews.bubble") private var compact = false
    @AppStorage("reader.reviews.tint") private var tint = ""
    @AppStorage("reader.reviews.glass") private var glass = 0.35
    @AppStorage("reader.reviews.opacity") private var cardOpacity = 0.08
    @AppStorage("reader.reviews.radius") private var radius = 12.0

    var body: some View {
        Form {
            Toggle("显示段评与章评", isOn: $enabled)
            if enabled {
                Section("显示方式") {
                    Picker("评论面板", selection: $web) {
                        Text("纸间卡片").tag(false); Text("书源原网页").tag(true)
                    }.pickerStyle(.segmented)
                    Picker("气泡", selection: $compact) {
                        Text("文字与数量").tag(false); Text("精简图标").tag(true)
                    }
                    Toggle("跟随主题色", isOn: Binding(get: { tint.isEmpty }, set: { tint = $0 ? "" : (AppTheme.hex(AppTheme.accent) ?? "526D75") }))
                    if !tint.isEmpty {
                        ColorPicker("气泡颜色", selection: Binding(get: { Color(hex: ReaderHighlightRule.parseHexUInt32(tint) ?? 0x526D75) },
                            set: { tint = AppTheme.hex($0) ?? tint }), supportsOpacity: false)
                    }
                }
                if !web {
                    Section("原生卡片") {
                        LabeledContent("玻璃浓度", value: glass.formatted(.percent.precision(.fractionLength(0))))
                        Slider(value: $glass, in: 0...1).accessibilityLabel("玻璃浓度")
                        LabeledContent("卡片不透明度", value: cardOpacity.formatted(.percent.precision(.fractionLength(0))))
                        Slider(value: $cardOpacity, in: 0...1).accessibilityLabel("卡片不透明度")
                        LabeledContent("圆角", value: "\(Int(radius)) pt")
                        Slider(value: $radius, in: 0...24, step: 1).accessibilityLabel("卡片圆角")
                    }
                    Section("样式预览") { ReaderReviewCard(comment: .init(author: "纸间 · 示例", text: "读到这句话，我又翻回了上一页。", likes: nil)) }
                }
            }
        }.navigationTitle("段评与互动样式").navigationBarTitleDisplayMode(.inline)
    }
}

struct ReaderReviewPanel: View {
    let selection: ReaderReviewSelection
    let cookies: SourceCookieStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Group {
                if selection.links.count == 1, let link = selection.links.first { ReaderReviewDetail(link: link, cookies: cookies) }
                else {
                    List(Array(selection.links.enumerated()), id: \.offset) { _, link in
                        NavigationLink { ReaderReviewDetail(link: link, cookies: cookies) } label: {
                            Label(link.isChapter ? link.label : "第 \(link.paragraph + 1) 段 · \(link.label)", systemImage: "text.bubble")
                        }
                    }
                }
            }.navigationTitle(selection.title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }.presentationDetents([.medium, .large])
    }
}

private struct ReaderReviewCard: View {
    let comment: ReaderReviewComment
    @AppStorage("reader.reviews.glass") private var glass = 0.35
    @AppStorage("reader.reviews.opacity") private var cardOpacity = 0.08
    @AppStorage("reader.reviews.radius") private var radius = 12.0
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let author = comment.author { Text(author).font(.subheadline.weight(.semibold)) }
            Text(comment.text).textSelection(.enabled)
            if let likes = comment.likes { Label(String(likes), systemImage: "hand.thumbsup").font(.caption).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
            .background(Color(uiColor: .secondarySystemBackground).opacity(min(max(cardOpacity, 0), 1)), in: RoundedRectangle(cornerRadius: radius))
            .background { RoundedRectangle(cornerRadius: radius).fill(.thinMaterial).opacity(min(max(glass, 0), 1)) }
    }
}

private struct ReaderReviewDetail: View {
    let link: ReaderSourceReview
    let cookies: SourceCookieStore
    @AppStorage("reader.reviews.web") private var prefersWebsite = false
    @State private var result: ReaderReviewResponse?
    @State private var openWebsite = false
    @State private var retry = 0
    var body: some View {
        Group {
            if prefersWebsite || openWebsite { ReaderReviewWebsite(url: link.url, cookies: cookies) }
            else if let result {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        switch result {
                        case .comments(let rows):
                            if rows.isEmpty { Text("这里还没有评论。") }
                            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in ReaderReviewCard(comment: row) }
                        case .rejected(let reason):
                            Text(reason)
                            Button("重试") { self.result = nil; retry += 1 }
                        case .website: Text("这个书源提供的是评论网页。")
                        }
                        Button { openWebsite = true } label: { Label("查看书源原网页", systemImage: "safari") }
                    }.padding()
                }
            } else { ProgressView("正在读取评论") }
        }.task(id: retry) {
            guard !prefersWebsite, !openWebsite else { return }
            let response = await Self.fetch(link.url, cookies: cookies)
            if !Task.isCancelled { result = response }
        }
    }

    private static func fetch(_ url: URL, cookies: SourceCookieStore) async -> ReaderReviewResponse {
        guard ReaderSourceReview.webURL(url.absoluteString) != nil else { return .rejected("不是可打开的评论地址。") }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(await cookies.cookieHeader(for: url), forHTTPHeaderField: "Cookie")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration, delegate: SourceRedirectSessionDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else { return .rejected("没有收到 HTTP 响应。") }
            if (300..<400).contains(http.statusCode) { return .website }
            guard (200..<300).contains(http.statusCode) else { return .rejected("书源返回 HTTP \(http.statusCode)。") }
            if http.mimeType?.lowercased() == "text/html" { return .website }
            let limit = 2 * 1024 * 1024
            guard response.expectedContentLength <= limit else { return .rejected("评论页过大，请查看原网页。") }
            var body = Data()
            for try await byte in bytes {
                guard body.count < limit else { return .rejected("评论页过大，请查看原网页。") }
                body.append(byte)
            }
            return ReaderReviewResponse.decode(body)
        } catch { return .rejected("评论请求未完成，请重试或查看原网页。") }
    }
}

private struct ReaderReviewWebsite: View {
    let url: URL
    let cookies: SourceCookieStore
    @StateObject private var session = WebReadingSession()
    @StateObject private var scope = SourceLoginCookieScope()
    @State private var failure: String?
    @State private var attempt = 0
    var body: some View {
        VStack(spacing: 0) {
            if let failure {
                HStack { Text(failure).font(.footnote); Spacer(); Button("重试") { self.failure = nil; attempt += 1 } }.padding()
            }
            SourceLoginWebView(url: url, cookieStore: cookies, readingSession: session, cookieScope: scope,
                onResponse: { status, _ in failure = status >= 400 ? "书源返回 HTTP \(status)。" : nil },
                onFailure: { failure = $0.localizedDescription }, onStatus: { _ in }).id(attempt)
        }
    }
}
