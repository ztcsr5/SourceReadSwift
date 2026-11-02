import SwiftUI

enum ReaderWorkbenchRoute: String, CaseIterable, Hashable {
    case themes, typography, appearance, heading, chrome, assistance
    var title: String {
        switch self { case .themes: return "装帧方案"; case .typography: return "字体与排版"; case .appearance: return "纸张与翻页"
        case .heading: return "章节扉页"; case .chrome: return "页眉与菜单"; case .assistance: return "阅读辅助" }
    }
    var symbol: String {
        switch self { case .themes: return "books.vertical"; case .typography: return "textformat"
        case .appearance: return "rectangle.on.rectangle"; case .heading: return "leaf"
        case .chrome: return "rectangle.topthird.inset.filled"; case .assistance: return "slider.horizontal.3" }
    }
    var subtitle: String {
        switch self { case .themes: return "保存属于你的整套阅读装帧"; case .typography: return "字体、字号、行距与留白"
        case .appearance: return "纸面、壁纸、亮度与翻页方式"; case .heading: return "章首装饰、标题构图与字阶"
        case .chrome: return "页眉页脚、安全区与菜单纸面"; case .assistance: return "朗读、选择、预加载与点击区域" }
    }
}

struct ReaderWorkbenchContext {
    let bookTitle: String
    let background: ReaderBackground
    let bottomInset: CGFloat
    var initialRoute: ReaderWorkbenchRoute? = nil
    var menuOpacity = 0.97
    var usesWallpaper = false
    var paper: Color { background.color(isNight: background.isDark) }
    var ink: Color { background.textColor(isNight: background.isDark) }
}

struct ReaderWorkbenchActions {
    let close: () -> Void
    var routeChanged: (ReaderWorkbenchRoute?) -> Void = { _ in }
}

/// One persistent sheet-like container; native navigation owns interactive child-page returns.
struct ReaderSettingsWorkbench: View {
    let context: ReaderWorkbenchContext
    private let preview: () -> AnyView
    private let page: (ReaderWorkbenchRoute) -> AnyView
    private let actions: ReaderWorkbenchActions
    @State private var path: [ReaderWorkbenchRoute]
    @State private var drag: CGFloat = 0
    @AppStorage("reader.atelierEnabled") private var usesWorkbench = true
    @AppMotion private var motion
    @Environment(\.dynamicTypeSize) private var typeSize

    init(context: ReaderWorkbenchContext, preview: @escaping () -> AnyView,
         page: @escaping (ReaderWorkbenchRoute) -> AnyView, actions: ReaderWorkbenchActions) {
        self.context = context; self.preview = preview; self.page = page; self.actions = actions
        _path = State(initialValue: context.initialRoute.map { [$0] } ?? [])
    }
    var body: some View {
        GeometryReader { proxy in
            let height = ReaderSettingsLayoutPolicy.maxPanelHeight(viewportHeight: proxy.size.height, bottomInset: context.bottomInset)
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    handle
                    NavigationStack(path: $path) {
                        home
                            .navigationTitle("阅读工坊").navigationBarTitleDisplayMode(.inline)
                            .navigationDestination(for: ReaderWorkbenchRoute.self) { route in
                                ReaderSettingsContent {
                                    ScrollView {
                                        VStack(alignment: .leading, spacing: 24) {
                                            page(route)
                                        }.padding(16)
                                    }.safeAreaInset(edge: .top, spacing: 0) {
                                        if !typeSize.isAccessibilitySize && proxy.size.height >= 600 {
                                            preview().padding(.horizontal, 16).padding(.bottom, 12)
                                        }
                                    }.navigationTitle(route.title).navigationBarTitleDisplayMode(.inline)
                                        .background { surface }
                                        .toolbar { closeToolbar }
                                }
                            }
                            .toolbar { closeToolbar }
                    }
                    .toolbarBackground(context.paper, for: .navigationBar)
                    .toolbarBackground(.visible, for: .navigationBar)
                    .toolbarColorScheme(context.background.isDark ? .dark : .light, for: .navigationBar)
                    .tint(AppTheme.accent)
                    .transaction { if motion.reducesMotion { $0.disablesAnimations = true } }
                }
                .frame(width: ReaderSettingsLayoutPolicy.maxPanelWidth(viewportWidth: proxy.size.width), height: height)
                .background { surface }
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(context.ink.opacity(0.10), lineWidth: 0.6).allowsHitTesting(false) }
                .shadow(color: context.ink.opacity(0.10), radius: 16, y: 8)
                .padding(.bottom, max(context.bottomInset, 8) + 8).offset(y: drag)
            }.foregroundStyle(context.ink)
                .environment(\.colorScheme, context.background.isDark ? .dark : .light)
        }.onChange(of: path) { actions.routeChanged($0.last) }
            .accessibilityIdentifier("reader.settingsWorkbench")
    }
    private var closeToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button(action: actions.close) { Image(systemName: "xmark").frame(width: 44, height: 44) }
                .accessibilityLabel("关闭阅读设置")
        }
    }
    private var handle: some View {
        Capsule().fill(context.ink.opacity(0.22)).frame(width: 32, height: 4)
            .frame(maxWidth: .infinity, minHeight: 32).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 8).onChanged { value in
                if value.translation.height > abs(value.translation.width) { drag = max(value.translation.height, 0) }
            }.onEnded { value in
                if value.translation.height > 100 || value.predictedEndTranslation.height > 180 { actions.close() }
                else { withAnimation(motion.animation(.expansion)) { drag = 0 } }
            })
            .accessibilityHidden(true)
    }
    private var surface: some View {
        ZStack {
            context.paper
            if context.usesWallpaper {
                if context.background == .custom, let image = ReaderCustomWallpaperStore.cachedWallpaper {
                    ReaderWallpaperView(image: image, fillMode: ReaderCustomWallpaperStore.adjustment.fillMode,
                        adjustment: ReaderCustomWallpaperStore.adjustment)
                        .opacity(1 - min(max(context.menuOpacity, 0.85), 1))
                } else {
                    ReaderPaperTextureView(background: context.background, night: context.background.isDark)
                        .opacity(1 - min(max(context.menuOpacity, 0.85), 1))
                }
            }
        }.allowsHitTesting(false)
            .animation(motion.animation(.background), value: context.background)
    }
    private var home: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(context.bookTitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Text("调好书页，再回到故事里。") .font(.title3.weight(.semibold))
                }
                NavigationLink(value: ReaderWorkbenchRoute.themes) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack { Label("你的阅读装帧", systemImage: "books.vertical").font(.caption); Spacer(); Image(systemName: "arrow.up.right") }
                        Text("让纸张、字与留白\n成为同一种气质。") .font(.title3.weight(.semibold))
                        ReaderChapterMotif(decoration: .folio).foregroundStyle(AppTheme.accent)
                        Text("查看与保存整套方案").font(.caption.weight(.semibold))
                    }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
                        .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(AppTheme.accent.opacity(0.18), lineWidth: 0.8) }
                }.buttonStyle(AppPressStyle())
                LazyVGrid(columns: typeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(Array(ReaderWorkbenchRoute.allCases.filter { $0 != .themes }.enumerated()), id: \.element) { index, route in
                        NavigationLink(value: route) {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack { Text(String(format: "%02d", index + 1)).font(.caption.monospaced()); Spacer(); Image(systemName: "arrow.up.right").font(.caption) }
                                    .foregroundStyle(.secondary)
                                Image(systemName: route.symbol).font(.title2).foregroundStyle(AppTheme.accent).frame(height: 32)
                                Text(route.title).font(.headline)
                                Text(route.subtitle).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }.padding(16).frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
                                .background(context.ink.opacity(0.035), in: RoundedRectangle(cornerRadius: 16))
                                .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(context.ink.opacity(0.08), lineWidth: 0.6) }
                        }.buttonStyle(AppPressStyle())
                    }
                }
                Button("切换经典设置") { usesWorkbench = false }
                    .font(.caption).frame(minHeight: 44).frame(maxWidth: .infinity)
            }.padding(16)
        }.background { surface }
    }
}

/// A reversible classic shell, retaining the same stack-bounded production pages.
struct ReaderClassicSettingsPanel: View {
    let context: ReaderWorkbenchContext
    @Binding var selection: Int
    let page: (Int) -> AnyView
    let close: () -> Void
    @AppStorage("reader.atelierEnabled") private var usesWorkbench = true
    var body: some View {
        GeometryReader { proxy in
            VStack {
                Spacer(minLength: 0)
                VStack(spacing: 16) {
                    HStack {
                        Text("阅读设置").font(.headline); Spacer()
                        Button(action: close) { Image(systemName: "xmark").frame(width: 44, height: 44) }.accessibilityLabel("关闭阅读设置")
                    }
                    Picker("设置分类", selection: $selection) {
                        Text("外观").tag(0); Text("排版").tag(1); Text("高级").tag(2)
                    }.pickerStyle(.segmented)
                    ScrollView { page(selection).padding(.bottom, 16) }
                    Button("启用阅读工坊") { usesWorkbench = true }.font(.caption).frame(minHeight: 44)
                }.padding(16)
                    .frame(width: ReaderSettingsLayoutPolicy.maxPanelWidth(viewportWidth: proxy.size.width),
                           height: ReaderSettingsLayoutPolicy.maxPanelHeight(viewportHeight: proxy.size.height, bottomInset: context.bottomInset))
                    .foregroundStyle(context.ink).background(context.paper, in: RoundedRectangle(cornerRadius: 18))
                    .padding(.bottom, max(context.bottomInset, 8) + 8)
            }.frame(maxWidth: .infinity).environment(\.colorScheme, context.background.isDark ? .dark : .light)
        }
    }
}
