import SwiftUI
import UIKit

enum QuoteCardTheme: String, CaseIterable, Identifiable {
    case parchment = "素笺"
    case obsidian = "极夜"
    case bamboo = "竹青"
    case aurora = "晨曦"

    var id: String { rawValue }

    var backgroundColor: Color {
        switch self {
        case .parchment: return Color(red: 0.96, green: 0.94, blue: 0.90)
        case .obsidian: return Color(red: 0.11, green: 0.11, blue: 0.13)
        case .bamboo: return Color(red: 0.92, green: 0.95, blue: 0.91)
        case .aurora: return Color(red: 0.95, green: 0.91, blue: 0.93)
        }
    }

    var textColor: Color {
        switch self {
        case .parchment: return Color(red: 0.20, green: 0.18, blue: 0.16)
        case .obsidian: return Color(red: 0.94, green: 0.94, blue: 0.96)
        case .bamboo: return Color(red: 0.16, green: 0.25, blue: 0.18)
        case .aurora: return Color(red: 0.26, green: 0.18, blue: 0.24)
        }
    }

    var secondaryTextColor: Color {
        switch self {
        case .parchment: return Color(red: 0.48, green: 0.44, blue: 0.40)
        case .obsidian: return Color(red: 0.65, green: 0.65, blue: 0.68)
        case .bamboo: return Color(red: 0.38, green: 0.48, blue: 0.40)
        case .aurora: return Color(red: 0.52, green: 0.42, blue: 0.48)
        }
    }

    var accentColor: Color {
        switch self {
        case .parchment: return Color(red: 0.72, green: 0.42, blue: 0.22)
        case .obsidian: return Color(red: 0.85, green: 0.72, blue: 0.48)
        case .bamboo: return Color(red: 0.30, green: 0.58, blue: 0.36)
        case .aurora: return Color(red: 0.80, green: 0.45, blue: 0.60)
        }
    }

    var borderColor: Color {
        switch self {
        case .parchment: return Color.black.opacity(0.08)
        case .obsidian: return Color.white.opacity(0.12)
        case .bamboo: return Color(red: 0.30, green: 0.58, blue: 0.36).opacity(0.15)
        case .aurora: return Color(red: 0.80, green: 0.45, blue: 0.60).opacity(0.15)
        }
    }
}

struct QuoteCardView: View {
    @Environment(\.dismiss) private var dismiss
    let quote: String
    let bookTitle: String
    let author: String
    var chapterTitle: String? = nil

    @State private var selectedTheme: QuoteCardTheme = .parchment
    @State private var toastMessage: String? = nil
    @State private var showShareSheet = false
    @State private var renderedImageToShare: UIImage? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Card Preview
                ScrollView {
                    VStack {
                        cardPreview
                            .padding(.vertical, 16)
                            .padding(.horizontal, 20)
                    }
                    .frame(maxWidth: .infinity)
                }

                // Theme Switcher & Actions
                VStack(spacing: 16) {
                    themePicker

                    HStack(spacing: 14) {
                        Button {
                            copyCardImage()
                        } label: {
                            Label("复制图片", systemImage: "doc.on.doc")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            saveCardToAlbum()
                        } label: {
                            Label("保存相册", systemImage: "arrow.down.to.line")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            shareCardImage()
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.subheadline.weight(.semibold))
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                }
                .background(.ultraThinMaterial)
            }
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("金句卡片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .overlay {
                if let toast = toastMessage {
                    Text(toast)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.8), in: Capsule())
                        .shadow(radius: 6)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(100)
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let img = renderedImageToShare {
                    ShareSheet(activityItems: [img])
                }
            }
        }
    }

    // MARK: - Card Component for rendering & preview

    private var cardPreview: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Opening quotation mark
            Text("“")
                .font(.system(size: 52, weight: .bold, design: .serif))
                .foregroundStyle(selectedTheme.accentColor)
                .frame(height: 32, alignment: .bottom)

            // Quote text
            Text(quote.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.system(size: 19, weight: .regular, design: .serif))
                .lineSpacing(10)
                .foregroundStyle(selectedTheme.textColor)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 2)

            // Closing quotation mark
            HStack {
                Spacer()
                Text("”")
                    .font(.system(size: 52, weight: .bold, design: .serif))
                    .foregroundStyle(selectedTheme.accentColor)
                    .frame(height: 32, alignment: .top)
            }

            Divider()
                .overlay(selectedTheme.borderColor)

            // Book Details & App Footer
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("《\(bookTitle)》")
                        .font(.system(size: 16, weight: .bold, design: .serif))
                        .foregroundStyle(selectedTheme.textColor)

                    HStack(spacing: 6) {
                        Text(author)
                        if let chapter = chapterTitle, !chapter.isEmpty {
                            Text("·")
                            Text(chapter)
                        }
                    }
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(selectedTheme.secondaryTextColor)
                    .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text(Date().formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(selectedTheme.secondaryTextColor)

                    Text("纸间 · 静心阅读")
                        .font(.system(size: 11, weight: .semibold, design: .serif))
                        .foregroundStyle(selectedTheme.accentColor)
                }
            }
        }
        .padding(28)
        .frame(maxWidth: 360)
        .background(selectedTheme.backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(selectedTheme.borderColor, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 16, x: 0, y: 8)
    }

    // MARK: - Theme Picker

    private var themePicker: some View {
        HStack(spacing: 20) {
            ForEach(QuoteCardTheme.allCases) { theme in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTheme = theme
                    }
                } label: {
                    VStack(spacing: 6) {
                        Circle()
                            .fill(theme.backgroundColor)
                            .frame(width: 34, height: 34)
                            .overlay(
                                Circle()
                                    .stroke(theme.borderColor, lineWidth: 1.5)
                            )
                            .overlay(
                                Circle()
                                    .stroke(AppTheme.accent, lineWidth: selectedTheme == theme ? 2.5 : 0)
                                    .padding(-4)
                            )
                        Text(theme.rawValue)
                            .font(.caption2.weight(selectedTheme == theme ? .bold : .regular))
                            .foregroundStyle(selectedTheme == theme ? Color.primary : Color.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Rendering & Actions

    @MainActor
    private func renderCardImage() -> UIImage? {
        let renderer = ImageRenderer(content: cardPreview)
        renderer.scale = UIScreen.main.scale
        return renderer.uiImage
    }

    private func copyCardImage() {
        guard let image = renderCardImage() else {
            showToast("生成图片失败")
            return
        }
        UIPasteboard.general.image = image
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        showToast("已复制到剪贴板")
    }

    private func saveCardToAlbum() {
        guard let image = renderCardImage() else {
            showToast("生成图片失败")
            return
        }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        showToast("已保存到系统相册")
    }

    private func shareCardImage() {
        guard let image = renderCardImage() else {
            showToast("生成图片失败")
            return
        }
        renderedImageToShare = image
        showShareSheet = true
    }

    private func showToast(_ message: String) {
        withAnimation {
            toastMessage = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                if toastMessage == message {
                    toastMessage = nil
                }
            }
        }
    }
}
