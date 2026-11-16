import SwiftUI
import UIKit

/// Lets the reader inspect a source's destination before opening or importing it.
struct SourceLoginDestinationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var copiedLink: String?
    @State private var status = "正在打开登录页…"
    @State private var finalURL: URL?
    @State private var responseStatusCode = 200
    @State private var responseHeaders: [String: String] = [:]
    @State private var isSaving = false
    @State private var hasCompleted = false
    @State private var hasCancelled = false
    @State private var completionTask: Task<Void, Never>?
    @StateObject private var readingSession = WebReadingSession()
    @StateObject private var cookieScope = SourceLoginCookieScope()
    let destination: SourceLoginDestination
    let cookieStore: SourceCookieStore
    var browserTitle: String = "书源登录"
    var onCompleted: (SourceResponse) -> Void = { _ in }
    var onCancelled: () -> Void = {}

    var body: some View {
        NavigationStack {
            Group {
                switch destination {
                case .web(let url, _):
                    VStack(spacing: 0) {
                        Text(status).font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                            .accessibilityIdentifier("source-browser-status")
                        SourceLoginWebView(url: url, cookieStore: cookieStore, readingSession: readingSession,
                            cookieScope: cookieScope,
                            onPageLoaded: { finalURL = $0 },
                            onResponse: { responseStatusCode = $0; responseHeaders = $1 }) { status = $0 }
                            .allowsHitTesting(!isSaving)
                    }
                case .publisher(let links):
                    List {
                        Section {
                            ForEach(links) { link in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(link.title).font(.headline)
                                    if let host = link.url.host {
                                        Text(host).font(.caption).foregroundStyle(.secondary)
                                    }
                                    if link.isPageReference {
                                        Link("打开发布页", destination: link.url)
                                    } else {
                                        Button(copiedLink == link.id ? "已复制导入链接" : "复制导入链接") {
                                            UIPasteboard.general.string = link.url.absoluteString
                                            copiedLink = link.id
                                        }
                                        .accessibilityIdentifier("source-copy-publisher-link")
                                    }
                                }
                            }
                        } footer: {
                            Text("只导入你确认来自作者的版本。复制地址后，到「书源管理 → 导入书源」，将它粘贴到 URL 栏，再点「从 URL 导入」。此页只提供地址，不检查最新版本、不自动导入，也不执行网页脚本。")
                        }
                    }
                }
            }
            .navigationTitle(isWebDestination ? browserTitle : "书源网页与更新")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { cancelBrowser(); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isWebDestination {
                        Button(isSaving ? "正在同步…" : "完成") { finishBrowserLogin() }
                            .disabled(isSaving || finalURL == nil)
                            .accessibilityIdentifier("source-browser-complete")
                    }
                }
            }
        }
        .onDisappear {
            readingSession.cancelExtraction()
            if !hasCompleted { cancelBrowser() }
        }
    }

    private var isWebDestination: Bool {
        if case .web = destination { return true }
        return false
    }

    private func finishBrowserLogin() {
        guard !isSaving, let webView = readingSession.webView,
              let finalURL = webView.url, !webView.isLoading,
              SourceLoginBrowserAction.browserPageURL(finalURL.absoluteString) != nil else { return }
        isSaving = true
        status = "正在同步登录信息…"
        completionTask = Task { @MainActor in
            do {
                let response = try await SourceBrowserPageCapture.capture(from: webView,
                    statusCode: responseStatusCode, headers: responseHeaders)
                _ = await SourceLoginBrowserCookies.synchronize(from: webView, into: cookieStore, scope: cookieScope)
                guard !Task.isCancelled, !hasCancelled else { return }
                guard webView.url == response.url, !webView.isLoading else { throw SourceBrowserPageCapture.CaptureError.pageChanged }
                hasCompleted = true
                onCompleted(response)
                dismiss()
            } catch {
                guard !Task.isCancelled, !hasCancelled else { return }
                isSaving = false
                status = error.localizedDescription
            }
        }
    }

    private func cancelBrowser() {
        guard !hasCompleted, !hasCancelled else { return }
        hasCancelled = true
        completionTask?.cancel()
        onCancelled()
    }
}
