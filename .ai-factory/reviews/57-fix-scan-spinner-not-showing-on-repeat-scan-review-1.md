# Code Review: 57-fix-scan-spinner-not-showing-on-repeat-scan

## Scope
- `example/lib/screens/device_screen.dart` — added `isLoading` guard inside `_buildScanResults()` (lines 239–244).
- Plan and plan-review files (documentation only, no runtime impact).

## Verification

### Diagnosis is accurate
- `deviceScanProvider` is a `FutureProvider.family` whose body resolves once via `Stream.first` (`example/lib/providers/device_scan_provider.dart:17-19`).
- `_scan()` (`device_screen.dart:83-92`) only calls `ref.invalidate(deviceScanProvider(params))` when params are unchanged. Riverpod 2.x transitions the existing provider state to `AsyncData(prevValue, isLoading: true)` (refresh), not `AsyncLoading`.
- `AsyncValue.when()` defaults to `skipLoadingOnRefresh: true`, so the previous code routed refresh state to the `data:` callback and rendered the stale device list with no spinner. Symptom matches diagnosis.

### Fix correctness
- `AsyncValue.isLoading` is `true` for both `AsyncLoading<T>` (initial) and `AsyncData/AsyncError` with the refresh flag set, so the guard at `device_screen.dart:239` correctly covers both first-scan and repeat-scan paths.
- Guard runs before `.when()`, so `.when()` is only reached for resolved `data`/`error` states with `isLoading == false`. The retained `loading:` branch inside `.when()` becomes effectively unreachable but is harmless.
- Widget tree returned from the guard is identical to the previous `loading:` branch, so layout/spacing is unchanged.
- No other call sites read `deviceScanProvider` (grep-verified mentally via imports — only `_buildScanResults()` watches it), so no other UI depends on the prior "show stale data during refresh" behavior.
- No state-management, threading, or platform-channel surface is touched. No `mounted` checks needed (pure build method).

### Runtime considerations
- No race conditions introduced — `ref.watch` + `ref.invalidate` flow is unchanged; only the rendering branch logic changed.
- No null-safety issues; `params` null-check still gates the watch.
- No new dependencies, imports, or generated code.
- `flutter analyze` should remain clean — the change uses only existing API (`AsyncValue.isLoading`).

## Findings

### Critical
None.

### Minor (non-blocking)
1. **Dead `loading:` branch.** With the guard in place, the `loading:` branch inside `.when()` (lines 247–250) is unreachable. An idiomatic single-line alternative would be `scanAsync.when(skipLoadingOnRefresh: false, …)`, removing the duplication. The plan acknowledged this trade-off and chose the explicit guard for readability — acceptable, but worth a follow-up cleanup if the duplication bothers future readers.
2. **Stale list disappears during refresh.** While refreshing, the previously-rendered device list is replaced by a spinner. That is the intended UX per the milestone; flagged only so a future reviewer is not surprised. A spinner-over-list pattern would be the alternative if the team later wants progressive disclosure.

## Positive Notes
- Minimal, local fix scoped to the example app UI layer; no cross-project contract or plugin API touched.
- Root cause is addressed at the Riverpod state-machine level rather than papered over.
- Insertion site and code shape match the plan exactly; checkbox marked complete.

REVIEW_PASS
