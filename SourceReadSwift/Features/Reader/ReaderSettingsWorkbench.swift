import SwiftUI

enum ReaderWorkbenchRoute: String, CaseIterable, Hashable {
    case themes, typography, appearance, heading, chrome, assistance

    var title: String {
        switch self {
        case .themes: return "氛围主题"
        case .typography: return "排版与字体"
        case .appearance: return "背景与墨色"
        case .heading: return "标题与装帧"
        case .chrome: return "页眉页脚"
        case .assistance: return "交互与更多"
        }
    }

    var shortTitle: String {
        switch self {
        case .themes: return "主题"
        case .typography: return "大小"
        case .appearance: return "配色"
        case .heading: return "格式"
        case .chrome: return "页眉"
        case .assistance: return "更多设置"
        }
    }

    var subtitle: String {
        switch self {
        case .themes: return "氛围预设"
        case .typography: return "排版设置"
        case .appearance: return "背景墨色"
        case .heading: return "标题样式"
        case .chrome: return "页眉页脚"
        case .assistance: return "交互辅助"
        }
    }

    var systemImage: String {
        switch self {
        case .themes: return "sparkles.rectangle.stack"
        case .typography: return "textformat.size"
        case .appearance: return "paintpalette"
        case .heading: return "doc.richtext"
        case .chrome: return "rectangle.topthird.inset.filled"
        case .assistance: return "ellipsis.circle"
        }
    }
}

struct ReaderWorkbenchContext {
    let bookTitle: String
    let background: ReaderBackground
    let bottomInset: CGFloat
    var initialRoute: ReaderWorkbenchRoute? = nil
    var menuOpacity = 0.97
    var usesWallpaper = false
    var isNightOverride: Bool? = nil
    var customAccentColor: Color? = nil
    var isSpeechActive: Bool = false
    var isAutoScrollActive: Bool = false

    var isNight: Bool { isNightOverride ?? background.isDark }
    var paper: Color { background.color(isNight: isNight) }
    var ink: Color { background.resolvedTextColor(isNight: isNight) }
    var accent: Color {
        customAccentColor ?? Color(hex: background.recommendedAccentHex)
    }
}

struct ReaderWorkbenchActions {
    let close: () -> Void
    var routeChanged: (ReaderWorkbenchRoute?) -> Void = { _ in }
    var openWallpaperEditor: (() -> Void)? = nil
    var toggleSpeech: (() -> Void)? = nil
    var toggleAutoScroll: (() -> Void)? = nil
}

struct ReaderSettingsWorkbench: View {
    let context: ReaderWorkbenchContext
    private let preview: () -> AnyView
    private let page: (ReaderWorkbenchRoute) -> AnyView
    private let actions: ReaderWorkbenchActions
    @State private var route: ReaderWorkbenchRoute?
    @State private var showingQuickFonts = false
    @Namespace private var morphNamespace

    @AppStorage("reader.fontSize") private var fontSize = ReaderTypographyDefaults.fontSize
    @AppStorage("reader.fontFamily") private var fontFamilyRaw = ReaderFontFamily.system.rawValue
    @AppStorage("reader.background") private var backgroundRaw = ReaderBackground.white.rawValue
    @AppStorage("reader.mode") private var modeRaw = ReaderMode.scroll.rawValue

    init(
        context: ReaderWorkbenchContext,
        preview: @escaping () -> AnyView,
        page: @escaping (ReaderWorkbenchRoute) -> AnyView,
        actions: ReaderWorkbenchActions
    ) {
        self.context = context
        self.preview = preview
        self.page = page
        self.actions = actions
        _route = State(initialValue: context.initialRoute)
    }

    var body: some View {
        GeometryReader { proxy in
            let maxExpanded = ReaderSettingsLayoutPolicy.maxPanelHeight(
                viewportHeight: proxy.size.height,
                bottomInset: context.bottomInset
            )
            let isCompactHome = route == nil && !showingQuickFonts
            let targetHeight = isCompactHome
                ? min(maxExpanded, max(proxy.size.height * 0.49, 360))
                : maxExpanded
            let width = ReaderSettingsLayoutPolicy.maxPanelWidth(viewportWidth: proxy.size.width)

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                panelBody(targetHeight: targetHeight, isCompactHome: isCompactHome)
                    .frame(width: width)
                    .frame(maxHeight: targetHeight)
                    .padding(.bottom, max(context.bottomInset, 12))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reader.settingsWorkbench")
    }

    private func panelBody(targetHeight: CGFloat, isCompactHome: Bool) -> some View {
        VStack(spacing: 0) {
            panelHeader(isCompactHome: isCompactHome)
            if showingQuickFonts {
                quickFontSelector
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .trailing)),
                        removal: .opacity
                    ))
            } else if let route {
                subpageView(for: route)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .trailing)),
                        removal: .opacity
                    ))
            } else {
                compactHomeView
                    .transition(.opacity)
            }
        }
        .background(panelBackgroundView)
        .modifier(ReaderChromeSurface(
            paper: context.paper,
            ink: context.ink,
            protectsReadingControls: true
        ))
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.black.opacity(0.001))
                .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .onTapGesture {}
        }
        .shadow(color: Color.black.opacity(context.isNight ? 0.34 : 0.14), radius: 22, y: 10)
        .animation(.spring(response: 0.30, dampingFraction: 0.86), value: route)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: showingQuickFonts)
    }

    @ViewBuilder
    private var panelBackgroundView: some View {
        if context.usesWallpaper,
           context.background == .custom,
           let image = ReaderCustomWallpaperStore.cachedWallpaper {
            ReaderWallpaperView(
                image: image,
                fillMode: ReaderCustomWallpaperStore.adjustment.fillMode,
                adjustment: ReaderCustomWallpaperStore.adjustment,
                isNight: context.isNight
            )
            .opacity(max(context.menuOpacity * 0.28, 0.08))
            .allowsHitTesting(false)
        }
    }

    private func panelHeader(isCompactHome: Bool) -> some View {
        VStack(spacing: 5) {
            Capsule()
                .fill(context.ink.opacity(0.22))
                .frame(width: 34, height: 4)
                .padding(.top, 8)

            HStack(spacing: 10) {
                if showingQuickFonts {
                    backButton {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                            showingQuickFonts = false
                        }
                    }
                } else if route != nil {
                    backButton { setRoute(nil) }
                } else {
                    Color.clear.frame(width: 28, height: 26)
                }

                Spacer(minLength: 4)

                Text(headerTitle(isCompactHome: isCompactHome))
                    .font(.system(size: isCompactHome ? 13 : 15, weight: .semibold))
                    .foregroundStyle(context.ink.opacity(isCompactHome ? 0.72 : 0.94))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .accessibilityIdentifier("reader.settings.bookTitle")

                Spacer(minLength: 4)

                Button(action: actions.close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(context.ink.opacity(0.84))
                        .frame(width: 26, height: 26)
                        .background(context.ink.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭阅读设置")
                .accessibilityIdentifier("reader.settings.close")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, isCompactHome ? 6 : 8)
        }
    }

    private func backButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                Text("返回")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(context.ink.opacity(0.9))
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(context.ink.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("返回设置首页")
        .accessibilityIdentifier("reader.settings.back")
    }

    private func headerTitle(isCompactHome: Bool) -> String {
        if showingQuickFonts { return "书籍字体" }
        if let route { return route.title }
        return context.bookTitle.isEmpty ? "阅读设置" : context.bookTitle
    }

    private var compactHomeView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                topFontSizeAndFontRow
                backgroundCarouselRow
                pageTurnModeRow
                actionTileGrid
            }
            .padding(.horizontal, 16)
            .padding(.top, 2)
            .padding(.bottom, 12)
        }
    }

    private var topFontSizeAndFontRow: some View {
        let activeFont = ReaderFontFamily(rawValue: fontFamilyRaw) ?? .system
        let sizeRounded = Int(fontSize.rounded())
        return HStack(spacing: 10) {
            HStack(spacing: 0) {
                Button {
                    fontSize = max(12, (fontSize - 1).rounded())
                } label: {
                    Text("A-")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(context.ink)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("减小字号")

                Text("\(sizeRounded)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(context.ink)
                    .frame(minWidth: 36)

                Button {
                    fontSize = min(60, (fontSize + 1).rounded())
                } label: {
                    Text("A+")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(context.ink)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("增大字号")
            }
            .frame(height: 40)
            .frame(maxWidth: .infinity)
            .background(context.ink.opacity(0.075), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    showingQuickFonts = true
                }
            } label: {
                HStack(spacing: 6) {
                    Text(activeFont == .system ? "书籍字体" : activeFont.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(context.ink)
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(context.ink.opacity(0.56))
                }
                .padding(.horizontal, 14)
                .frame(height: 40)
                .background(context.ink.opacity(0.075), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(AppPressStyle())
            .accessibilityLabel("选择书籍字体")
        }
    }

    private var orderedBackgroundChoices: [ReaderBackground] {
        let featured: [ReaderBackground] = [
            .dark, .white, .sageGreen, .paper,
            .shuimoPaper, .starlight, .wuxiaScroll, .sakuraSky, .kawaiiNote
        ]
        var seen = Set(featured)
        var list = featured.filter { ReaderBackground.pickerCases.contains($0) || $0 == .dark }
        for item in ReaderBackground.pickerCases where !seen.contains(item) && item != .custom {
            seen.insert(item)
            list.append(item)
        }
        return list
    }

    private var backgroundCarouselRow: some View {
        let selectedBg = ReaderBackground(rawValue: backgroundRaw) ?? .white
        return VStack(alignment: .leading, spacing: 7) {
            Text("阅读背景")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(context.ink.opacity(0.72))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(orderedBackgroundChoices) { item in
                        backgroundSwatchCard(item: item, selected: selectedBg == item)
                    }
                    customBackgroundCard(selected: selectedBg == .custom)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func backgroundSwatchCard(item: ReaderBackground, selected: Bool) -> some View {
        let night = context.isNight && item.isDark ? true : (item == .dark || item == .starlight ? true : context.isNight)
        let swatchInk = item.resolvedTextColor(isNight: night)
        let swatchPaper = item.color(isNight: night)
        let assetName = item.wallpaperAssetName(isNight: night)

        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                backgroundRaw = item.rawValue
            }
        } label: {
            ZStack {
                if let assetName {
                    Image(assetName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 66, height: 48)
                        .clipped()
                        .overlay(swatchPaper.opacity(night ? 0.34 : 0.16))
                } else {
                    swatchPaper
                }

                VStack {
                    HStack {
                        Spacer()
                        if selected {
                            Image(systemName: "asterisk")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(swatchInk.opacity(0.85))
                                .padding(5)
                        }
                    }
                    Spacer()
                }

                VStack {
                    Spacer()
                    Text(shortBackgroundLabel(item))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(swatchInk.opacity(0.92))
                        .lineLimit(1)
                        .padding(.bottom, 6)
                }
            }
            .frame(width: 66, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        selected ? context.ink.opacity(0.88) : context.ink.opacity(0.16),
                        lineWidth: selected ? 1.8 : 0.7
                    )
            }
        }
        .buttonStyle(AppPressStyle())
        .accessibilityLabel(item.title)
    }

    private func customBackgroundCard(selected: Bool) -> some View {
        Button {
            backgroundRaw = ReaderBackground.custom.rawValue
            if let openWallpaperEditor = actions.openWallpaperEditor {
                openWallpaperEditor()
            } else {
                setRoute(.appearance)
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: "plus.viewfinder")
                    .font(.system(size: 14, weight: .semibold))
                Text("自定义")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(context.ink.opacity(selected ? 0.95 : 0.78))
            .frame(width: 66, height: 48)
            .background(context.ink.opacity(0.065), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        selected ? context.ink.opacity(0.88) : context.ink.opacity(0.24),
                        style: StrokeStyle(lineWidth: selected ? 1.6 : 0.9, dash: selected ? [] : [4, 3])
                    )
            }
        }
        .buttonStyle(AppPressStyle())
        .accessibilityLabel("自定义阅读背景")
    }

    private func shortBackgroundLabel(_ item: ReaderBackground) -> String {
        switch item {
        case .dark: return "黑色"
        case .white: return "白色"
        case .sageGreen: return "护眼绿"
        case .paper: return "羊皮纸"
        case .shuimoPaper: return "水墨"
        case .starlight: return "星夜"
        case .wuxiaScroll: return "竹林"
        case .sakuraSky: return "樱空"
        case .kawaiiNote: return "手账"
        default: return String(item.title.prefix(4))
        }
    }

    private var pageTurnModeRow: some View {
        let selectedMode = ReaderMode(rawValue: modeRaw) ?? .scroll
        return VStack(alignment: .leading, spacing: 7) {
            Text("翻页")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(context.ink.opacity(0.72))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ReaderMode.allCases) { mode in
                        let isSelected = selectedMode == mode
                        Button {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                modeRaw = mode.rawValue
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: iconForMode(mode))
                                    .font(.system(size: 11, weight: .semibold))
                                Text(mode.title)
                                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                            }
                            .foregroundStyle(isSelected ? context.paper : context.ink.opacity(0.88))
                            .padding(.horizontal, 13)
                            .frame(height: 33)
                            .background(
                                isSelected ? context.ink.opacity(0.88) : context.ink.opacity(0.075),
                                in: Capsule()
                            )
                        }
                        .buttonStyle(AppPressStyle())
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }

    private func iconForMode(_ mode: ReaderMode) -> String {
        switch mode {
        case .scroll: return "arrow.up.and.down.text.horizontal"
        case .pageTurn: return "rectangle.portrait.and.arrow.right"
        case .cover: return "square.stack"
        case .pageCurl: return "book.pages"
        }
    }

    private var actionTileGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
        return LazyVGrid(columns: columns, spacing: 8) {
            routeTile(.typography)
            routeTile(.appearance)
            quickActionTile(
                icon: context.isSpeechActive ? "speaker.wave.3.fill" : "speaker.wave.2",
                title: "朗读",
                subtitle: context.isSpeechActive ? "朗读中" : "语音设置",
                isActive: context.isSpeechActive
            ) {
                if let toggleSpeech = actions.toggleSpeech {
                    toggleSpeech()
                } else {
                    setRoute(.assistance)
                }
            }
            quickActionTile(
                icon: context.isAutoScrollActive ? "pause.fill" : "play.fill",
                title: "自动阅读",
                subtitle: context.isAutoScrollActive ? "滚动中" : "匀速翻页",
                isActive: context.isAutoScrollActive
            ) {
                if let toggleAutoScroll = actions.toggleAutoScroll {
                    toggleAutoScroll()
                } else {
                    setRoute(.assistance)
                }
            }
            routeTile(.themes)
            routeTile(.heading)
            routeTile(.chrome)
            routeTile(.assistance)
        }
        .padding(.top, 2)
    }

    private func routeTile(_ target: ReaderWorkbenchRoute) -> some View {
        Button {
            setRoute(target)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: target.systemImage)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(context.ink.opacity(0.88))
                Text(target.shortTitle)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(context.ink.opacity(0.92))
                    .lineLimit(1)
                Text(target.subtitle)
                    .font(.system(size: 9.5, weight: .regular))
                    .foregroundStyle(context.ink.opacity(0.56))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .contentShape(Rectangle())
            .matchedGeometryEffect(id: target.rawValue, in: morphNamespace)
        }
        .buttonStyle(AppPressStyle())
        .accessibilityIdentifier("reader.settings.route." + target.rawValue)
    }

    private func quickActionTile(
        icon: String,
        title: String,
        subtitle: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: isActive ? .bold : .medium))
                    .foregroundStyle(isActive ? context.accent : context.ink.opacity(0.88))
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(isActive ? context.accent : context.ink.opacity(0.92))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 9.5, weight: .regular))
                    .foregroundStyle(isActive ? context.accent.opacity(0.85) : context.ink.opacity(0.56))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                isActive ? context.accent.opacity(0.10) : Color.clear,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(AppPressStyle())
    }

    private var quickFontSelector: some View {
        let activeFont = ReaderFontFamily(rawValue: fontFamilyRaw) ?? .system
        return ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 10) {
                preview()
                    .frame(maxHeight: 84)
                    .clipped()

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(ReaderFontFamily.allCases) { family in
                        let selected = family == activeFont
                        Button {
                            fontFamilyRaw = family.rawValue
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(family.title)
                                        .font(family.swiftUIFont(size: 14, weight: .semibold))
                                        .foregroundStyle(context.ink)
                                    Text(family == .custom ? "已导入本地字体" : "正文即时预览")
                                        .font(.system(size: 10))
                                        .foregroundStyle(context.ink.opacity(0.56))
                                }
                                Spacer(minLength: 4)
                                if selected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundStyle(context.accent)
                                }
                            }
                            .padding(.horizontal, 12)
                            .frame(height: 48)
                            .background(
                                context.ink.opacity(selected ? 0.12 : 0.06),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(selected ? context.accent.opacity(0.75) : context.ink.opacity(0.10), lineWidth: 1)
                            }
                        }
                        .buttonStyle(AppPressStyle())
                    }
                }

                Button {
                    showingQuickFonts = false
                    setRoute(.typography)
                } label: {
                    Text("进入更多字重与排版细调")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(context.accent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(context.accent.opacity(0.09), in: Capsule())
                }
                .buttonStyle(AppPressStyle())
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    private func subpageView(for activeRoute: ReaderWorkbenchRoute) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                if activeRoute != .assistance {
                    preview()
                        .frame(maxHeight: 84)
                        .clipped()
                }
                page(activeRoute)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .matchedGeometryEffect(id: activeRoute.rawValue, in: morphNamespace)
    }

    private func setRoute(_ target: ReaderWorkbenchRoute?) {
        showingQuickFonts = false
        withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
            route = target
        }
        actions.routeChanged(target)
    }
}

struct ReaderClassicSettingsPanel: View {
    let context: ReaderWorkbenchContext
    private let preview: () -> AnyView
    private let page: (ReaderWorkbenchRoute) -> AnyView
    private let actions: ReaderWorkbenchActions

    init(
        context: ReaderWorkbenchContext,
        preview: @escaping () -> AnyView,
        page: @escaping (ReaderWorkbenchRoute) -> AnyView,
        actions: ReaderWorkbenchActions
    ) {
        self.context = context
        self.preview = preview
        self.page = page
        self.actions = actions
    }

    var body: some View {
        ReaderSettingsWorkbench(
            context: context,
            preview: preview,
            page: page,
            actions: actions
        )
    }
}
