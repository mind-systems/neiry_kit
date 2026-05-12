# Code Review: Fix PSD band power display in Streams tab

**Plan:** `.ai-factory/plans/58-fix-psd-band-power-display-in-streams-tab.md`
**Changed files:**
- `example/lib/screens/streams_screen.dart` (modified)
- `.ai-factory/plans/58-fix-psd-band-power-display-in-streams-tab.md` (new)
- `.ai-factory/plan-reviews/58-fix-psd-band-power-display-in-streams-tab-plan-review-1.md` (new)

## Scope check

Only `example/lib/screens/streams_screen.dart` was modified in the application code, matching the plan's constraint that JNI/iOS bridges and `PsdData` must not be touched. No proto, no platform channel, no provider changes. ✅

## Correctness

### Task 1 — bounds normalization (lines 78–94)

```dart
double _bandPower(PsdData psd, double lower, double upper) {
  final lo = lower <= upper ? lower : upper;
  final hi = lower <= upper ? upper : lower;
  ...
  if (f >= lo && f <= hi) { ... }
```

- Logic is symmetric and tolerates either ordering. With `deltaLower=4.0, deltaUpper=1.0` from the SDK, `lo=1.0, hi=4.0`, so frequency bins in `[1, 4]` Hz now match. ✅
- If `lower == upper`, the first ternary picks `lower` and the second picks `upper` (same value) — fine. ✅
- The inclusive bounds (`>=`, `<=`) match the original logic; bins exactly on the boundary still count. ✅
- No change to sum accumulation, channel iteration, averaging, or the `count == 0 || psd.channelCount == 0` zero-guard, per the plan. ✅

### Task 2 — scientific notation (lines 115–129)

All five band labels (`Delta`, `Theta`, `Alpha`, `SMR`, `Beta`) now use `.toStringAsExponential(2)`. Label text, widget tree, and surrounding code are untouched. ✅

For PSD magnitudes around `1e-14` to `1e-17` W/Hz, output is now legible (e.g. `2.34e-15`) instead of `0.000`. For `0.0` (count=0 case), `toStringAsExponential(2)` yields `"0.00e+0"`, which is still readable. ✅

## Runtime risk analysis

- **NaN / Infinity bounds:** `lower <= upper` with NaN evaluates to false, so `lo` would get `upper` and `hi` would get `lower`; subsequent `f >= lo && f <= hi` comparisons against NaN are false → returns 0. No crash, just a zero band. Same degenerate behavior as before the fix. Not a regression.
- **Empty `psd.frequencies` / `psd.values`:** loop body never executes, `count==0` guard returns `0.0`. `0.0.toStringAsExponential(2)` is `"0.00e+0"` — renders fine. No null-deref risk.
- **No async / threading changes:** the function and its call sites are pure synchronous code inside the build method. No race conditions introduced.
- **No new imports, no new dependencies, no type changes.** Hot reload safe.

## Style / consistency

- Variable names `lo` / `hi` are concise and idiomatic Dart; consistent with the surrounding terse style (`fi`, `ch`).
- The two-line ternary could be written as `final (lo, hi) = lower <= upper ? (lower, upper) : (upper, lower);` using records, but the current form is clearer and avoids assuming a Dart SDK version that supports record-destructuring patterns. Not a finding — current form is fine.

## What I checked but found nothing wrong with

- `PsdData` field access — `deltaLower/Upper`, `thetaLower/Upper`, `alphaLower/Upper`, `smrLower/Upper`, `betaLower/Upper` are all referenced unchanged from before the fix; no schema drift.
- `_bandPower` is private to the file (`_` prefix) — no external callers to update.
- No tests reference `_bandPower` or these labels (plan explicitly sets `Testing: no`); nothing to update there.
- Other PSD-related code paths (NFB classifier, etc.) are not affected — they consume `clCNFB` band fields directly, not via this UI helper.

## Findings

None.

REVIEW_PASS
