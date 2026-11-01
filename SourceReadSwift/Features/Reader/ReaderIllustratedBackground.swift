import SwiftUI
import UIKit

enum ReaderIllustratedBackgroundStore {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 4
        cache.totalCostLimit = 32 * 1024 * 1024
        return cache
    }()
    static func cached(_ name: String) -> UIImage? { cache.object(forKey: name as NSString) }
    static func load(_ name: String) async -> UIImage? {
        if let hit = cached(name) { return hit }
        return await Task.detached(priority: .userInitiated) {
            guard let raw = UIImage(named: name) else { return nil as UIImage? }
            let decoded = raw.preparingForDisplay() ?? raw
            let cost = Int(decoded.size.width * decoded.size.height * decoded.scale * decoded.scale * 4)
            cache.setObject(decoded, forKey: name as NSString, cost: cost)
            return decoded
        }.value
    }
}

struct ReaderIllustratedBackgroundView: View {
    let name: String
    let paper: Color
    @State private var image: UIImage?

    init(name: String, paper: Color) {
        self.name = name
        self.paper = paper
        _image = State(initialValue: ReaderIllustratedBackgroundStore.cached(name))
    }
    var body: some View {
        ZStack {
            paper
            if let image { ReaderWallpaperView(image: image, fillMode: .fill) }
        }
        .task(id: name) {
            let loaded = await ReaderIllustratedBackgroundStore.load(name)
            guard !Task.isCancelled else { return }
            image = loaded
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
