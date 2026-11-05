import SwiftUI

/// Searchable source categories retain their groups without a horizontal chip wall.
struct ExploreCategorySelectionSheet: View {
    let categories: [ExploreCategory]
    let selectedID: String?
    let onSelect: (ExploreCategory) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var matches: [ExploreCategory] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return keyword.isEmpty ? categories : categories.filter {
            $0.title.localizedStandardContains(keyword) || ($0.group ?? "").localizedStandardContains(keyword)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if matches.isEmpty {
                    Text("没有匹配的分类，换一个关键词试试。")
                        .foregroundStyle(.secondary)
                }
                ForEach(matches) { category in
                    Button {
                        onSelect(category)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(category.title).foregroundStyle(.primary)
                                if let group = category.group {
                                    Text(group).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if category.id == selectedID { Image(systemName: "checkmark") }
                        }
                        .frame(minHeight: 44)
                    }
                }
            }
            .searchable(text: $query, prompt: "搜索分类或分组")
            .navigationTitle("选择分类")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
            }
        }
        .tint(AppTheme.accent)
    }
}
