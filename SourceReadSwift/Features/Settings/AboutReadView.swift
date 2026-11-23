import SwiftUI

/// A quiet name page; product guidance and legal documents remain one menu away.
struct AboutReadView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 48) {
                VStack(alignment: .leading, spacing: 16) {
                    PaperBetweenMark(size: 56)
                    Text("纸间").font(.system(size: 40, weight: .bold, design: .serif))
                    Text("INPAGE  /  字里，行间。")
                        .font(.caption.weight(.medium)).tracking(2).foregroundStyle(AppTheme.accent)
                }
                VStack(alignment: .leading, spacing: 16) {
                    Text("纸，是故事停留的地方。\n间，是留给自己的片刻。")
                        .font(.title2.weight(.medium)).lineSpacing(8)
                    Text("我们把这段不必赶路的时间，叫作纸间。")
                        .foregroundStyle(.secondary)
                }
                Rectangle().fill(AppTheme.accent.opacity(0.2)).frame(width: 48, height: 1)
                VStack(alignment: .leading, spacing: 16) {
                    Text("一页之内，山海很远。")
                        .font(.title3.weight(.semibold))
                    Text("读得慢一点，也没有关系。\n一句话可以停留，一本书可以重逢。\n合上时留一枚书签，翻开时接住上一次的自己。")
                        .foregroundStyle(.secondary).lineSpacing(8)
                }
                Text("把世界合上片刻。\n把自己，留在字里行间。")
                    .font(.headline).lineSpacing(8)
                Text(AppVersion.displayString).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: 560, alignment: .leading)
            .padding(.horizontal, 32).padding(.vertical, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .pageBackground()
        .navigationTitle("关于纸间")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    NavigationLink {
                        List { SettingsQQGroupRow() }.navigationTitle("读者交流")
                            .scrollContentBackground(.hidden).pageBackground()
                    } label: { Label("读者 QQ 群", systemImage: "person.2") }
                    NavigationLink { ReadingGuideView() } label: {
                        Label("让阅读按你的习惯来", systemImage: "book")
                    }
                    .accessibilityIdentifier("about.readingGuide")
                    NavigationLink { PrivacyLegalHubView() } label: {
                        Label("隐私、条款与开源许可", systemImage: "shield")
                    }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 44, height: 44)
                }
                .accessibilityLabel("读者交流、阅读指引与条款")
                .accessibilityIdentifier("about.options")
            }
        }
    }
}

private struct ReadingGuideView: View {
    var body: some View {
        List {
            Label("导入本地 TXT、EPUB，或使用自己添加的 Legado 书源", systemImage: "books.vertical")
            Label("调出顺眼的纸色、字号和行距，横翻或纵读都可以", systemImage: "textformat.size")
            Label("用书签、阅读记录和本书搜索，找回读过的句子", systemImage: "bookmark")
        }
        .listRowBackground(AppThemeRowSurface())
        .pageBackground()
        .navigationTitle("让阅读按你的习惯来")
        .navigationBarTitleDisplayMode(.inline)
    }
}
