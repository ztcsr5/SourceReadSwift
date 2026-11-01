import SwiftUI

struct SourceGroupAssignmentRequest: Identifiable {
    let id = UUID()
    let sourceIDs: Set<String>
}

struct SourceGroupAssignmentView: View {
    @ObservedObject var store: SourceStore
    let sourceIDs: Set<String>
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("将 \(sourceIDs.count) 个书源移入分组") {
                    Button("未分组") { assign("") }
                    ForEach(store.organization.allGroups(in: store.sources), id: \.self) { group in
                        Button(group) { assign(group) }
                    }
                }
                .listRowBackground(AppThemeRowSurface())
                Section("新建分组并移入") {
                    TextField("分组名称", text: $newName)
                    Button("保存") { assign(newName) }
                        .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .listRowBackground(AppThemeRowSurface())
                if let error = store.lastError { Text(error).foregroundStyle(.red) }
            }
            .pageBackground()
            .navigationTitle("设置分组")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
    }

    private func assign(_ group: String) {
        store.setGroup(group, for: sourceIDs)
        if store.lastError == nil { dismiss() }
    }
}

struct SourceOrganizationView: View {
    @ObservedObject var store: SourceStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selectedGroup: String?
    @State private var groupAssignment: SourceGroupAssignmentRequest?
    @State private var editingGroup: String?
    @State private var groupName = ""
    @State private var showGroupEditor = false
    @State private var deletingGroup: String?

    var body: some View {
        let organization = store.organization
        let groups = organization.allGroups(in: store.sources)
        let visible = organization.ordered(store.sources).filter { source in
            let inGroup = selectedGroup.map { group in
                group.isEmpty ? organization.groups(for: source).isEmpty : organization.groups(for: source).contains(group)
            } ?? true
            let key = query.trimmingCharacters(in: .whitespacesAndNewlines)
            return inGroup && (key.isEmpty || source.bookSourceName.localizedCaseInsensitiveContains(key)
                || source.bookSourceUrl.localizedCaseInsensitiveContains(key))
        }
        return NavigationStack {
            List {
                Section {
                    Picker("排序方式", selection: Binding(get: { store.organization.sort }, set: { sort in
                        store.updateOrganization { $0.sort = sort }
                    })) {
                        ForEach(SourceLibrarySort.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("分组筛选", selection: $selectedGroup) {
                        Text("全部分组").tag(String?.none)
                        Text("未分组").tag(String?.some(""))
                        ForEach(groups, id: \.self) { Text($0).tag(String?.some($0)) }
                    }
                    TextField("搜索要调整的书源", text: $query)
                        .textInputAutocapitalization(.never)
                } footer: {
                    Text("置顶与置底始终优先；自定义顺序下可拖动同一区域的书源。筛选后排序不会改变其他分组。")
                }
                .listRowBackground(AppThemeRowSurface())
                Section {
                    DisclosureGroup("管理分组") {
                    Button {
                        editingGroup = nil; groupName = ""; showGroupEditor = true
                    } label: { Label("新建分组", systemImage: "folder.badge.plus") }
                    ForEach(groups, id: \.self) { group in
                        HStack {
                            Text(group)
                            Spacer()
                            Menu {
                                Button("重命名") { editingGroup = group; groupName = group; showGroupEditor = true }
                                Button("删除分组", role: .destructive) { deletingGroup = group }
                            } label: {
                                Image(systemName: "ellipsis.circle").frame(minWidth: 44, minHeight: 44)
                            }
                            .accessibilityLabel("管理分组 \(group)")
                        }
                    }
                    }
                }
                .listRowBackground(AppThemeRowSurface())
                ForEach(SourcePlacement.allCases) { placement in
                    let section = visible.filter { organization.placement(for: $0) == placement }
                    if !section.isEmpty {
                        Section(placement.title + "（\(section.count)）") {
                            ForEach(section) { source in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(source.bookSourceName).font(.body)
                                    Text(organization.groups(for: source).joined(separator: " · ").nilIfEmpty ?? "未分组")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                .contextMenu {
                                    ForEach(SourcePlacement.allCases) { destination in
                                        Button(destination == .normal ? "取消置顶 / 置底" : destination.title) {
                                            store.setPlacement(destination, for: [source.id])
                                        }
                                    }
                                    Button("设置分组") { groupAssignment = SourceGroupAssignmentRequest(sourceIDs: [source.id]) }
                                }
                            }
                            .onMove { offsets, destination in
                                var ids = section.map(\.id)
                                ids.move(fromOffsets: offsets, toOffset: destination)
                                store.reorderSources(ids)
                            }
                            .moveDisabled(organization.sort != .custom)
                        }
                        .listRowBackground(AppThemeRowSurface())
                    }
                }
                if let error = store.lastError { Text(error).foregroundStyle(.red) }
            }
            .environment(\.editMode, .constant(.active))
            .pageBackground()
            .navigationTitle("排序与分组")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .sheet(item: $groupAssignment) { request in
                SourceGroupAssignmentView(store: store, sourceIDs: request.sourceIDs)
            }
            .alert(editingGroup == nil ? "新建分组" : "重命名分组", isPresented: $showGroupEditor) {
                TextField("名称", text: $groupName)
                Button("取消", role: .cancel) { }
                Button("保存") { saveGroup() }
                    .disabled(SourceOrganization.splitGroups(groupName).count != 1)
            }
            .confirmationDialog("删除分组不会删除书源", isPresented: Binding(
                get: { deletingGroup != nil }, set: { if !$0 { deletingGroup = nil } }
            ), titleVisibility: .visible) {
                Button("删除分组", role: .destructive) {
                    guard let group = deletingGroup else { return }
                    store.updateOrganization { $0.deleteGroup(group, sources: store.sources) }
                    if selectedGroup == group { selectedGroup = nil }
                    deletingGroup = nil
                }
            }
        }
    }

    private func saveGroup() {
        let name = SourceOrganization.splitGroups(groupName).joined(separator: ",")
        guard !name.isEmpty else { return }
        store.updateOrganization { preferences in
            if let old = editingGroup { preferences.renameGroup(old, to: name, sources: store.sources) }
            else { preferences.namedGroups = Array(Set(preferences.namedGroups + SourceOrganization.splitGroups(name))).sorted() }
        }
        if let old = editingGroup, selectedGroup == old { selectedGroup = name }
    }
}
