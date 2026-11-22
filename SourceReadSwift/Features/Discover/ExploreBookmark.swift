import CryptoKit
import Foundation

/// A personal shortcut names a column; only the current source menu supplies executable routes.
struct ExploreBookmark: Codable, Hashable, Identifiable {
    let sourceID: String
    let title: String
    let group: String?
    private let routeDigest: Data?
    var id: Self { self }

    init(sourceID: String, category: ExploreCategory, in categories: [ExploreCategory]) {
        self.sourceID = sourceID
        title = category.title
        group = category.group
        let ambiguous = categories.contains { $0.title == category.title && $0.group == category.group && $0.url != category.url }
        routeDigest = ambiguous ? Self.digest(category.url) : nil
    }

    func resolve(in categories: [ExploreCategory]) -> ExploreCategory? {
        var match: ExploreCategory?
        for category in categories where category.title == title && category.group == group {
            if let routeDigest, routeDigest != Self.digest(category.url) { continue }
            guard match == nil else { return nil }
            match = category
        }
        return match
    }

    private static func digest(_ route: String) -> Data { Data(SHA256.hash(data: Data(route.utf8))) }
}
