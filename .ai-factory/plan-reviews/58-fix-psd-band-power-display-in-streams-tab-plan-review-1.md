# Plan Review: Fix PSD band power display in Streams tab

**Plan:** `.ai-factory/plans/58-fix-psd-band-power-display-in-streams-tab.md`
**Risk Level:** 🟢 Low

## Context Gates

- **ARCHITECTURE.md** — OK. The plan is scoped to `example/lib/screens/streams_screen.dart`, which is correctly inside the Example app layer. No bridge / model / channel boundary is crossed. The constraint section explicitly forbids touching the JNI/iOS bridges and `PsdData`, which matches the architectural boundaries.
- **ROADMAP.md** — OK. Plan aligns 1:1 with the open item under **Bug fixes & hardening** → "Fix PSD band power display in Streams tab" (line 79). The plan chose the cleaner `lo/hi` swap instead of the roadmap-suggested `.clamp(...)` formulation, but the end result is equivalent and arguably more readable.
- **RULES.md** — Not present. No additional gates to enforce.
- **skill-context/aif-review/SKILL.md** — Not present. No project-specific overrides.

## Codebase Verification

- `example/lib/screens/streams_screen.dart` exists; `_bandPower` is at **line 78** as stated. The comparison `if (f >= lower && f <= upper)` is at **line 83**, not 78 itself, but the task description correctly says "around line 78" referring to the function definition. ✅
- `_PsdCard.build` uses `.toStringAsFixed(3)` on five band labels at **lines 114, 117, 120, 123, 126** — exactly as the plan states. ✅
- `PsdData` exposes the eight fields the task names (`deltaLower/Upper`, `thetaLower/Upper`, `alphaLower/Upper`, `smrLower/Upper`, `betaLower/Upper`) plus optional `individual*` fields. All referenced fields are `double` (non-nullable). ✅
- `PsdData.frequencies`, `frequencyCount`, `channelCount`, `values` (List<List<double>>) — all match the usage inside `_bandPower`. ✅
- The "swapped bounds" claim is consistent with the roadmap log ("SDK sends `deltaLower=4.0, deltaUpper=1.0`"). The fix is defensive and does not assume a fixed direction. ✅

## Findings

### Critical Issues
None.

### Suggestions (non-blocking)

1. **Magnitude assumption for `toStringAsExponential(2)`** — the plan asserts PSD values are SI W/Hz on the order of `1e-14`–`1e-17`. Scientific notation handles values of *any* magnitude legibly (including `0.000` cases), so the fix is safe even if a future SDK version changes units. Worth a one-line comment near the band labels noting "PSD is W/Hz, render in scientific notation" so a future reader does not "tidy" it back to `toStringAsFixed`.

2. **Minor: `_bandPower` still treats `values[ch][fi]` as positive-summable** — the sum/average logic is unchanged and is fine for power spectral density (always ≥ 0), but if the SDK ever returns sentinel `-1` to mean "no data" (used elsewhere in the SDK for "not available") the average would be skewed. Out of scope for this fix, but worth a follow-up roadmap entry if it ever materializes. No change requested here.

3. **No test added** — plan explicitly sets `Testing: no`. The bounds-swap normalization is pure logic that would be easy to unit-test (e.g., `_bandPower` with `lower=4, upper=1` should pick the same bins as `lower=1, upper=4`). Not blocking — example apps in this repo follow the "manual smoke test on hardware" pattern, and `_bandPower` is private to the screen file. Mentioned only for awareness.

### Positive Notes

- Scope is tightly bounded — only the example screen, no bridge or model surface. Matches the roadmap directive verbatim.
- The `lo = lower <= upper ? lower : upper` formulation is more readable than the `.clamp(...)` chain hinted at in the roadmap, and is symmetric/defensive against any future swap direction.
- Constraints section explicitly forbids touching `PsdData`, providers, and the JNI/iOS bridges, which is the right call given the SDK contract quirk.
- Task ordering (Task 2 depends on Task 1) is correct — without bounds normalization, scientific notation alone would still show non-zero values for some bands but with whatever (wrong) bins fall inside the swapped range.

## Verdict

Plan is precise, scoped correctly, and the line/file references all check out against the codebase. No critical issues, no architectural conflicts, no missing steps.

PLAN_REVIEW_PASS
