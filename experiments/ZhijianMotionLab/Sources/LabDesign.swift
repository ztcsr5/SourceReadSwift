import SwiftUI

enum LabPalette {
    static let ink = Color(red: 0.10, green: 0.12, blue: 0.18)
    static let paper = Color(red: 0.97, green: 0.965, blue: 0.98)
    static let midnight = Color(red: 0.035, green: 0.07, blue: 0.085)
    static let accent = Color(red: 0, green: 0.48, blue: 1)
    static let gold = Color(red: 0.91, green: 0.77, blue: 0.53)
    static let navigation = Animation.spring(response: 0.65, dampingFraction: 0.87)
    static let feedback = Animation.spring(response: 0.32, dampingFraction: 0.78)
}

struct LabPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduced
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduced ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.76 : 1)
            .animation(reduced ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

/// Original two-page mark, independent of Rex branding.
struct LabMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).frame(width: 30, height: 48).rotationEffect(.degrees(-25)).offset(x: -12)
            RoundedRectangle(cornerRadius: 8).frame(width: 30, height: 48).rotationEffect(.degrees(25)).offset(x: 12)
            Capsule().frame(width: 4, height: 38).offset(y: 7).blendMode(.destinationOut)
        }
        .compositingGroup().frame(width: 78, height: 74).accessibilityLabel("纸间，翻开新的世界")
    }
}

struct LabGlass<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reducedTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    var isDark = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        content().background {
            if reducedTransparency || contrast == .increased {
                Capsule().fill(isDark ? LabPalette.midnight : Color.white)
            } else { Capsule().fill(.regularMaterial) }
        }
        .overlay(Capsule().stroke(.white.opacity(isDark ? 0.16 : 0.7), lineWidth: 0.8))
    }
}

struct LabTicketShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path(roundedRect: rect, cornerRadius: 20)
        let y = rect.height * 0.73
        path.addEllipse(in: CGRect(x: -9, y: y - 9, width: 18, height: 18))
        path.addEllipse(in: CGRect(x: rect.width - 9, y: y - 9, width: 18, height: 18))
        return path
    }
}

struct LabTicket: View {
    let book: LabBook
    var quote: String? = nil
    var serial = "01"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                LabCover(book: book).frame(width: 62, height: 88)
                VStack(alignment: .leading, spacing: 9) {
                    Text("纸间藏书票  /  \(serial)").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1)
                    Text(book.title).font(.system(.title3, design: .serif).weight(.semibold))
                    Text(quote ?? book.tagline).font(.footnote).lineLimit(3)
                }
                Spacer(minLength: 0)
            }
            Line().stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 4])).foregroundStyle(LabPalette.ink.opacity(0.18)).frame(height: 1)
            HStack {
                Text(quote == nil ? "ORIGINAL STORY · 演示藏书票" : "SAVED BY YOU · 我的书笺")
                    .font(.system(size: 8, weight: .medium, design: .monospaced)).tracking(1)
                Spacer()
                Image(systemName: "bookmark.fill").font(.caption)
            }
        }
        .foregroundStyle(LabPalette.ink).padding(20)
        .background(Color(red: 0.99, green: 0.98, blue: 0.94))
        .clipShape(LabTicketShape(), style: FillStyle(eoFill: true))
        .shadow(color: LabPalette.ink.opacity(0.13), radius: 16, x: 0, y: 12)
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path { Path { $0.move(to: .zero); $0.addLine(to: CGPoint(x: rect.width, y: 0)) } }
    }
}
