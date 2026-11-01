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
Local tree-sitter Swift syntax: no new errors; git diff --check passed. Native compile and XCTest pending. No device acceptance or final 1.1.7 IPA delivery yet.
Next: CI item 1, then compact proper local/remote detail layout for item 2, retaining the non-recursive reader boundary.
