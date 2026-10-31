import SwiftUI
import WebKit

struct SmartWebReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var session = WebReadingSession()
    @AppStorage("web.blockAdvertisements") private var blockAds = true
    @State private var address: String
    @State private var loadedURL: URL?
    @State private var addressError: String?

    init(initialURL: URL? = nil) {
        _address = State(initialValue: initialURL?.absoluteString ?? "https://")
        _loadedURL = State(initialValue: initialURL)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    TextField("网页地址", text: $address)
                        .textInputAutocapitalization(.never).autocorrectionDisabled(true)
                        .keyboardType(.URL).textFieldStyle(.roundedBorder).onSubmit(loadPage)
                    Button("打开", action: loadPage).buttonStyle(.bordered)
                }.padding(12)
                if let loadedURL {
                    // Keep the web view mounted beneath the extracted projection:
                    // returning preserves the current navigation and login state.
                    ReadableWebView(url: loadedURL, session: session, blockAds: blockAds)
                        .overlay {
                            if let article = session.article {
                                ExtractedArticleView(article: article).background(AppTheme.background)
                            }
                        }
                } else {
                    CenterTextEmptyState("打开章节网页后，可提取正文去除网页干扰。")
                }
                if let error = addressError ?? session.errorMessage {
                    Text(error).font(.footnote).foregroundStyle(.red).padding(8)
                }
                HStack {
                    Button { session.webView?.goBack() } label: { Image(systemName: "chevron.left") }.accessibilityLabel("网页后退")
                    Spacer()
                    if session.article != nil {
                        Button("返回网页") { session.article = nil }
                    } else {
                        Button(action: session.extractCurrentPage) {
                            Label(session.isExtracting ? "提取中…" : "提取正文并阅读", systemImage: "doc.text.magnifyingglass")
                        }.disabled(loadedURL == nil || session.isExtracting)
                    }
                    Spacer()
                    Menu {
                        Toggle("拦截常见广告", isOn: $blockAds)
                        Button("刷新网页") { session.webView?.reload() }
                    } label: { Image(systemName: "shield.lefthalf.filled") }.accessibilityLabel("网页内容控制")
                }.buttonStyle(.bordered).padding(12)
            }
            .pageBackground().navigationTitle("网页阅读").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
            .onDisappear { session.cancelExtraction() }
        }
    }

    private func loadPage() {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(url.scheme?.lowercased()) else {
            addressError = "请输入有效的 http/https 地址"; return
        }
        addressError = nil
        session.cancelExtraction()
        session.article = nil
        loadedURL = url
    }
}
