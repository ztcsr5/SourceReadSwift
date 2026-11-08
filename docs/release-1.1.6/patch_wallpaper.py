from pathlib import Path
R=Path(__file__).resolve().parents[2]
p=R/'SourceReadSwift/Features/Reader/ReaderSettingsModels.swift';s=p.read_text(encoding='utf8')
s=s.replace('    case linen\n','    case linen\n    case bamboo, mountains, ginkgo, tide\n',1)
s=s.replace('            .kraftTexture, .parchmentTexture, .linen,','            .bamboo, .mountains, .ginkgo, .tide,\n            .kraftTexture, .parchmentTexture, .linen,',1)
s=s.replace('        case .linen: return "亚麻纸纹"','''        case .linen: return "亚麻纸纹"
        case .bamboo: return "竹影宣纸"
        case .mountains: return "远山雾白"
        case .ginkgo: return "银杏花笺"
        case .tide: return "浅海潮汐"''',1)
s=s.replace('self == .linen }','self == .linen || wallpaperAssetName != nil }',1)
s=s.replace('    var color: Color {','''    var wallpaperAssetName: String? {
        switch self {
        case .bamboo: return "ReadingBamboo"
        case .mountains: return "ReadingMountains"
        case .ginkgo: return "ReadingGinkgo"
        case .tide: return "ReadingTide"
        default: return nil
        }
    }

    var color: Color {''',1)
s=s.replace('        case .linen: return 0xF1EBDD','''        case .linen: return 0xF1EBDD
        case .bamboo: return 0xEFF2E3
        case .mountains: return 0xF5F3EB
        case .ginkgo: return 0xF8F1E7
        case .tide: return 0xEFF5F7''',1)
s=s.replace('        case .linen: return 0x38342F','        case .linen: return 0x38342F\n        case .bamboo, .mountains, .ginkgo, .tide: return 0x222A25',1)
s=s.replace('        case .white: return 0x18181A\n        case .gray: return 0x2C2C2E', '        case .bamboo, .mountains, .ginkgo, .tide: return 0x1D2420\n        case .white: return 0x18181A\n        case .gray: return 0x2C2C2E',1)
s=s.replace('        case .green: return 0x88C16F','        case .bamboo, .mountains, .ginkgo, .tide: return 0xDEE4DF\n        case .green: return 0x88C16F',1)
s=s.replace('             .sakuraClassic, .sakuraEarthly, .sakuraInk: return true','             .sakuraClassic, .sakuraEarthly, .sakuraInk, .bamboo, .mountains, .ginkgo, .tide: return true',1)
p.write_text(s,encoding='utf8')
p=R/'SourceReadSwift/Features/Reader/ReaderPaperTexture.swift';s=p.read_text(encoding='utf8')
old='''        Image(uiImage: ReaderPaperTexture.image(background: background, night: night))
            .resizable(resizingMode: .tile)
            .allowsHitTesting(false)
            .accessibilityHidden(true)'''
new='''        if let asset = background.wallpaperAssetName {
            ReaderIllustratedBackgroundView(name: asset, paper: background.color(isNight: night))
        } else {
            Image(uiImage: ReaderPaperTexture.image(background: background, night: night))
                .resizable(resizingMode: .tile)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }'''
assert old in s;s=s.replace(old,new);p.write_text(s,encoding='utf8')
p=R/'SourceReadSwift/Features/Reader/ReaderView.swift';s=p.read_text(encoding='utf8')
s=s.replace('        .preferredColorScheme(background.isDark ? .dark : .light)','''        .task(id: backgroundRawValue) {
            guard let name = background.wallpaperAssetName else { return }
            let loaded = await ReaderIllustratedBackgroundStore.load(name)
            guard loaded != nil, !Task.isCancelled else { return }
            // Warm before versioning UIKit snapshots; otherwise a cached page
            // could keep its pre-decode blank background forever.
            backgroundWallpaperRevision = UUID()
            rebuildPagedBlocksCache()
        }
        .preferredColorScheme(background.isDark ? .dark : .light)''',1)
s=s.replace('            Text("背景颜色")','            Text("阅读背景 · 纸纹与插画")',1)
old='''                                Circle()
                                    .fill(item.color(isNight: item.isDark))
                                    .frame(width: 40, height: 40)'''
new='''                                ZStack {
                                    item.color(isNight: item.isDark)
                                    if item.hasTexture { ReaderPaperTextureView(background: item, night: item.isDark) }
                                }
                                    .frame(width: 40, height: 40)
                                    .clipShape(Circle())'''
assert old in s;s=s.replace(old,new,1);p.write_text(s,encoding='utf8')
p=R/'SourceReadSwiftTests/ReaderBackgroundPickerTests.swift';s=p.read_text(encoding='utf8').replace('XCTAssertEqual(cases.count, 14, "11 种原有外观与 3 种独立纸纹")','XCTAssertEqual(cases.count, 18, "11 种原有外观、3 种纸纹与 4 幅原创插画")');p.write_text(s,encoding='utf8')
