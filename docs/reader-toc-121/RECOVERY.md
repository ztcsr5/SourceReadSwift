# Reader TOC / Build 121

- Active project: D:/Gemini反重力/SourceReadSwift2, branch codex/release-1.1.0.
- Goal: fix slow TOC scrolling / delayed chapter selection shown in the 67.76 s user video, group app themes under Settings > 外观, preserve paging fixes and iOS 16 deployment.
- Baseline: de82995c7c9848f48e5c242508b5d82c410be8c2 (1.1.0 / 120).
- Copy-first baseline: F:/SourceReadSwift/reader-toc-121/BASELINE; baseline.json records hashes. Previous release artifacts are untouched.
- Observed: video 20–24 s and 60–63 s still shows the prior chapter after dismissing the TOC. TOC has 849 chapters. No physical-device profiling available.
- Observed code: row canJump rescans full chapter indices; BookDetail list refilters per row and has variable row count; progress encodes full shelf/local content on main actor; distant network jump resolves against an old page map before deferred rebuild.
- Modified: single-pass TOC snapshots, COW-aware filter memoization, one stable detail row, small synchronous progress sidecar, background target pagination with request/generation/layout/content guards and explicit anchor commit, pending-jump retention/feedback, dedicated AppearanceSettingsView. Build 121, marketing 1.1.0, iOS minimum 16.0.
- Next: native compile and full XCTest via same-commit iOS/Unsigned IPA CI; inspect failures, package only after both green; verify diff/rollback in scratch and IPA plist/hash. Device FPS and iOS16 runtime remain unmeasured.
- Additional observed bottleneck: ChapterContentCacheStore also rewrote up to 500 cached chapters synchronously on each save/LRU touch. Those immutable snapshots now write in order on a shared background disk queue. Reload is a queue barrier; clear cannot be overtaken by older queued writes. Explicit remote jumps cancel speculative old-cursor prefetch rather than scheduling more of it.
