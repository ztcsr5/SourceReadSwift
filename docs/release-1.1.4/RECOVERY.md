# 1.1.4 / Build125 — menu edge exit and slower auto-scroll

Baseline: d8c3a1f0133b19014b9f5af983d16df9f0fa8985, 1.1.3/124 preserved.
Evidence: F:/SourceReadSwift/release-1.1.4/. Copy-first snapshot saved.
Final user direction overrides the initial assumption: first reveal reader menu,
then swipe from LEFT edge to RIGHT to exit. Menu-hidden page gestures unchanged.
Reader-only UIKit screen-edge recognizer, dynamic descendant priority, no global
navigation pop unlock. Settings/covers disable the exit gesture. Normal dismiss
retains the existing session persistence and tab restoration paths.
Auto-scroll: shared max60 seconds for slider/buttons/runtime clamp. Preserve saved
user delay; editing while active cancels captured old wait and restarts new interval.
Next: policy and hosted bridge tests, full CI, native tabs and unsigned IPA.
