import SwiftUI

/// A visual identity with the same palette and wording in the lookbook and on the bookshelf.
enum AtmosphericThemeSignature: String {
    case ink, jianghu, sky, journal

    init?(theme: AppVisualTheme) {
        switch theme {
        case .shuimo: self = .ink
        case .wuxia: self = .jianghu
        case .anime: self = .sky
        case .kawaii: self = .journal
        default: return nil
        }
    }

    var volume: String {
        switch self {
        case .ink: return "壹 · 山水志"
        case .jianghu: return "贰 · 山河录"
        case .sky: return "叁 · 晴空号"
        case .journal: return "肆 · 手账集"
        }
    }

    var caption: String {
        switch self {
        case .ink: return "山色淡，落款红"
        case .jianghu: return "竹影深，旧卷有金"
        case .sky: return "把晴空与晚星翻成两页"
        case .journal: return "留白、贴签，以及甜一点的页角"
        }
    }

    var imageName: String {
        switch self {
        case .ink: return "seal"
        case .jianghu: return "bookmark.fill"
        case .sky: return "sparkle"
        case .journal: return "heart.fill"
        }
    }

    var artworkAlignment: Alignment {
        switch self {
        case .ink: return .bottomTrailing
        case .jianghu: return .topTrailing
        case .sky: return .center
        case .journal: return .bottom
        }
    }
}

struct AtmosphericThemePlate: View {
    let theme: AppVisualTheme
    let signature: AtmosphericThemeSignature
    let night: Bool
    let isSelected: Bool
    @Environment(\.colorSchemeContrast) private var contrast

    private var paper: Color { Color(hex: night ? theme.darkCardHex : theme.cardHex) }
    private var ink: Color { Color(hex: night ? 0xF7F6F5 : 0x1F2428) }
    private var accent: Color { Color(hex: night ? theme.darkAccentHex : theme.accentHex) }
    private var trim: Color { Color(hex: night ? theme.darkSecondaryHex : theme.secondaryHex) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: signature.artworkAlignment) {
                paper
                if contrast != .increased, let art = theme.atmosphericPaperAsset(isDark: night) {
                    ReaderIllustratedBackgroundView(name: art, paper: paper)
                        .id(art)
                }
                badge
                    .padding(12)
            }
            .frame(height: 108)
            .clipped()
            .accessibilityHidden(true)

            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(theme.title).font(theme.titleFont(size: 20, weight: .semibold))
                    Text(signature.caption).font(.subheadline).foregroundStyle(ink.opacity(0.77))
                }
                Spacer(minLength: 6)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .imageScale(.large)
                    .foregroundStyle(isSelected ? accent : ink.opacity(0.45))
                    .accessibilityHidden(true)
            }
            .padding(12)
        }
        .foregroundStyle(ink)
        .background(paper)
        .clipShape(RoundedRectangle(cornerRadius: theme.radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: theme.radius, style: .continuous)
                .strokeBorder(isSelected ? accent : ink.opacity(0.14), lineWidth: isSelected ? 2 : 1)
                .allowsHitTesting(false)
        }
        .contentShape(RoundedRectangle(cornerRadius: theme.radius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var badge: some View {
        Label(signature.volume, systemImage: signature.imageName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(paper, in: RoundedRectangle(cornerRadius: signature == .jianghu ? 4 : 8))
            .overlay {
                RoundedRectangle(cornerRadius: signature == .jianghu ? 4 : 8)
                    .strokeBorder(trim.opacity(0.68), lineWidth: 1)
            }
    }
}

struct AtmosphericBookshelfLine: View {
    let theme: AppVisualTheme
    let signature: AtmosphericThemeSignature
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: signature.imageName).foregroundStyle(AppTheme.accent)
            Text(signature.volume)
                .font(theme.titleFont(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
            Rectangle()
                .fill(AppTheme.secondaryAccent.opacity(scheme == .dark ? 0.56 : 0.32))
                .frame(height: 1)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(AppTheme.card.opacity(0.88), in: RoundedRectangle(cornerRadius: 4))
        .accessibilityHidden(true)
    }
}
