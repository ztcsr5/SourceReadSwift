import SwiftUI
import UIKit

/// A live, unclipped preview of the current book using the same heading, typography, highlight, and chrome preferences.
struct ReaderAtelierPreview: View {
    let title: String
    let excerpt: String
    var paperRevision: UUID? = nil
    var bookTitle: String = ""
    var sourceURL: String = ""

    @Environment(\.colorScheme) private var systemColorScheme
    @ObservedObject private var highlightRuleStore = ReaderHighlightRuleStore.shared

    @AppStorage("reader.fontFamily") private var familyRaw = ReaderFontFamily.system.rawValue
    @AppStorage("reader.fontWeight") private var weightRaw = ReaderBodyFontWeight.regular.rawValue
    @AppStorage("reader.customFontPostScriptName") private var customName = ""
    @AppStorage("reader.fontSize") private var bodySize = 20.0
    @AppStorage("reader.lineSpacing") private var lineSpacing = ReaderTypographyDefaults.lineSpacing
    @AppStorage("reader.letterSpacing") private var letterSpacing = ReaderTypographyDefaults.letterSpacing
    @AppStorage("reader.paragraphSpacing") private var paragraphSpacing = ReaderTypographyDefaults.paragraphSpacing
    @AppStorage("reader.paragraphIndent") private var paragraphIndent = ReaderTypographyDefaults.paragraphIndent
    @AppStorage("reader.pagePadding") private var pagePadding = ReaderTypographyDefaults.pagePadding
    @AppStorage("reader.textAlignment") private var textAlignmentRaw = ReaderTextAlignment.smart.rawValue
    @AppStorage("reader.chapterHeadingStyle") private var headingStyleRaw = ReaderPageChromeLayout.header.rawValue
    @AppStorage("reader.chapterTitleFamily") private var titleFamilyRaw = ""
    @AppStorage("reader.chapterTitleSize") private var titleSize = 0.0
    @AppStorage("reader.chapterTitleBold") private var titleBold = true
    @AppStorage("reader.chapterDecoration") private var decorationRaw = "none"
    @AppStorage("reader.chapterAlignment") private var alignmentRaw = "leading"
    @AppStorage("reader.headerFontSize") private var headerFontSize = 12.0
    @AppStorage("reader.headerOpacity") private var headerOpacity = 0.82
    @AppStorage("reader.headerLeftSlot") private var headerLeftSlotRaw = ReaderChromeSlotContent.chapterTitle.rawValue
    @AppStorage("reader.headerCenterSlot") private var headerCenterSlotRaw = ReaderChromeSlotContent.none.rawValue
    @AppStorage("reader.headerRightSlot") private var headerRightSlotRaw = ReaderChromeSlotContent.none.rawValue
    @AppStorage("reader.footerLeftSlot") private var footerLeftSlotRaw = ReaderChromeSlotContent.time.rawValue
    @AppStorage("reader.footerCenterSlot") private var footerCenterSlotRaw = ReaderChromeSlotContent.chapterAndPercent.rawValue
    @AppStorage("reader.footerRightSlot") private var footerRightSlotRaw = ReaderChromeSlotContent.pageAndBattery.rawValue
    @AppStorage("reader.chromeShowDivider") private var chromeShowDivider = false
    @AppStorage("reader.footerShowTime") private var footerShowTime = true
    @AppStorage("reader.footerShowBatteryIcon") private var footerShowBatteryIcon = true
    @AppStorage("reader.footerShowBatteryPercent") private var footerShowBatteryPercent = true
    @AppStorage("reader.background") private var paperRaw = ReaderBackground.white.rawValue
    @AppStorage("reader.customWallpaperFillMode") private var fillRaw = ReaderWallpaperFillMode.fill.rawValue
    @AppStorage("reader.followSystemPaper") private var followSystemPaper = true
    @AppStorage("reader.inkOpacity") private var inkOpacity = 1.0
    @AppStorage("reader.customInkHex") private var customInkHexRaw = ""

    private var paper: ReaderBackground { ReaderBackground(rawValue: paperRaw) ?? .white }
    private var headingAlignment: ReaderChapterAlignment { ReaderChapterAlignment(rawValue: alignmentRaw) ?? .leading }
    private var family: ReaderFontFamily { ReaderFontFamily(rawValue: familyRaw) ?? .system }
    private var bodyWeight: ReaderBodyFontWeight { ReaderBodyFontWeight(rawValue: weightRaw) ?? .regular }
    private var textAlignment: ReaderTextAlignment { ReaderTextAlignment(rawValue: textAlignmentRaw) ?? .smart }
    private var chromeStyle: ReaderPageChromeLayout { ReaderPageChromeLayout(rawValue: headingStyleRaw) ?? .header }
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
        let resolvedInk = paper.resolvedTextColor(isNight: isNight, customInkHex: parsedCustomInkHex, inkOpacity: inkOpacity)
        let headerLeft = ReaderChromeSlotContent(rawValue: headerLeftSlotRaw) ?? .chapterTitle
        let headerCenter = ReaderChromeSlotContent(rawValue: headerCenterSlotRaw) ?? .none
        let headerRight = ReaderChromeSlotContent(rawValue: headerRightSlotRaw) ?? .none
        let footerLeft = ReaderChromeSlotContent(rawValue: footerLeftSlotRaw) ?? .time
        let footerCenter = ReaderChromeSlotContent(rawValue: footerCenterSlotRaw) ?? .chapterAndPercent
        let footerRight = ReaderChromeSlotContent(rawValue: footerRightSlotRaw) ?? .pageAndBattery
        let displayTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "第壹章 · 纸间入门指南" : title
        let slotContext = ReaderChromeSlotContext(
            chapterTitle: chromeStyle == .hidden ? nil : displayTitle,
            bookTitle: bookTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "纸间示范集" : bookTitle,
            pageProgressText: "12/38",
            percentText: "31.6%",
            chapterAndPercentText: "\(displayTitle)  31.6%",
            batterySymbolName: "battery.75",
            batteryPercentageText: "82%",
            showBatteryIcon: footerShowBatteryIcon,
            showBatteryPercent: footerShowBatteryPercent,
            showTime: footerShowTime
        )
        let horizontalMargin = min(max(CGFloat(pagePadding) * 0.72, 10), 28)
        let clampedBodySize = min(max(CGFloat(bodySize), 12), 26)
        let headingFrameAlignment: Alignment = headingAlignment == .center ? .center : (headingAlignment == .trailing ? .trailing : .leading)
        let headingStackAlignment: HorizontalAlignment = headingAlignment == .center ? .center : (headingAlignment == .trailing ? .trailing : .leading)
        let sampleBody = excerpt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? ReaderTypographySample.defaultSampleText
            : excerpt

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Label("实时排版预览", systemImage: "book.closed")
                    .font(.caption2.weight(.semibold))
                Spacer(minLength: 4)
                Text("\(family.title) · \(Int(bodySize))pt · 行\(Int(lineSpacing)) · 缩\(Int(paragraphIndent))")
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(resolvedInk.opacity(0.08), in: Capsule())
            }
            .foregroundStyle(resolvedInk.opacity(0.62))

            if headerLeft != .none || headerCenter != .none || headerRight != .none {
                VStack(spacing: 4) {
                    ReaderThreeSlotChromeStrip(
                        left: headerLeft,
                        center: headerCenter,
                        right: headerRight,
                        context: slotContext,
                        fontSize: min(CGFloat(ReaderHeadingPreferences.headerSize(headerFontSize)), 13),
                        weight: .medium,
                        foreground: resolvedInk.opacity(ReaderHeadingPreferences.opacity(headerOpacity))
                    )
                    if chromeShowDivider {
                        Rectangle()
                            .fill(resolvedInk.opacity(0.12))
                            .frame(height: 0.5)
                    }
                }
            }

            if chromeStyle != .hidden {
                let decoration = ReaderChapterDecoration(rawValue: decorationRaw) ?? .none
                VStack(alignment: headingStackAlignment, spacing: 4) {
                    if decoration != .none {
                        ReaderChapterMotif(decoration: decoration, width: 104)
                            .foregroundStyle(resolvedInk.opacity(0.85))
                    }
                    Text(displayTitle)
                        .font((ReaderFontFamily(rawValue: titleFamilyRaw) ?? family).swiftUIFont(
                            size: min(CGFloat(ReaderHeadingPreferences.titleSize(custom: titleSize, body: bodySize)), 24),
                            weight: titleBold ? .bold : .regular,
                            customPostScriptName: customName
                        ))
                        .lineLimit(1)
                        .multilineTextAlignment(headingAlignment.swiftUI)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: headingFrameAlignment)
            }

            ReaderTypographySample(
                font: family.uiFont(ofSize: clampedBodySize, weight: bodyWeight.uiWeight, customPostScriptName: customName),
                boldFont: family.uiFont(ofSize: clampedBodySize, weight: .semibold, customPostScriptName: customName),
                ink: UIColor(resolvedInk),
                layout: .init(
                    alignment: textAlignment,
                    lineSpacing: min(lineSpacing, 16),
                    letterSpacing: letterSpacing,
                    paragraphSpacing: min(paragraphSpacing, 20),
                    paragraphIndent: min(paragraphIndent, 48)
                ),
                highlightRules: highlightRuleStore.activeRules(bookTitle: bookTitle, sourceURL: sourceURL),
                isNight: isNight,
                sampleText: sampleBody
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)

            if footerLeft != .none || footerCenter != .none || footerRight != .none {
                VStack(spacing: 4) {
                    if chromeShowDivider {
                        Rectangle()
                            .fill(resolvedInk.opacity(0.12))
                            .frame(height: 0.5)
                    }
                    ReaderThreeSlotChromeStrip(
                        left: footerLeft,
                        center: footerCenter,
                        right: footerRight,
                        context: slotContext,
                        fontSize: 10,
                        weight: .medium,
                        foreground: resolvedInk.opacity(0.5)
                    )
                }
            }
        }
        .padding(.horizontal, horizontalMargin)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(resolvedInk)
        .background {
            if paper == .custom, let image = ReaderCustomWallpaperStore.cachedWallpaper {
                ReaderWallpaperView(image: image, fillMode: ReaderWallpaperFillMode(rawValue: fillRaw) ?? .fill,
                    adjustment: ReaderCustomWallpaperStore.adjustment, isNight: isNight).id(paperRevision)
            } else { ReaderPaperTextureView(background: paper, night: isNight) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.primary.opacity(0.10), lineWidth: 0.75) }
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
