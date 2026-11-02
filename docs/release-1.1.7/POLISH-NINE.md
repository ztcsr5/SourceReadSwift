# 1.1.7 · build 130 candidate · nine-point closeout

Baseline: ad814912685b53ce7c4b4262598e047c168bec55 / unsigned build 129, not full-CI accepted. Existing work and build 128 retained. Startup experiment remains paused. Item12 is USER MANUAL; no gateway traffic.

Device correction from user: iPhone 13 **Pro**, reported iOS 27.0.1, subjective frame pacing (not an instrumented “under100fps” measurement). The device is ProMotion-capable; 120Hz is a hardware ceiling, not proof of every presented frame. CI currently covers simulator runtimes, not that physical phone/OS.

| # | Scope | Source work / evidence | Acceptance still required |
|---|---|---|---|
| 1 | Slide and app hitches | Single coherent progress publication; no repeated idle page installation/publication; unchanged Web style compares typed payload instead of MB-sized JSON signatures | Native regression plus physical frame-time A/B |
| 2 | Current-reading desk | Compact horizontal jacket, theme-owned paper and restrained cover wash, static spine/page edges/shadow, separate cover/text arrival | Width 320/390/430, all themes, light/dark/accessibility screenshots |
| 3 | Interaction vocabulary | Shared press/arrival/navigation/expansion/background timing; live glass reserved for explicit floating controls | Mounted flow and reduced-motion verification; physical subjective review |
| 4 | Book details | Editorial book dossier, dimensional jacket, readable title/author/source, themed wash, synopsis expansion; native hero/back retained | Native snapshots, interactive return/cancel on phone |
| 5 | Overall performance | Coherent store writes, less bridge allocation/backdrop sampling, no periodic diagnostic defaults writes during reading | Instruments Animation Hitches + Time Profiler on iPhone13Pro; no fabricated FPS |
| 6 | Font selection | Native as-copy picker, immediate busy acknowledgement, coordinated copy/descriptor parse/registration off main, success/error feedback | Real bundled-font async IO test; user file-provider pick/apply/relaunch |
| 7 | Motion continuity | Scoped root chrome animation, cache hit avoids nil/image flash, separate arrivals, distance/velocity-aware page settle | Rapid turns/cancel/resize/teardown regression; phone gesture interruption |
| 8 | Missing local cover | Opaque semantic theme jacket and independent ink; no inherited black symbol/transparent primary fill; title fallback | Nil/invalid/file covers across nine themes and both appearances |
| 9 | Cross-cutting completeness | Retain failing logs, exact identities/theme compatibility, no weakened tests, add boundary/snapshot checks, rerun complete native gates | Full green exact-head CI + copied IPA hash + physical checklist |

## Checkpoint
- Red regression commit ed91ad2: compact-height and idle-callback tests added before fixes; native26 ran152 tests/7 assertion failures: idle interaction publication32 vs2, current card457pt vs≤280pt at three widths, and three already-known theme-count failures. Red logs retained under F:/SourceReadSwift/reader-motion-117/ed91ad2*/; no relaxed assertions.
- Local Swift syntax parse: 17 changed/new Swift files, zero parse errors at initial checkpoint. Native SDK compilation/tests are not available on Windows and are not represented by this parse check.
- Source candidate implemented; build130 native gates pending. No build130 delivery or completion/FPS/device acceptance claim.

## Physical run (must not be replaced with simulator averages)
1. Same iPhone13Pro, same OS/theme/text/brightness; Low Power Mode off, Accessibility → Motion → Limit Frame Rate off, device cool. Record conditions, do not force unsupported cadence or run permanent display links.
2. Settings → 全应用帧时间: record separate30-second runs for continuous slide turns, shelf scroll and shelf→detail→reader→interactive back. Keep both baseline/candidate reports; the display-link report measures main-run-loop cadence, not GPU presentation.
3. Capture Animation Hitches/Time Profiler on the actual phone when a Mac is available. Compare long-frame counts, P95/P99, gesture pauses and thermal state. Confirm no chapter/character position loss after twenty rapid turns, cancellations and reader-mode switches.
4. In both Settings and Reader font entry points: pick the same TTF from On My iPhone and iCloud/provider, verify busy→named success, changed preview/body, independent chapter title, relaunch persistence. Test cancel, invalid file, duplicate and collection font. Import errors must preserve old selection.
5. Check missing cover and 404/decode failure in light/dark/all nine themes; no black inherited symbol. Check320pt/large text and Reduce Motion; no clipped title, dead menu, duplicate hero source or animation-delayed input.

## Implementation checkpoint before native candidate
- Production source changes only; no paused experiment edits. No new packages/assets/download dependencies. Classic compact toggle and original native tab strategy retained.
- Live material is now opt-in for floating controls; list cards keep opaque theme paper. Cover cache hits avoid a nil/image flash. Missing-cover jacket owns paper/ink independently of link tint.
- Font CSS uses a local, filename-validated readerfont scheme with off-main IO and actual WebContent font-load regression, rather than base64 bridge copies. CoreText descriptors support collection fonts. Native picker completes dismissal before named success/error feedback.
- Whole-reader page interaction and position semantics retained; new idle-update/position-publication tests lock bounded invalidation. Distance-aware settle does not change commit/cancel ownership.
- Native source candidate will include exact nine-theme assertions (not a relaxed >= check) and WebKit failure diagnostics without skipping or increasing the existing position-test timeout. Regular Intel job budget45min because build+full suite exceeded30min; individual assertions retained.
- Local preflight:29 Swift edits/new files parsed with no new syntax errors; YAML and git diff --check passed. Parsing is not SDK typechecking or XCTest.

## Native41b5a14 regression results (not acceptance)
- Unsigned device build passed. Regular simulator executed1580 tests/2skipped/3assertion failures, solely in new font-boundary checks: canonical directoryURL marker comparison and CoreText duplicatedName305 (plus missing imported result). Existing compact-height/idle-notification/typed-style/theme/position and new WebContent local-font-load tests passed. Failed logs retained under exact41b5a14 evidence.
- Fix the actual boundary code, retain original assertions: compare symlink-resolved parent paths rather than URL directory markers; accept documented alreadyRegistered/duplicatedName only when the exact PostScript face resolves (no fallback). Full new-head native gates still required.

- Native26 on41b5a14 also logged158tests/3assertionfailures, same font boundaries. The complete nine-theme snapshot test took62.9sec on Intel and exceeded its60sec per-test allowance; overall step hit25min after20min compile. Split the exact same18captures into three named6capture tests (no removed themes/appearances/traits/assertions). Increase native job/step walltime to45/35min, retain60sec per-test limit. Full regular suite completed under45min; no timing claims made from hosted simulators.

## Visual review41b5a14 / identity safety fix
- Downloaded regular compact UI archive54556403bytes SHA2561df89e4957bf21cf471766761b434c51de591f8fdd49b681b3c7617eaffc5bbf. Indexed25 scoped PNGs with hashes under F:/SourceReadSwift/reader-motion-117/41b5a1463ffd7e9ea5c1a10d91270506b4b25828/visual-review/INDEX.json; inspected five contact sheets and raw390 remote/blueprintdark images.
- Missing-cover theme jackets and compact desk are visible in all9themes/lightdark; accessibility grows rather than shrinks. Found important failure: detail identity fade was still nearzero in several initial/mid-animation captures. Do not accept these screenshots as finished. Remove opacity gating from essential title/author; retain only bounded offset and native zoom. Add immediate-render ink assertion excluding jacket/toplabel/footer, so an unreadable initial title cannot pass via a nice screenshot later. New exact-head screenshots required.
