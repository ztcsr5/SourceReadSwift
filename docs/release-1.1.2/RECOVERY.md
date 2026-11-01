# 1.1.2 / Build123 — iOS26 tab chrome hotfix

Baseline: 272b38ae603abe0552c4b5c28e2246f377aa781d, released 1.1.1/122 preserved.
Evidence/rollback baseline: F:/SourceReadSwift/release-1.1.2/
Screenshots show empty native accessory and root tabs leaking into local reading.
Removed native bottom accessory; conditional safe-area audio panel keeps tab/navigation identity.
Native toolbar visibility is applied in tab children; reader/gateway/hideRootTabBar declare
hidden tab-bar preference at the destination itself, not only outside TabView.
Do not change pagination, typography or chapter-loading logic for this hotfix.
Next: full old-system regression plus iOS26 hosted-tab runtime tests, device build, IPA verification.
Physical iPhone appearance still requires device acceptance. No agents delegated.
