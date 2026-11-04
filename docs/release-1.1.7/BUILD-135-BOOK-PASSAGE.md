# Build 135 · book stage and native return

Baseline f69bd4231efaf0c2906a0c0172647a4010febd27 (Build134), independent
codex/build135-book-stage-continuity branch. Existing dirty documents and
baseline patch saved at F:/SourceReadSwift/book-passage-135/baseline.

## Acceptance, not just implementation
1. Keep the overhanging book; replace the pillow-like flat card with a recessed
   back plane, lit shelf surface and a separate front edge. Preserve a normal
   280–290pt envelope and first-screen shelf. The book itself uses narrow page
   edges and tight corners. Same book/theme must be compared to Build134.
2. The current reader locks native pop at all times; its fallback edge only
   dismisses after touch-up. Let book entry paths use the native edge return
   while the reader menu is visible, not while paging/selection/settings.
   Keep the legacy/non-book fallback. Never replace the navigation delegate.
3. One destination-owned opening book, spinner only after arrival. No fixed
   wait before the real saved cursor is ready. On native pop, a book carrier
   fades over the still-live reading surface using transitionCoordinator.
   UIKit owns progress and reversal; clean up on completion/cancellation.
   No snapshot of the user's prose, per-frame SwiftUI publisher or new decoder.
4. Real UI cancel AND finish, with native log pairs requiring interactive=1.
   Existing assertions remain; no pass based on a touch-up-triggered dismissal.
   Show the real recording, not a conceptual simulation. If it fails, fix or
   withdraw that part rather than declare the interaction accepted.

Local: 53 Python tests, changed Swift grammar and workflow YAML passed.
Native SDK compilation, mounted layout and real UI are pending. 13Pro frame
timing / tactile quality remain device acceptance items, not simulator FPS.

Scope: desk and entry/return only. Search visual, source engine, pagination,
cursor format and global themes remain unchanged. Restore guard, original
Build134 artifacts, Songti fallback and high-raster pipeline retained.
