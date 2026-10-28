import Foundation

/// Locates test fixtures in the checked-out source tree.
///
/// The fixtures are multi-megabyte corpora (114 search pages, 97 chapter
/// lists). Copying them into the `.xctest` bundle made XcodeGen emit two copy
/// commands for every file, and two `manifest.json` files could not coexist at
/// the bundle root. Reading them from `#filePath` keeps the bundle small and
/// makes the lookup independent of how Xcode lays out resources.
enum TestFixtureSupport {
    static var fixturesDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
    }

    /// Directory for a named corpus, e.g. `rows-corpus` or `toc-corpus`.
    static func directory(_ name: String) -> URL {
        fixturesDirectory.appendingPathComponent(name, isDirectory: true)
    }

    /// Mirrors `Bundle.url(forResource:withExtension:subdirectory:)` for the
    /// `Fixtures` subtree. `subdirectory` may be `Fixtures`, `Fixtures/rows-corpus`
    /// or a plain corpus name; the `Fixtures` component is implicit.
    static func url(name: String, extension ext: String, subdirectory: String? = nil) -> URL? {
        var base = fixturesDirectory
        if let subdirectory {
            for component in subdirectory.split(separator: "/") where component != "Fixtures" {
                base.appendPathComponent(String(component), isDirectory: true)
            }
        }
        let candidate = base.appendingPathComponent("\(name).\(ext)")
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }
}
