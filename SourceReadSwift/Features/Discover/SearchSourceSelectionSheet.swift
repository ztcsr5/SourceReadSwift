import SwiftUI

/// Source rows are built only while this searchable sheet is presented.
struct SearchSourceSelectionSheet: View {
    let sources: [BookSource]
    let selectedURL: String?
    let onSelect: (BookSource?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var matches: [BookSource] {
        Self.matchingSources(sources, query: query)
    }

    static func matchingSources(_ sources: [BookSource], query: String) -> [BookSource] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return keyword.isEmpty ? sources : sources.filter {
            $0.bookSourceName.localizedStandardContains(keyword)
                || $0.bookSourceUrl.localizedStandardContains(keyword)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Button {
                    onSelect(nil)
                    dismiss()
                } label: {
                    HStack {
                        Text("全部已启用书源")
                        Spacer()
                        if selectedURL == nil { Image(systemName: "checkmark") }
                    }
                    .frame(minHeight: 44)
                }
                .accessibilityAddTraits(selectedURL == nil ? .isSelected : [])
                .listRowBackground(AppThemeRowSurface())
                Section("选择一个书源") {
                    if matches.isEmpty {
                        Text("没有匹配的书源，换一个关键词试试。")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(matches) { source in
                        Button {
                            onSelect(source)
                            dismiss()
                        } label: {
                            HStack {
                                Text(source.bookSourceName).foregroundStyle(.primary)
                                Spacer()
                                if source.bookSourceUrl == selectedURL { Image(systemName: "checkmark") }
                            }
                            .frame(minHeight: 44)
                        }
                        .accessibilityAddTraits(source.bookSourceUrl == selectedURL ? .isSelected : [])
                        .listRowBackground(AppThemeRowSurface())
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .pageBackground()
            .searchable(text: $query, prompt: "搜索书源名称或网址")
            .navigationTitle("搜索范围")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
            }
        }
        .tint(AppTheme.accent)
    }
}
