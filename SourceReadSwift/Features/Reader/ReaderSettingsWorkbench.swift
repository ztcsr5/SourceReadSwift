import SwiftUI
import UIKit

enum ReaderWorkbenchRoute: String, CaseIterable, Hashable {
    case themes, typography, appearance, heading, chrome, highlights, assistance

    var title: String {
        switch self {
        case .themes: return "氛围主题"
        case .typography: return "排版与字体"
        case .appearance: return "背景与墨色"
        case .heading: return "标题与装帧"
        case .chrome: return "页眉页脚"
        case .highlights: return "关键词高亮"
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
        case .highlights: return "高亮"
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
        case .highlights: return "词句着色"
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
        case .highlights: return "highlighter"
        case .assistance: return "ellipsis.circle"
        }
    }
}

struct ReaderWorkbenchContext {
    let bookTitle: String
    let background: ReaderBackground
    let bottomInset: CGFloat
    var initialRoute: ReaderWorkbenchRoute? = nil
    var isNightOverride: Bool? = nil
    var customInkColor: Color? = nil
    var customAccentColor: Color? = nil
    var isSpeechActive: Bool = false
    var isAutoScrollActive: Bool = false

    var isNight: Bool { isNightOverride ?? background.isDark }
    var paper: Color { background.color(isNight: isNight) }
    var ink: Color { customInkColor ?? background.resolvedTextColor(isNight: isNight) }
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
    private enum Screen: Equatable { case home, fonts, route(ReaderWorkbenchRoute) }
    @State private var screen: Screen
    @State private var isReturningHome = false
    @State private var hasAppeared = false
    @AppMotion private var motion
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.readingEdition) private var skin

    @AppStorage("reader.fontSize") private var fontSize = ReaderTypographyDefaults.fontSize
    @AppStorage("reader.fontFamily") private var fontFamilyRaw = ReaderFontFamily.system.rawValue
    @AppStorage("reader.background") private var backgroundRaw = ReaderBackground.white.rawValue
    @AppStorage("reader.followSystemPaper") private var followSystemPaper = false
    @AppStorage("reader.mode") private var modeRaw = ReaderMode.scroll.rawValue
    @ObservedObject private var highlightRuleStore = ReaderHighlightRuleStore.shared

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
        _screen = State(initialValue: context.initialRoute.map(Screen.route) ?? .home)
    }

    var body: some View {
        GeometryReader { proxy in
            let maxExpanded = ReaderSettingsLayoutPolicy.maxPanelHeight(
                viewportHeight: proxy.size.height,
                bottomInset: context.bottomInset
            )
            let isCompactHome = screen == .home
            // Keep the home glass compact (~50% height) while giving subpages
            // comfortable height for unclipped live previews and sliders.
            let compactHeight = max(proxy.size.height * 0.51, min(360, proxy.size.height * 0.55))
            let expandedSubpageHeight = max(proxy.size.height * 0.62, min(460, proxy.size.height * 0.66))
            let desiredHeight = isCompactHome ? compactHeight : expandedSubpageHeight
            let targetHeight = textSize.isAccessibilitySize ? maxExpanded : min(maxExpanded, desiredHeight)
            let width = ReaderSettingsLayoutPolicy.maxPanelWidth(viewportWidth: proxy.size.width)

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                panelBody(targetHeight: targetHeight, isCompactHome: isCompactHome)
                    .frame(width: width)
                    .padding(.bottom, max(context.bottomInset, 12))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .tint(context.accent)
        .environment(\.colorScheme, context.isNight ? .dark : .light)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reader.settingsWorkbench")
    }

    private func panelBody(targetHeight: CGFloat, isCompactHome: Bool) -> some View {
        VStack(spacing: 0) {
            panelHeader(isCompactHome: isCompactHome)
            ZStack(alignment: .top) {
                switch screen {
                case .home: compactHomeView.transition(pageTransition)
                case .fonts: quickFontSelector.transition(pageTransition)
                case .route(let route): subpageView(for: route).id(route).transition(pageTransition)
                }
            }
            .frame(maxHeight: .infinity)
            .clipped()
        }
        .frame(height: targetHeight)
        .clipShape(skin.map { AnyShape(EditionContour(skin: $0)) } ?? AnyShape(RoundedRectangle(cornerRadius: 24, style: .continuous)))
        .modifier(ReaderChromeSurface(paper: context.paper, ink: context.ink))
        .background {
            (skin.map { AnyShape(EditionContour(skin: $0)) } ?? AnyShape(RoundedRectangle(cornerRadius: 24, style: .continuous)))
                .fill(Color.black.opacity(0.001))
                .contentShape(Rectangle())
                .onTapGesture {}
        }
        .scaleEffect(hasAppeared || motion.reducesMotion ? 1.0 : 0.95, anchor: .bottom)
        .opacity(hasAppeared || motion.reducesMotion ? 1.0 : 0.01)
        .animation(motion.reducesMotion ? nil : .spring(response: 0.34, dampingFraction: 0.80), value: screen)
        .onAppear {
            guard !hasAppeared else { return }
            withAnimation(motion.reducesMotion ? nil : .spring(response: 0.34, dampingFraction: 0.78)) {
                hasAppeared = true
            }
        }
    }

    private var pageTransition: AnyTransition {
        guard !motion.reducesMotion else { return .identity }
        let distance: CGFloat = skin == .blade ? 20 : 12
        let step = isReturningHome ? -distance : distance
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: step)),
            removal: .opacity.combined(with: .offset(x: -step * 0.5))
        )
    }

    private func panelHeader(isCompactHome: Bool) -> some View {
        VStack(spacing: 5) {
            Capsule()
                .fill(context.ink.opacity(0.22))
                .frame(width: 34, height: 4)
                .padding(.top, 8)

            HStack(spacing: 10) {
                if !isCompactHome {
                    backButton { showScreen(.home) }
                } else {
                    Color.clear.frame(width: 28, height: 26)
                }

                Spacer(minLength: 4)

                EditionHeadingLabel(title: headerTitle, font: .system(size: isCompactHome ? 13 : 15, weight: .semibold),
                                    ink: context.ink, isCompact: true)
                    .foregroundStyle(context.ink.opacity(isCompactHome ? 0.72 : 0.94))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .accessibilityIdentifier("reader.settings.bookTitle")

                Spacer(minLength: 4)

                Button(action: actions.close) {
                    EditionGlyph(systemName: "xmark", size: 11, weight: .bold)
                        .foregroundStyle(context.ink.opacity(0.86))
                        .frame(width: 28, height: 28)
                        .modifier(controlFinish(legacyRadius: 14, legacyFill: context.ink.opacity(0.08)))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(ReaderControlPressStyle())
                .accessibilityLabel("关闭阅读设置")
                .accessibilityIdentifier("reader.settings.close")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, isCompactHome ? 6 : 8)

            EditionDivider(ink: context.accent.opacity(0.65), verticalPadding: 0)
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
        }
    }

    private func backButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                EditionGlyph(systemName: "chevron.left", size: 11, weight: .semibold)
                Text("返回")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(context.ink.opacity(0.9))
            .padding(.horizontal, 10)
            .frame(height: 28)
            .modifier(controlFinish(legacyRadius: 14, legacyFill: context.ink.opacity(0.08)))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(ReaderControlPressStyle())
        .accessibilityLabel("返回设置首页")
        .accessibilityIdentifier("reader.settings.back")
    }

    private var headerTitle: String {
        switch screen {
        case .home: return context.bookTitle.isEmpty ? "阅读设置" : context.bookTitle
        case .fonts: return "书籍字体"
        case .route(let route): return route.title
        }
    }

    private var compactHomeView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                topFontSizeAndFontRow
                backgroundCarouselRow
                pageTurnModeRow
                actionTileGrid
                highlightQuickStrip
            }
            .padding(.horizontal, 16)
            .padding(.top, 2)
            .padding(.bottom, 12)
        }
    }

    private var highlightQuickStrip: some View {
        let enabledCount = highlightRuleStore.rules.filter(\.enabled).count
        return Button {
            showScreen(.route(.highlights))
        } label: {
            HStack(spacing: 8) {
                EditionGlyph(systemName: "highlighter", size: 13, weight: .semibold)
                    .foregroundStyle(enabledCount > 0 ? context.accent : context.ink.opacity(0.75))
                Text("关键词高亮")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(context.ink.opacity(0.92))
                Text(enabledCount > 0 ? "已启用 \(enabledCount) 条" : "点击配置词句着色")
                    .font(.system(size: 11))
                    .foregroundStyle(context.ink.opacity(0.56))
                    .lineLimit(1)
                Spacer(minLength: 4)
                EditionGlyph(systemName: "chevron.right", size: 11, weight: .semibold)
                    .foregroundStyle(context.ink.opacity(0.45))
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .modifier(controlFinish(isSelected: enabledCount > 0, legacyRadius: 12,
                legacyFill: enabledCount > 0 ? context.accent.opacity(0.09) : context.ink.opacity(0.05)))
            .contentShape(Rectangle())
        }
        .buttonStyle(ReaderControlPressStyle())
        .accessibilityIdentifier("reader.settings.route.highlights")
    }

    private var topFontSizeAndFontRow: some View {
        let activeFont = ReaderFontFamily(rawValue: fontFamilyRaw) ?? .system
        let sizeRounded = Int(fontSize.rounded())
        return HStack(spacing: 10) {
            HStack(spacing: 0) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    fontSize = max(12, (fontSize - 1).rounded())
                } label: {
                    Text("A-")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(context.ink)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(ReaderControlPressStyle())
                .accessibilityLabel("减小字号")

                Text("\(sizeRounded)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(motion.reducesMotion ? nil : .spring(response: 0.22, dampingFraction: 0.76), value: sizeRounded)
                    .foregroundStyle(context.ink)
                    .frame(minWidth: 36)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    fontSize = min(60, (fontSize + 1).rounded())
                } label: {
                    Text("A+")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(context.ink)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(ReaderControlPressStyle())
                .accessibilityLabel("增大字号")
            }
            .frame(height: 44)
            .frame(maxWidth: .infinity)
            .modifier(controlFinish(legacyRadius: 13, legacyFill: context.ink.opacity(0.075)))

            Button {
                showScreen(.fonts)
            } label: {
                HStack(spacing: 6) {
                    Text(activeFont == .system ? "书籍字体" : activeFont.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(context.ink)
                        .lineLimit(1)
                    EditionGlyph(systemName: "chevron.right", size: 11, weight: .semibold)
                        .foregroundStyle(context.ink.opacity(0.56))
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
                .modifier(controlFinish(legacyRadius: 13, legacyFill: context.ink.opacity(0.075)))
            }
            .buttonStyle(ReaderControlPressStyle())
            .accessibilityLabel("选择书籍字体")
        }
    }

    private var orderedBackgroundChoices: [ReaderBackground] {
        let featured: [ReaderBackground] = [
            .dark, .white, .mistLeaf, .mistSky, .mistRose, .sageGreen, .paper,
            .wushanFlame, .wushanInk, .wushanJade, .starlight, .kawaiiNote
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
                LazyHStack(spacing: 10) {
                    ForEach(orderedBackgroundChoices) { item in
                        backgroundSwatchCard(item: item, selected: selectedBg == item)
                    }
                    customBackgroundCard(selected: selectedBg == .custom)
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 3)
            }
            .frame(height: 56)
        }
    }

    private func backgroundSwatchCard(item: ReaderBackground, selected: Bool) -> some View {
        // Always preview each paper swatch in its own true daylight/night identity so
        // light presets (such as 白色) never turn dark when previewed on a dark page.
        let night = item.isDark
        let swatchInk = item.resolvedTextColor(isNight: night)
        let swatchPaper = item.color(isNight: night)
        let assetName = item.wallpaperAssetName(isNight: night)

        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if !item.isDark {
                followSystemPaper = false
            }
            guard !selected else { return }
            withAnimation(motion.reducesMotion ? nil : .spring(response: 0.28, dampingFraction: 0.72)) {
                backgroundRaw = item.rawValue
            }
        } label: {
            ZStack {
                if item.mistEdge != nil {
                    ReaderPaperTextureView(background: item, night: night)
                } else if let assetName {
                    ReaderIllustratedSwatch(name: assetName, paper: swatchPaper)
                        .id(assetName)
                        .overlay(swatchPaper.opacity(night ? 0.30 : 0.14))
                } else {
                    swatchPaper
                }

                VStack {
                    HStack {
                        Spacer()
                        EditionGlyph(systemName: "checkmark.circle.fill", size: 12)
                            .foregroundStyle(swatchInk)
                            .scaleEffect(selected ? 1.0 : 0.5)
                            .opacity(selected ? 1 : 0)
                            .padding(5)
                            .animation(motion.reducesMotion ? nil : .spring(response: 0.26, dampingFraction: 0.68), value: selected)
                    }
                    Spacer()
                }

                VStack {
                    Spacer()
                    Text(shortBackgroundLabel(item))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(swatchInk.opacity(0.94))
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                        .padding(.bottom, 6)
                }
            }
            .frame(width: 68, height: 48)
            .clipShape(skin.map { AnyShape(EditionContour(skin: $0)) } ?? AnyShape(RoundedRectangle(cornerRadius: 12, style: .continuous)))
            .overlay {
                (skin.map { AnyShape(EditionContour(skin: $0)) } ?? AnyShape(RoundedRectangle(cornerRadius: 12, style: .continuous)))
                    .stroke(
                        selected ? context.accent : context.ink.opacity(0.18),
                        lineWidth: selected ? 2.0 : 0.75
                    )
                    .animation(motion.reducesMotion ? nil : .spring(response: 0.26, dampingFraction: 0.70), value: selected)
                    .allowsHitTesting(false)
            }
            .scaleEffect(selected && !motion.reducesMotion ? 1.04 : 1.0)
            .shadow(color: selected ? context.accent.opacity(0.24) : .clear, radius: selected ? 5 : 0, y: 2)
            .animation(motion.reducesMotion ? nil : .spring(response: 0.28, dampingFraction: 0.68), value: selected)
        }
        .buttonStyle(ReaderControlPressStyle())
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func customBackgroundCard(selected: Bool) -> some View {
        Button {
            backgroundRaw = ReaderBackground.custom.rawValue
            if let openWallpaperEditor = actions.openWallpaperEditor {
                openWallpaperEditor()
            } else {
                showScreen(.route(.appearance))
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
        .buttonStyle(ReaderControlPressStyle())
        .accessibilityLabel("自定义阅读背景")
    }

    private func shortBackgroundLabel(_ item: ReaderBackground) -> String {
        switch item {
        case .dark: return "黑色"
        case .white: return "白色"
        case .sageGreen: return "护眼绿"
        case .paper: return "羊皮纸"
        case .wushanFlame: return "炽焰雾山"
        case .wushanInk: return "雾山浓墨"
        case .wushanJade: return "青岚竹影"
        case .shuimoPaper: return "水墨"
        case .starlight: return "星夜"
        case .wuxiaScroll: return "武侠"
        case .sakuraSky: return "樱空"
        case .kawaiiNote: return "兔兔"
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
                    let visibleModes = ReaderMode.pickerCases.contains(selectedMode)
                        ? ReaderMode.pickerCases
                        : ReaderMode.pickerCases + [selectedMode]
                    ForEach(visibleModes) { mode in
                        let isSelected = selectedMode == mode
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            guard !isSelected else { return }
                            withAnimation(motion.reducesMotion ? nil : .spring(response: 0.26, dampingFraction: 0.72)) {
                                modeRaw = mode.rawValue
                            }
                        } label: {
                            HStack(spacing: 5) {
                                EditionGlyph(systemName: iconForMode(mode), size: 11)
                                Text(mode.title)
                                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                            }
                            .padding(.horizontal, 13)
                            .frame(height: 33)
                            .modifier(controlFinish(isSelected: isSelected, legacyRadius: 18,
                                legacyFill: isSelected ? context.ink.opacity(0.88) : context.ink.opacity(0.075),
                                legacyInk: isSelected ? context.paper : context.ink.opacity(0.88)))
                            .scaleEffect(isSelected && !motion.reducesMotion ? 1.03 : 1.0)
                            .animation(motion.reducesMotion ? nil : .spring(response: 0.26, dampingFraction: 0.70), value: isSelected)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(ReaderControlPressStyle())
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 2)
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
        case .dissolve: return "square.on.square"
        case .stacked: return "square.3.layers.3d"
        case .ripple: return "drop.circle"
        case .verticalSlide: return "arrow.up.and.down"
        case .parallax: return "square.2.layers.3d"
        case .wipe: return "rectangle.lefthalf.inset.filled"
        case .split: return "rectangle.split.2x1"
        case .perspective: return "rectangle.portrait.rotate"
        case .cube: return "cube.transparent"
        case .fan: return "fanblades"
        case .cardGlide: return "rectangle.on.rectangle.angled"
        case .lens: return "camera.aperture"
        }
    }

    private var actionTileGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: textSize.isAccessibilitySize ? 2 : 4)
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
                    showScreen(.route(.assistance))
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
                    showScreen(.route(.assistance))
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
            showScreen(.route(target))
        } label: {
            VStack(spacing: 4) {
                EditionGlyph(systemName: target.systemImage, size: 16, weight: .medium)
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
            .frame(minHeight: textSize.isAccessibilitySize ? 58 : 54)
            .modifier(controlFinish())
            .contentShape(Rectangle())
        }
        .buttonStyle(ReaderControlPressStyle())
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
                EditionGlyph(systemName: icon, size: 16, weight: isActive ? .bold : .medium)
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
            .frame(minHeight: textSize.isAccessibilitySize ? 58 : 54)
            .modifier(controlFinish(legacyFill: isActive ? context.accent.opacity(0.10) : .clear))
            .overlay(alignment: .topTrailing) {
                EditionStatusDot(isActive: isActive, ink: context.accent)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(ReaderControlPressStyle())
    }

    private var quickFontSelector: some View {
        let activeFont = ReaderFontFamily(rawValue: fontFamilyRaw) ?? .system
        return ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 10) {
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
                                    EditionGlyph(systemName: "checkmark.circle.fill", size: 14)
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
                                    .animation(motion.animation(.press), value: selected)
                                    .allowsHitTesting(false)
                            }
                        }
                        .buttonStyle(ReaderControlPressStyle())
                    }
                }

                Button {
                    showScreen(.route(.typography))
                } label: {
                    Text("进入更多字重与排版细调")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(context.accent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(context.accent.opacity(0.09), in: Capsule())
                }
                .buttonStyle(ReaderControlPressStyle())
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    private func subpageView(for activeRoute: ReaderWorkbenchRoute) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                switch activeRoute {
                case .typography, .heading, .appearance:
                    preview()
                case .themes, .chrome, .highlights, .assistance:
                    EmptyView()
                }
                page(activeRoute)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    private func showScreen(_ next: Screen) {
        guard screen != next else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        isReturningHome = next == .home
        // Animate only page replacement; the backdrop and preference writes
        // stay outside this transaction.
        withAnimation(motion.reducesMotion ? nil : .spring(response: 0.32, dampingFraction: 0.84)) { screen = next }
        if case .route(let route) = next { actions.routeChanged(route) }
        else { actions.routeChanged(nil) }
    }

    private func controlFinish(isSelected: Bool = false, legacyRadius: CGFloat = 12,
                               legacyFill: Color = .clear, legacyInk: Color? = nil) -> EditionControlFinish {
        EditionControlFinish(ink: context.ink, paper: context.paper, isSelected: isSelected,
                             legacyRadius: legacyRadius, legacyFill: legacyFill, legacyInk: legacyInk ?? context.ink)
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
