import SwiftUI

/// Bundled reference metadata, never a live listing or a playback entitlement.
struct ReferenceMedia: Decodable, Identifiable, Hashable {
    let id: Int
    let title: String
    let poster: String
    let backdrop: String
    let logo: String
    let year: String
    let release: String
    let genre: String
    let overview: String
    let rating: String

    static let samples: [ReferenceMedia] = {
        guard let url = Bundle.main.url(forResource: "ReferenceMedia", withExtension: "json") else {
            preconditionFailure("Missing bundled visual-reference catalog ReferenceMedia.json")
        }
        do { return try JSONDecoder().decode([ReferenceMedia].self, from: Data(contentsOf: url)) }
        catch { preconditionFailure("Cannot decode bundled visual-reference catalog: \(error)") }
    }()

    static func item(_ id: Int) -> ReferenceMedia {
        samples.first { $0.id == id } ?? samples[0]
    }
}

@MainActor final class ReferenceShelf: ObservableObject {
    @Published private(set) var saved: Set<Int>
    private let preferences: UserDefaults
    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
        saved = Set(preferences.array(forKey: "lab.reference.saved") as? [Int] ?? [])
    }
    func toggle(_ item: ReferenceMedia) {
        if saved.contains(item.id) { saved.remove(item.id) } else { saved.insert(item.id) }
        preferences.set(saved.sorted(), forKey: "lab.reference.saved")
    }
}

struct ReferenceImage: View {
    @EnvironmentObject private var artwork: LabArtwork
    let name: String
    var fits = false
    var body: some View {
        GeometryReader { proxy in
            if let image = artwork.image(name) {
                Image(uiImage: image).resizable()
                    .aspectRatio(contentMode: fits ? .fit : .fill)
                    .frame(width: proxy.size.width, height: proxy.size.height).clipped()
            } else { (name.hasPrefix("RefTitle") ? Color.clear : Color.gray.opacity(0.12)) }
        }.accessibilityHidden(true)
    }
}

struct ReferencePoster: View {
    let item: ReferenceMedia
    var radius: CGFloat = 9
    var body: some View {
        ReferenceImage(name: item.poster)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .accessibilityLabel(item.title)
    }
}
