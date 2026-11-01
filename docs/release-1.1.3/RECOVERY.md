# 1.1.3 / Build124 — scroll chapter header

Baseline:0785bf059059fabf9e98775369e9bd64dff893b6 (1.1.2/123 preserved).
Evidence: F:/SourceReadSwift/release-1.1.3/; baseline copied before edits.
Only scroll reading chrome changes: small left chapter title on opaque theme paper,
always present by default even with bottom-only status. Explicit hidden-heading and
top clock/battery preferences remain respected. Shared geometry protects safe area,
chapter band and body gap with the same initial body inset. No pagination changes.
ImageRenderer pixel regression checks that underlying red/blue body layers cannot
bleed through the actual SwiftUI component. Geometry and preference cases added.
Next: legacy full tests, native iOS26 tab suite, device build and IPA verification.
