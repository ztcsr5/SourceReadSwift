# 1.1.7 work in progress — not released

Baseline 68b68b7abbb7bea06e7fe53d95edc89ec8ee7c79 (1.1.6 /127).
Source D:/Gemini反重力/SourceReadSwift2; evidence F:/SourceReadSwift/release-1.1.7.

## User request ledger (all pending until verified)
1. Preserve exact reading position while changing page mode.
2. Reader local-book details must use the real detail layout, not a sparse metadata form.
3. Continue 31-source comic compatibility, retain failures honestly.
4. Deepen parser compatibility with deterministic fixtures.
5. System light/dark following.
6. Dismiss proxy port number keyboard.
7. Fast TOC ascending/descending.
8. Search UI responsiveness and bounded publication.
9. Compact detail page, remove duplicate metadata/intro.
10. Balanced reader menu margins; iOS26 native glass, iOS16–25 legacy style.
11. Local website-source inference, browser session-aware; preview/test before import.
12. Configurable AI API chat + file/image/source/purification attachments. API secrets in Keychain, no implicit uploads, generated source review/test before import.
13. Useful opt-in conservative purification rules.
14. Rebuild LAN web UX, preserve auth/upload contracts.
15. Dozens of original launch-random reading notes under Settings brand.
16. Rename discovery to 寻书 and book icon.
17. Material/shape/typography themes; runtime OS capability gate, no spoofed API availability from user selection. Global collaboration includes source login center, rule playground, purification rules, and all other secondary pages (user clarification). Work in numeric order from item 1.
18. More original cute/interesting reading backgrounds.
19. Rebuild custom wallpaper editing/preview/persistence.

No minimum120fps claim. iOS16 deployment and actual runtime gates remain mandatory. Do not claim all19 complete from partial fixes.

## Current checkpoint
Item 1 code changed: capture outgoing mode's chapter/paragraph/UTF-16 anchor before rebuilding; do not overwrite restored page with paragraph mapping. Scroll bridge restores UTF-16 ranges and reports position inside a long paragraph without publishing offset-only SwiftUI state changes.
4 new regressions: 60 repeated paged switches; previous-chapter insertion/reflow; UTF-16 page boundaries; actual WebKit long-paragraph restoration/report.
First CI cce60ce: device and simulator builds passed; 1499 tests, 2 skipped, 1 failed. Real WebKit long-paragraph regression reported offset 0. Root cause: chapter heading shares flat index 0 with paragraph 0; generic querySelector selected the heading before applying character offset. Fixed positive-offset selection to .para and added trailing position publication so a short swipe cannot lose its last line. Keep the original failing assertion; rerun required.
Item 2 implemented: compact shared identity header; local details with progress/catalog/file information, existing-reader chapter callback, no recursive reader. Two mounted 320/390-width snapshot tests pending native review.
Items 3–4 partial: JSON comic image object arrays now preserve per-image headers (previous flattening discarded headers); original provided MHT recursive JSONPath→JS→image directive retained as regression fixture. Live MHT probe failed certificate-expired twice including Windows trusted roots; never disabled TLS. Not all comics claimed working; previous 31-source audit remains baseline, rerun pending.
Item 5 implemented: root system appearance uses nil preference rather than an App environment snapshot; mounted live trait-change tests pending.
Item 6 implemented: focused host/port fields, keyboard Done, interactive scroll dismissal, ungrouped numeric port; physical keyboard interaction still needs device acceptance.
Item 7 implemented: stable presentation row slots instead of moving/recreating thousands of chapter identities on sort; selection remains actual chapter.index; scroll intent targets row index. Semantic/cache tests augmented, mounted/device performance not claimed.
Item 8 implemented: streamed ranking/filter/group/aggregation off main actor; snapshot revision rejects stale/cancelled publications; Set membership replaces quadratic group deduplication; progress/failure updates batched every 400ms. Four projection/cancellation/pagination tests pending native run.
Local tree-sitter Swift syntax: no new errors; git diff --check passed. No final 1.1.7 IPA delivery yet. Next: native rerun of items 1–8, inspect item 2 snapshots, then item 9 compact remote details. Items 10–19 not started.
