import SwiftUI
import UIKit

/// Lets the reader inspect a source's destination before opening or importing it.
struct SourceLoginDestinationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var copiedLink: String?
    let destination: SourceLoginDestination

    var body: some View {
        NavigationStack {
            List {
                switch destination {
                case .web(let url, let waitsForAndroidResult):
                    Section {
                        Link(destination: url) {
                            Label("打开 \(url.host ?? "来源网页")", systemImage: "safari")
                        }
                    } footer: {
                        if waitsForAndroidResult {
                            Text("来源脚本要求 Android 浏览器返回结果。此处只打开网页，不会自动登录或回填。请使用作者提供的 iOS 登录方式。")
                        } else {
                            Text("确认来源网页后再打开。打开页面不等于已经登录。")
                        }
                    }
                case .publisher(let links):
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
            .navigationTitle("书源网页与更新")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}
