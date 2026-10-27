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

    private var fields: [SourceLoginField] {
        SourceLoginFieldParser.parse(source.loginUi)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                statusBar
                if fields.isEmpty {
                    pageContent
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
                    if fields.isEmpty {
                        Button("完成") { dismiss() }
                    } else {
                        Button("登录") { submit() }
                            .disabled(busy)
                    }
                }
            }
        }
        .presentationDetents([.large])
        .onAppear {
            if fields.isEmpty, loginTarget?.usedBookSourceFallback == true {
                status = "该书源未配置 loginUrl，已打开书源主页，请登录后点完成"
            } else if !fields.isEmpty {
                status = "请输入 \(source.bookSourceName) 的登录信息"
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
            SourceLoginWebView(url: target.url, cookieStore: cookieStore) { message in
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
                if let action = field.action, let url = URL(string: action) {
                    openURL(url)
                }
            } label: {
                Text(field.name).frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private func binding(for name: String) -> Binding<String> {
        Binding(
            get: { input[name] ?? "" },
            set: { input[name] = $0 }
        )
    }

    private func submit() {
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

    private var loginTarget: SourceLoginURLResolver.Target? {
        SourceLoginURLResolver.resolve(
            loginUrl: source.loginUrl,
            bookSourceUrl: source.bookSourceUrl
        )
    }
}

private struct SourceLoginWebView: UIViewRepresentable {
    let url: URL
    let cookieStore: SourceCookieStore
    let onStatus: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(cookieStore: cookieStore, onStatus: onStatus)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
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
            onStatus("页面已加载，Cookie 已同步")
            Task { @MainActor in
                let cookies: [HTTPCookie] = await withCheckedContinuation { continuation in
                    webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                        continuation.resume(returning: cookies)
                    }
                }
                await cookieStore.storeWebViewCookies(cookies)
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
