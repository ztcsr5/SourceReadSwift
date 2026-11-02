import Foundation

/// File-provider type labels are advisory; validate the actual selection at the IO boundary.
enum FontImportPolicy {
    static let maximumBytes = 64 * 1024 * 1024
    static let extensions: Set<String> = ["ttf", "otf", "ttc", "otc", "woff"]
    static func validate(suffix: String, bytes: Int) throws {
        guard extensions.contains(suffix.lowercased()) else {
            throw NSError(domain: "FontImport", code: 1, userInfo: [NSLocalizedDescriptionKey: "请选择 TTF、OTF、TTC 或 OTC 字体文件，不要选择压缩包。"])
        }
        guard bytes > 0, bytes <= maximumBytes else {
            throw NSError(domain: "FontImport", code: 2, userInfo: [NSLocalizedDescriptionKey: "字体文件必须非空且不超过 64 MB。"])
        }
    }
}
