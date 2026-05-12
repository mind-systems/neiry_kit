# Plan: Fix PSD band power display in Streams tab

## Context
The Streams tab in the example app always shows `0.000` for every PSD band (Delta, Theta, Alpha, SMR, Beta) because `_bandPower()` receives swapped lower/upper bounds from the SDK and because the formatted output truncates SI-unit PSD magnitudes (~1e-14 W/Hz) to zero. Fix both bugs in `example/lib/screens/streams_screen.dart` only — the SDK bridge layers are intentionally untouched.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Fix display bugs

- [x] **Task 1: Normalize band bounds in `_bandPower`**
  Files: `example/lib/screens/streams_screen.dart`
  In `_bandPower(PsdData psd, double lower, double upper)` (around line 78), normalize the bounds before the frequency-bin comparison so the function tolerates swapped `lower`/`upper` values coming from the SDK (e.g. `deltaLower=4.0, deltaUpper=1.0`). At the top of the function compute `final lo = lower <= upper ? lower : upper;` and `final hi = lower <= upper ? upper : lower;`, then change the condition `if (f >= lower && f <= upper)` to `if (f >= lo && f <= hi)`. Do not change any other logic in the function (sum accumulation, channel iteration, averaging, zero-guards).

- [x] **Task 2: Render PSD band values in scientific notation** (depends on Task 1)
  Files: `example/lib/screens/streams_screen.dart`
  Replace `.toStringAsFixed(3)` with `.toStringAsExponential(2)` in all five band labels inside `_PsdCard.build` (Delta, Theta, Alpha, SMR, Beta — lines ~114, 117, 120, 123, 126) so that SI-unit PSD magnitudes (~1e-14 to 1e-17 W/Hz) render legibly instead of collapsing to `0.000`. Do not change label text, widget structure, or surrounding code.

## Constraints
- Do **not** modify the Android JNI bridge, iOS bridge, or any serialization code — the swapped bounds are an SDK contract quirk and `lower`/`upper` are labels, not ordering guarantees.
- Do **not** modify `PsdData` or any provider.
- Scope is limited to `example/lib/screens/streams_screen.dart`.
