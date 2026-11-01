# 1.1.5 / Build126 — Main-page density

- Baseline: 08b9e4a35671ed3a1eaf3a58369a1c60fbfd536c (1.1.4/125).
- Branch: codex/release-1.1.5.
- Evidence: F:/SourceReadSwift/release-1.1.5; pristine tracked snapshot in BASELINE.
- Goal: reduce duplicated chrome/padding, oversized cards and diagnostic clutter without shrinking tap targets or touching reader typography/pagination.
- Changes: shared 16pt page / 12pt card / 14pt section spacing; content-sized continue card; inline home/settings titles; settings groups consolidated, performance moved to a linked page; source quick actions adapt to width and explanatory prose collapses; book-detail duplicate 96pt tail removed; legacy tab vertical inset reduced, native tab behavior unchanged.
- Additional user request: sorting a TOC goes to its new first visible row, not back to the current chapter. TOC list identity changes without animation; forward/reverse projections cached together. Only TOC chrome/cache changed, not page rendering.
- Source organization: persistent top/normal/bottom partitions, custom drag order plus name/enabled/weight sorting; existing/imported and custom groups, filtering, batch assignment, create/rename/delete. Metadata lives in the atomic source snapshot and backups independently of parser rules; old snapshots default to empty preferences. Test restart, reimport, restore, filtered dragging and failed-save semantics.
- Validation: AppLayoutDensityTests measurements and mounted screenshot attachments at 320/390 widths, dark and accessibility text; full XCTest plus native iOS26 tab/teardown regressions. Physical iOS16/17 device acceptance remains separate.
- Next: compile/test on both CI SDKs, export/inspect screenshot attachments, package unsigned IPA only from the passing commit. Never overwrite the preserved 1.1.4/125 IPA.
