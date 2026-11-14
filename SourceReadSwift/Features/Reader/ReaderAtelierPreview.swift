import SwiftUI

/// A bounded preview of the current book, using the same heading and typography preferences.
struct ReaderAtelierPreview: View {
    let title: String
    let excerpt: String
    var paperRevision: UUID? = nil
    @Environment(\.colorScheme) private var systemColorScheme
    @AppStorage("reader.fontFamily") private var familyRaw = ReaderFontFamily.system.rawValue
    @AppStorage("reader.fontWeight") private var weightRaw = ReaderBodyFontWeight.regular.rawValue
    @AppStorage("reader.customFontPostScriptName") private var customName = ""
    @AppStorage("reader.fontSize") private var bodySize = 20.0
    @AppStorage("reader.lineSpacing") private var lineSpacing = ReaderTypographyDefaults.lineSpacing
    @AppStorage("reader.chapterTitleFamily") private var titleFamilyRaw = ""
    @AppStorage("reader.chapterTitleSize") private var titleSize = 0.0
    @AppStorage("reader.chapterTitleBold") private var titleBold = true
    @AppStorage("reader.chapterDecoration") private var decorationRaw = "none"
    @AppStorage("reader.chapterAlignment") private var alignmentRaw = "leading"
    @AppStorage("reader.background") private var paperRaw = ReaderBackground.white.rawValue
    @AppStorage("reader.customWallpaperFillMode") private var fillRaw = ReaderWallpaperFillMode.fill.rawValue
    @AppStorage("reader.followSystemPaper") private var followSystemPaper = true
    @AppStorage("reader.inkOpacity") private var inkOpacity = 1.0
    @AppStorage("reader.customInkHex") private var customInkHexRaw = ""

    private var paper: ReaderBackground { ReaderBackground(rawValue: paperRaw) ?? .white }
    private var alignment: ReaderChapterAlignment { ReaderChapterAlignment(rawValue: alignmentRaw) ?? .leading }
    private var family: ReaderFontFamily { ReaderFontFamily(rawValue: familyRaw) ?? .system }
    private var bodyWeight: ReaderBodyFontWeight { ReaderBodyFontWeight(rawValue: weightRaw) ?? .regular }
    private var isNight: Bool {
        (paper != .custom && paper.isDark) || (followSystemPaper && systemColorScheme == .dark)
    }
    private var parsedCustomInkHex: UInt32? {
        let trimmed = customInkHexRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let hex = UInt32(trimmed.replacingOccurrences(of: "#", with: ""), radix: 16) else {
            return nil
        }
        return hex
    }
    var body: some View {
        VStack(alignment: alignment == .center ? .center : alignment == .trailing ? .trailing : .leading, spacing: 6) {
            HStack { Label("排版预览", systemImage: "book.closed"); Spacer(); Text("实时生效") }
                .font(.caption2).foregroundStyle(.secondary)
            let decoration = ReaderChapterDecoration(rawValue: decorationRaw) ?? .none
            if decoration != .none { ReaderChapterMotif(decoration: decoration) }
            Text(title).font((ReaderFontFamily(rawValue: titleFamilyRaw) ?? family).swiftUIFont(
                size: min(CGFloat(ReaderHeadingPreferences.titleSize(custom: titleSize, body: bodySize)), 24),
                weight: titleBold ? .bold : .regular, customPostScriptName: customName))
                .lineLimit(1).multilineTextAlignment(alignment.swiftUI).fixedSize(horizontal: false, vertical: true)
            Text(excerpt.isEmpty ? "当前章节暂无正文，加载后会显示真实内容。" : excerpt)
                .font(family.swiftUIFont(size: min(CGFloat(bodySize), 20), weight: bodyWeight.swiftUIWeight, customPostScriptName: customName))
                .lineSpacing(min(lineSpacing, 6)).lineLimit(2)
        }.padding(.horizontal, 14).padding(.vertical, 10).frame(maxWidth: .infinity)
            .foregroundStyle(paper.resolvedTextColor(isNight: isNight, customInkHex: parsedCustomInkHex, inkOpacity: inkOpacity))
            .background {
                if paper == .custom, let image = ReaderCustomWallpaperStore.cachedWallpaper {
                    ReaderWallpaperView(image: image, fillMode: ReaderWallpaperFillMode(rawValue: fillRaw) ?? .fill,
                        adjustment: ReaderCustomWallpaperStore.adjustment, isNight: isNight).id(paperRevision)
                } else { ReaderPaperTextureView(background: paper, night: isNight) }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.primary.opacity(0.08), lineWidth: 0.6) }
            .environment(\.colorScheme, isNight ? .dark : .light)
            .accessibilityLabel("当前书页的排版预览，不改变阅读位置")
    }
}

struct ReaderChapterDesignEditor: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage("reader.chapterDecoration") private var decorationRaw = "none"
    @AppStorage("reader.chapterAlignment") private var alignmentRaw = "leading"
    @AppStorage("reader.chapterTitleFamily") private var familyRaw = ""
    @AppStorage("reader.chapterTitleSize") private var size = 0.0
    @AppStorage("reader.chapterTitleBold") private var isBold = true
    @AppStorage("reader.chapterHeadingStyle") private var placement = ReaderPageChromeLayout.header.rawValue
    @AppStorage("reader.titleSpacing") private var titleSpacing = ReaderTypographyDefaults.titleSpacing
    @AppStorage("reader.fontSize") private var bodySize = 20.0
    @Namespace private var selection
    @AppMotion private var motion
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("让每一章，有自己的开场。") .font(.title3.weight(.semibold))
            Text("章饰只出现在章节开头。正文、书签和阅读位置保持原有逻辑。")
                .font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: typeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(ReaderChapterDecoration.allCases, id: \.self) { decoration in
                    Button {
                        withAnimation(motion.animation(.navigation)) { decorationRaw = decoration.rawValue }
                        HapticFeedback.light()
                    } label: {
                        VStack(spacing: 12) {
                            ReaderChapterMotif(decoration: decoration, width: 96).frame(maxWidth: .infinity, minHeight: 40)
                            Text(decoration.title).font(.subheadline.weight(.medium))
                            if decoration.rawValue == decorationRaw { Label("已选择", systemImage: "checkmark.circle.fill").font(.caption) }
                            else { Text("章首装帧").font(.caption).foregroundStyle(.secondary) }
                        }.frame(maxWidth: .infinity, minHeight: 124).padding(8)
                            .background {
                                if decoration.rawValue == decorationRaw {
                                    RoundedRectangle(cornerRadius: 16).fill(AppTheme.accent.opacity(0.10))
                                        .matchedGeometryEffect(id: "chapter-selection", in: selection)
                                } else { RoundedRectangle(cornerRadius: 16).fill(AppTheme.elevatedCard) }
                            }
                            .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(AppTheme.accent.opacity(decoration.rawValue == decorationRaw ? 0.6 : 0.10), lineWidth: 1) }
                    }.buttonStyle(AppPressStyle()).accessibilityAddTraits(decoration.rawValue == decorationRaw ? .isSelected : [])
                }
            }
            BrandSegmentedControl("章节名对齐", selection: $alignmentRaw, options:
                            ReaderChapterAlignment.allCases.map { ($0.rawValue, $0.title) })
            VStack(alignment: .leading, spacing: 8) {
                Text("章节标题位置").font(.subheadline.weight(.semibold))
                BrandSegmentedControl("章节标题位置", selection: $placement, options:
                            ReaderPageChromeLayout.allCases.map { ($0.rawValue, $0.title) })
                Text((ReaderPageChromeLayout(rawValue: placement) ?? .header).help)
                    .font(.caption).foregroundStyle(.secondary)
                if placement != ReaderPageChromeLayout.hidden.rawValue {
                    Text("标题下方留白 · \(Int(titleSpacing)) pt").font(.subheadline)
                    Slider(value: $titleSpacing, in: 0...36, step: 2)
                        .accessibilityLabel("标题下方留白")
                }
            }
            Toggle("章节名加粗", isOn: $isBold)
            Picker("章节名字体", selection: $familyRaw) {
                Text("跟随正文").tag("")
                ForEach(ReaderFontFamily.allCases) { Text($0.title).tag($0.rawValue) }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("章节名字号 · \(Int(ReaderHeadingPreferences.titleSize(custom: size, body: bodySize))) pt")
                Slider(value: Binding(get: { ReaderHeadingPreferences.titleSize(custom: size, body: bodySize) }, set: { size = $0 }), in: 14...44, step: 1)
                Button("跟随正文字号") { size = 0 }.font(.caption)
            }
            NavigationLink { CustomFontManagementView() } label: { Label("管理与导入字体", systemImage: "textformat") }
        }.tint(AppTheme.accent)
    }
}
