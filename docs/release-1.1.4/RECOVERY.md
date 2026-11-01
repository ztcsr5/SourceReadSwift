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
Crash intake: D:/QQ游戏/SourceReadSwift-2026-11-01-191131.ips.
Observed: iOS17.0 / iPhone16,1 / 1.1.3 Build124 / EXC_CRASH SIGABRT.
Crash app UUID d2a714d9-b448-3f01-bd78-39712756d60c matches desktop124 IPA.
Root stack: dismantleUIViewController -> cancelInteraction -> ReaderView
handlePageInteraction -> SwiftUI -> swift_beginAccess / AccessSet::insert.
Terminal dismantle now detaches callbacks first, invalidates queued work and stops
animation without installing pending hosted pages or publishing SwiftUI state.
Reusable cancel defers its state notification until after layout; mode owner resets
the interaction gate and ended reader sessions reject late interaction callbacks.
Twelve actual-controller regressions include the real dismantle and hosted unmount
paths, queued taps/flicks, animation, callback capture release and reusable cancel.
Next: full CI, native tabs, unsigned125. Physical iOS17 retest remains pending.
