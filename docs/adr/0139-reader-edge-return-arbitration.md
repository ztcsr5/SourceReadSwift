# 0139 · Edge-return gesture arbitration inside the WKWebView reader

## Context

The reader's native interactive return (iOS 18+ system Zoom, iOS 16/17 compatibility
transition) intermittently never begins when the drag starts at the leading edge over
real prose. Four controlled runs on simulator hardware (80–100 rounds each, identical
touch input, identical native stack, only the WebKit arbitration scope varied) narrowed
it down:

| run | conditions | failing rounds | highlight began in failures |
|---|---|---:|---:|
| b2c865aa | A/B/C/D | 17/80 | 17/17 |
| 9d97d537 | A/B/C/D/E | 18/100 | 18/18 |
| 5ba22c2e (iOS 26) | A/D/F/G | 6/80 (all D) | 6/6 |
| 5ba22c2e (iOS 18) | A/D/F/G | 5/80 (all D) | 1/1 armed |

In every passing round `WKHighlightLongPressGestureRecognizer` stayed `.possible`.
`require(toFail:)` on it — even when the walk verifiably reached `WKContentView` —
did not stop it from beginning. Turning its `isEnabled` off did.

## Options

1. Keep adjusting thresholds, delays or gesture speeds. Rejected: 180 rounds already
   disprove "not enough distance/time"; failures are discrete, not graded.
2. Install failure dependencies only. Rejected by measurement: WebKit begins the
   highlight regardless, so the system Zoom never receives the edge drag.
3. Disable the highlight while text selection is off, keep the subtree failure
   dependency, and restore the recognizer the moment selection is turned back on.
   Selected — F and G both reached 20/20 on iOS 26 and iOS 18.

## Decision

`ReaderEdgeReturnWebView.edgeGateScope` defaults to `.webKitSubtreeWithoutHighlight`.
`applySelectionHighlightPolicy` disables reachable highlight recognizers immediately
when `textSelectionEnabled == false` and re-enables exactly those instances when the
user turns selection on. Instances are tracked by identity, never by class, so a WebKit
revision that adds a second highlight cannot leak a disabled recognizer.

## Consequences

- Edge return no longer depends on WebKit's long-press arbitration while selection is off.
- With text selection ON the highlight stays enabled; a leading-edge drag over selected
  text can still be swallowed. This is a known, deliberate degradation and needs device
  confirmation, not a silent behavior change.
- The gate is installed from `layoutSubviews`/`didMoveToWindow` as before; it remains a
  no-op when no navigation controller or edge recognizer exists (sheet-hosted readers).
- Experiments stay in `ReaderZoomExperiment` (DEBUG-only launch argument). Production
  never routes through them.

## Evidence

`docs/READER-ZOOM-EXPERIMENT-20261112.md`, rounds archived at
`F:/SourceReadSwift/reader-quality-137/verification/`.