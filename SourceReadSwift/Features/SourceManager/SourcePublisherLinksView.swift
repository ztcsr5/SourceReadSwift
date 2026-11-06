import SwiftUI

struct SourcePublisherLinksView: View {
    let page: SourcePublisherPage
    let isLoading: Bool
    let onSelect: (SourcePublisherLink) -> Void

    var body: some View {
        List {
            Section {
                Text("该页面包含以下链接。选择后才会下载；导入书源后可在列表中查看和编辑规则。")
                    .font(.footnote).foregroundStyle(.secondary)
                Text(page.url.absoluteString).font(.caption).textSelection(.enabled)
            }
            Section("选择链接（\(page.links.count)）") {
                ForEach(page.links) { link in
                    Button { onSelect(link) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Label(link.title, systemImage: link.isPageReference ? "list.bullet.rectangle" : "doc.badge.arrow.up")
                            Text(link.url.absoluteString).font(.caption).foregroundStyle(.secondary)
                                .lineLimit(3)
                            if link.isPageReference { Text("查看返回内容，不执行网页脚本").font(.caption2).foregroundStyle(.secondary) }
                        }.frame(minHeight: 44, alignment: .leading)
                    }
                    .disabled(isLoading)
                }
            }
        }
    }
}
