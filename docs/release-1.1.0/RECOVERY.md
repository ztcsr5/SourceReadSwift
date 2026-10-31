# 1.1.0 recovery checkpoint

- Baseline: `71156be1ac148d6328dccc2844ed2555a41313b0` (user confirms paging fixed).
- Active branch: `codex/release-1.1.0`, project `D:/Gemini反重力/SourceReadSwift2`.
- Backup: `F:/SourceReadSwift/release-1.1.0/BASELINE`, manifest `baseline.json` in its parent.
- Goal: implement the 23 requests in ISSUES.md without regressing Build119 page transactions; deliver verified 1.1.0 Build120 IPA.
- Current changes: reader indentation/quote/title/selection/menu; DOM revision + jump acknowledgement guards; TOC auto-scroll cancellation; local metadata sheet; concurrent detail phases + source identity guard; lazy search sections + correct source revision; web visible-DOM extraction and conservative content blocker; purification regex cache; theme colors; diagnostics drill-in; settings/tab polish; LAN workbench adaptive visual update.
- Added final browser-reproduced regression fix: a newer explicit TOC jump cancels old native smooth motion AND its delayed fallback, even when target equals the current position. JavaScriptCore regression added; DOM update/reset also invalidates old motion.
- Verification so far: simulator/device compilation passed at e06501b; browser light/dark/mobile, exact chapter target, revision guard, speech motion/newer explicit jump passed on current worktree. Patch/rollback drill passed before the final motion fix and must be regenerated.
- Next: final commit native compile/test (all tests, retain fit/conservation matrix); fix failures, package latest same-commit IPA and evidence. Issue ledger and device acceptance are written. iOS16 runtime behavior not yet verified.
- No claim of device fix until actual device evidence; Windows has no local Xcode.
