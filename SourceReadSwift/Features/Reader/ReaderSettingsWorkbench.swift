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

/// Settings own a local route, never the reader's outer navigation stack.
struct ReaderSettingsWorkbench: View {
    let context: ReaderWorkbenchContext
    private let preview: () -> AnyView
    private let page: (ReaderWorkbenchRoute) -> AnyView
    private let actions: ReaderWorkbenchActions
    @State private var route: ReaderWorkbenchRoute?
    @State private var drag: CGFloat = 0
    @AppStorage("reader.atelierEnabled") private var usesWorkbench = true
    @AppMotion private var motion
    @Environment(\.dynamicTypeSize) private var typeSize

    init(context: ReaderWorkbenchContext, preview: @escaping () -> AnyView,
         page: @escaping (ReaderWorkbenchRoute) -> AnyView, actions: ReaderWorkbenchActions) {
        self.context = context; self.preview = preview; self.page = page; self.actions = actions
        _route = State(initialValue: context.initialRoute)
    }
    var body: some View {
        GeometryReader { proxy in
            let maximum = ReaderSettingsLayoutPolicy.maxPanelHeight(viewportHeight: proxy.size.height, bottomInset: context.bottomInset)
            let height = typeSize.isAccessibilitySize ? maximum : min(maximum, max(proxy.size.height * 0.72, 360))
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    handle
                    header
                    ReaderSettingsContent {
                        if let route {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 24) {
                                    page(route)
                                }.padding(16)
                            }.safeAreaInset(edge: .top, spacing: 0) {
                                if route == .heading && !typeSize.isAccessibilitySize && proxy.size.height >= 600 {
                                    preview().padding(.horizontal, 16).padding(.bottom, 12)
                                }
                            }
                            .id(route)
                        } else {
                            home
                        }
                    }
                    .tint(AppTheme.accent)
                    .transaction { if motion.reducesMotion { $0.disablesAnimations = true } }
                }
                .frame(width: ReaderSettingsLayoutPolicy.maxPanelWidth(viewportWidth: proxy.size.width), height: height)
                .modifier(ReaderChromeSurface(paper: context.paper, ink: context.ink))
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(context.ink.opacity(0.10), lineWidth: 0.6).allowsHitTesting(false) }
                .shadow(color: context.ink.opacity(0.10), radius: 16, y: 8)
                .padding(.bottom, max(context.bottomInset, 8) + 8).offset(y: drag)
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .foregroundStyle(context.ink)
                .environment(\.colorScheme, context.background.isDark ? .dark : .light)
        }.onChange(of: route) { actions.routeChanged($0) }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("reader.settingsWorkbench")
    }
    private var header: some View {
        HStack(spacing: 8) {
            if route != nil {
                Button { route = nil } label: {
                    Image(systemName: "chevron.left").frame(width: 44, height: 44)
                }.accessibilityLabel("返回阅读设置")
                    .accessibilityIdentifier("reader.settings.back")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(route?.title ?? "阅读设置").font(.headline).lineLimit(1)
                Text(context.bookTitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Button(action: actions.close) { Image(systemName: "xmark").frame(width: 44, height: 44) }
                .accessibilityLabel("关闭阅读设置")
                .accessibilityIdentifier("reader.settings.close")
        }.padding(.horizontal, 12).padding(.bottom, 8).buttonStyle(AppPressStyle())
    }
    private var handle: some View {
        Capsule().fill(context.ink.opacity(0.22)).frame(width: 32, height: 4)
            .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 8).onChanged { value in
                if value.translation.height > abs(value.translation.width) { drag = max(value.translation.height, 0) }
            }.onEnded { value in
                if value.translation.height > 100 || value.predictedEndTranslation.height > 180 { actions.close() }
                else { withAnimation(motion.animation(.expansion)) { drag = 0 } }
            })
            .accessibilityHidden(true)
    }
    private var home: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                primaryRow(.typography, index: "字")
                Divider().padding(.leading, 56)
                primaryRow(.appearance, index: "纸")
                Divider().padding(.leading, 56)
                primaryRow(.heading, index: "章")
                Divider().padding(.vertical, 12)
                secondaryRow(.chrome)
                secondaryRow(.assistance)
                secondaryRow(.themes)
                Button("切换经典设置") { usesWorkbench = false }
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(minHeight: 44).frame(maxWidth: .infinity).padding(.top, 8)
            }.padding(16)
        }
    }

    private func primaryRow(_ route: ReaderWorkbenchRoute, index: String) -> some View {
        Button { self.route = route } label: {
            HStack(spacing: 16) {
                Text(index).font(.system(.title2, design: .serif).weight(.medium))
                    .foregroundStyle(AppTheme.accent).frame(width: 40).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(route.title).font(.headline)
                    Text(route.subtitle).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, minHeight: 72, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(AppPressStyle()).accessibilityIdentifier("reader.settings.route." + route.rawValue)
    }

    private func secondaryRow(_ route: ReaderWorkbenchRoute) -> some View {
        Button { self.route = route } label: {
            HStack(spacing: 12) {
                Image(systemName: route.symbol).frame(width: 28).foregroundStyle(AppTheme.accent)
                Text(route.title).font(.subheadline.weight(.medium))
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, minHeight: 48, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(AppPressStyle()).accessibilityIdentifier("reader.settings.route." + route.rawValue)
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
                    .foregroundStyle(context.ink)
                    .modifier(ReaderChromeSurface(paper: context.paper, ink: context.ink))
                    .padding(.bottom, max(context.bottomInset, 8) + 8)
            }.frame(maxWidth: .infinity).environment(\.colorScheme, context.background.isDark ? .dark : .light)
        }
    }
}
