import Foundation

/// Chooses when the directory can be loaded independently from book metadata.
enum BookDetailDirectoryPolicy {
    static func waitsForDetail(_ source: BookSource) -> Bool {
        if source.hasDynamicMediaType { return true }
        guard let rules = source.ruleBookInfo else { return false }
        return rules.raw?.nilIfEmpty != nil || BookDetailParser.directoryRuleKeys.contains {
            rules.fields[$0]?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty != nil
        }
    }

    static func destinationChanged(from original: BookDetail, to resolved: BookDetail, source: BookSource) -> Bool {
        directoryAddress(for: original) != directoryAddress(for: resolved)
            || source.resolvingMediaKind(original.mediaKind).sourceKind != source.resolvingMediaKind(resolved.mediaKind).sourceKind
    }

    private static func directoryAddress(for detail: BookDetail) -> String {
        detail.tocUrl?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? detail.bookUrl
    }
}
