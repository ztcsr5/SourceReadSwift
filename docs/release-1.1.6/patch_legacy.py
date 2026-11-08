from pathlib import Path
R=Path(__file__).resolve().parents[2]
p=R/'SourceReadSwift/App/RootTabView.swift';s=p.read_text(encoding='utf8')
s=s.replace('    @State private var selectedTab = 0','    @State private var selectedTab = 0\n    @State private var legacySearchRequest: UUID?')
s=s.replace('case 1: DiscoverView(viewModel: appState.discoverViewModel)','case 1: DiscoverView(viewModel: appState.discoverViewModel, searchRequestID: legacySearchRequest)')
a=s.index('    private var customTabBar: some View {');b=s.index('    private func tabButton(',a)
s=s[:a]+'''    private var customTabBar: some View {
        LegacyTabBar(selection: $selectedTab) {
            legacySearchRequest = UUID()
            selectedTab = 1
        }
    }

'''+s[b:]
a=s.index('    private func tabButton(');b=s.index('    private func dismissKeyboard()',a);s=s[:a]+s[b:]
p.write_text(s,encoding='utf8')
p=R/'SourceReadSwift/Features/Discover/DiscoverView.swift';s=p.read_text(encoding='utf8')
s=s.replace('    @ObservedObject var viewModel: DiscoverViewModel','    @ObservedObject var viewModel: DiscoverViewModel\n    let searchRequestID: UUID?\n    @FocusState private var searchIsFocused: Bool',1)
s=s.replace('    init(viewModel: DiscoverViewModel? = nil) {','    init(viewModel: DiscoverViewModel? = nil, searchRequestID: UUID? = nil) {\n        self.searchRequestID = searchRequestID',1)
s=s.replace('            .task {\n                viewModel.bind(appState: appState)','''            .onChange(of: searchRequestID) { request in
                if request != nil { selectedTab = .search; searchIsFocused = true }
            }
            .task {
                if searchRequestID != nil {
                    selectedTab = .search
                    await Task.yield()
                    searchIsFocused = true
                }
                viewModel.bind(appState: appState)''',1)
s=s.replace('TextField("搜索书名或作者", text: $viewModel.keyword)','TextField("搜索书名或作者", text: $viewModel.keyword)\n                .focused($searchIsFocused)',1)
p.write_text(s,encoding='utf8')
