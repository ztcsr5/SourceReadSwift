import SwiftUI

/// A single quiet system material; native tab chrome owns its own Liquid Glass.
struct BrandGlass<Outline: InsettableShape>: View {
    let outline: Outline
    @AppStorage(AppVisualTheme.selectionKey) private var themeRaw = AppVisualTheme.initialSelection.rawValue
    @Environment(\.accessibilityReduceTransparency) private var reducesTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private var theme: AppVisualTheme { AppVisualTheme(rawValue: themeRaw) ?? .classic }

    var body: some View {
        surface
            .overlay(outline.strokeBorder(contrast == .increased ? theme.secondaryInk : theme.controlBorder,
                                          lineWidth: contrast == .increased ? 1 : 0.75))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    @ViewBuilder private var surface: some View {
        if reducesTransparency || contrast == .increased {
            outline.fill(AppTheme.card)
        } else {
            // Liquid Glass's projected shadow is clipped by the book pager.
            // Keep stationary cards clean and let the native tab own the depth.
            outline.fill(.thinMaterial).overlay(outline.fill(AppTheme.card.opacity(0.32)))
        }
    }
}

/// Theme-aware treatment for independent filters, not primary buttons.
struct BrandFilterFinish: ViewModifier {
    let isSelected: Bool
    let legacyFill: Color
    @AppStorage(AppVisualTheme.selectionKey) private var themeRaw = AppVisualTheme.initialSelection.rawValue
    @AppMotion private var motion
    private var theme: AppVisualTheme { AppVisualTheme(rawValue: themeRaw) ?? .classic }

    func body(content: Content) -> some View {
        content
            .foregroundStyle(isSelected ? (theme.usesNeutralGlass ? AppTheme.accent : .white) : theme.primaryInk)
            .background {
                Capsule().fill(theme.usesNeutralGlass ? (isSelected ? theme.controlFill : .clear)
                    : (isSelected ? AppTheme.accent : legacyFill))
            }
            .overlay {
                Capsule().strokeBorder(theme.usesNeutralGlass ? theme.controlBorder : .primary.opacity(isSelected ? 0 : 0.06),
                                       lineWidth: 0.75).allowsHitTesting(false)
            }
            .animation(motion.animation(.navigation), value: isSelected)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
