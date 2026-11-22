import SwiftUI

struct EmptyStateCard: View {
    let systemImage: String
    let title: String
    let message: String
    @Environment(\.readingEdition) private var skin
    @GlassPaperFill private var cardFill

    var body: some View {
        VStack(spacing: 14) {
            if let skin, ["books.vertical", "book.closed", "book", "folder", "compass.drawing"].contains(systemImage) {
                EditionSigil(skin: skin, ink: AppTheme.accent)
                    .frame(width: 46, height: 46)
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
            }

            Text(title)
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 18, x: 0, y: 10)
    }
}
