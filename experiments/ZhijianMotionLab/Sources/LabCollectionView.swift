import SwiftUI

struct LabCollectionView: View {
    @EnvironmentObject private var library: LabLibrary
    @State private var pendingDeletion: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("片刻，也值得珍藏。").font(.caption).tracking(2).foregroundStyle(LabPalette.accent)
                Text("我的书笺").font(.system(.largeTitle, design: .serif).weight(.semibold))
                if library.snapshot.quotes.isEmpty {
                    VStack(spacing: 18) {
                        Image(systemName: "ticket").font(.system(size: 48, weight: .ultraLight))
                        Text("故事还没有留下书笺").font(.headline)
                        Text("打开首页的任意故事，在试读中保存喜欢的段落。这里不预置你的阅读记录。")
                            .font(.subheadline).multilineTextAlignment(.center).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).padding(.vertical, 70)
                } else {
                    ForEach(library.snapshot.quotes) { quote in
                        if let book = library.books.first(where: { $0.id == quote.bookID }) {
                            VStack(alignment: .trailing, spacing: 8) {
                                VStack(alignment: .leading, spacing: 12) {
                                    ReadingTicket(book: book).frame(height: 130)
                                    Text(quote.text).font(.subheadline).lineSpacing(5)
                                }
                                .accessibilityIdentifier("quote.saved.\(book.id)")
                                Button("删除书笺", role: .destructive) { pendingDeletion = quote.id }
                                    .font(.caption).frame(minHeight: 44)
                            }
                        }
                    }
                }
            }.padding(24).padding(.top, 20).padding(.bottom, 100)
        }
        .background(LabPalette.paper).foregroundStyle(LabPalette.ink)
        .confirmationDialog("删除这张书笺？", isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })) {
            Button("删除书笺", role: .destructive) { if let pendingDeletion { library.deleteQuote(pendingDeletion) }; pendingDeletion = nil }
            Button("保留", role: .cancel) { pendingDeletion = nil }
        }
        .preferredColorScheme(.light)
    }
}

struct LabSettingsView: View {
    @EnvironmentObject private var library: LabLibrary
    let onReplay: () -> Void
    @State private var showsReset = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    LabMark().scaleEffect(0.6).frame(width: 54, height: 60).foregroundStyle(LabPalette.accent)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("纸间 · 动效实验").font(.headline)
                        Text("PROLOGUE / 0.1.0").font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 12)
                Text("一座故事的入口。探索可自由滑动的景深书海、藏书票、阅读进度、格式轨道与大封面；不覆盖正式纸间。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section("视觉偏好") {
                Toggle("减少装饰性动画", isOn: $library.minimizesMotion)
                Toggle("首页封面沉浸背景", isOn: $library.usesImmersiveBackground)
                Text("系统「减少动态效果」同时生效。关闭沉浸背景会真正移除海报绘制层，保留深色可读底面。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("重播启动序章", action: onReplay)
            }
            Section("本地演示记录") {
                LabeledContent("书笺", value: "\(library.snapshot.quotes.count) 张")
                LabeledContent("记录过位置", value: "\(library.snapshot.positions.count) 本")
                Button("清空实验记录", role: .destructive) { showsReset = true }
                if let message = library.persistenceMessage { Text(message).font(.caption) }
            }
            Section("封面来源") {
                Link("查看 Open Library", destination: URL(string: "https://openlibrary.org")!)
                Text("三体 ISBN 9787536692930，其余为所选英文版本；完整版本来源记录随源码提供。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("边界") {
                Text("封面来自 Open Library 的指定版本；内容仅供私人 UI 测试。试读文字由实验自行编写，不是原书正文；引导图表是样式示例，不冒充你的阅读统计。正式纸间和书源没有改动。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("实验设置").tint(LabPalette.accent)
        .confirmationDialog("清空本测试 App 的全部书笺与位置？", isPresented: $showsReset) {
            Button("清空实验记录", role: .destructive) { library.reset() }
        } message: { Text("不会访问或修改正式纸间的数据。") }
        .preferredColorScheme(.light)
    }
}
