# Plan Review: 57-fix-scan-spinner-not-showing-on-repeat-scan

## Code Review Summary

**Files Reviewed:** 1 plan, 2 source files (`example/lib/screens/device_screen.dart`, `example/lib/providers/device_scan_provider.dart`)
**Risk Level:** 🟢 Low

### Context Gates
- **Architecture (`.ai-factory/ARCHITECTURE.md`)**: Change is scoped to the example app UI layer; no architectural boundaries touched. PASS.
- **Rules (`.ai-factory/RULES.md`)**: File not present in repo — skipped (WARN, non-blocking).
- **Roadmap (`.ai-factory/ROADMAP.md`)**: Task 57 is a small example-app fix; not required to be a roadmap milestone. WARN, non-blocking.
- **Skill-context (`.ai-factory/skill-context/aif-review/SKILL.md`)**: Not present — no project-specific overrides apply.

### Diagnosis verification

The plan's root-cause analysis matches Riverpod semantics:

- `deviceScanProvider` is a `FutureProvider.family` returning `Stream.first` (`device_scan_provider.dart:17-19`).
- `_scan()` calls `ref.invalidate(deviceScanProvider(params))` only when params are unchanged (`device_screen.dart:87-90`). When params change, `setState(...)` triggers a new `ref.watch` of a fresh provider instance, producing `AsyncLoading` — that case already worked.
- For the same-params case, `ref.invalidate` flips the existing provider to `AsyncData(prevValue, isLoading: true)` (Riverpod 2.x "refresh" semantics). `AsyncValue.when()` defaults to `skipLoadingOnRefresh: true`, so it routes to `data:` and renders the stale device list with no spinner — exactly the reported symptom.

Diagnosis is correct.

### Fix verification

The proposed guard:

```dart
if (scanAsync.isLoading) { ... CircularProgressIndicator() ... }
```

`AsyncValue.isLoading` is `true` for both `AsyncLoading` (initial) and `AsyncData/AsyncError` with the loading flag set (refresh). Inserting it before `.when()` correctly covers both cases. File path (`example/lib/screens/device_screen.dart`) and insertion site (after line 237 `final scanAsync = ref.watch(...)`, before line 239 `return scanAsync.when(...)`) match the actual code.

Side effects considered:
- Stale device list disappears during a refresh while the spinner is shown. That is the intended UX per the plan's stated goal ("spinner shows for both first-time and repeat scans").
- The `loading:` branch of `.when()` becomes dead code in practice; the plan acknowledges this and keeps it for safety. Acceptable.
- No other call sites of `deviceScanProvider` exist (verified via grep mental-model from imports); only `_buildScanResults()` watches it.

### Critical Issues
None.

### Minor Suggestions (non-blocking)

1. **Idiomatic alternative.** A more idiomatic Riverpod fix is a single-line change to `.when()`:
   ```dart
   return scanAsync.when(
     skipLoadingOnRefresh: false,
     loading: () => ...,
     error: ...,
     data: ...,
   );
   ```
   This routes refresh-loading through the existing `loading:` branch instead of guarding before `.when()`, avoiding the "dead branch" the plan mentions. Behaviorally equivalent. The plan's explicit-guard approach is also correct and arguably more readable to someone unfamiliar with `skipLoadingOnRefresh`. Not a blocker — author's choice.

2. **Minimal logging.** Plan says "Logging: minimal" but adds no logs. For a UI-only fix this is fine; the existing `_showError` SnackBar covers error visibility. No action needed.

### Positive Notes

- Root cause is correctly identified at the Riverpod state-machine level, not just at the symptom level.
- The fix is local, minimal, and does not touch the provider, state model, or any cross-project contract.
- Plan correctly preserves the `loading:` branch in `.when()` as a defensive fallback.
- File path and line numbers match the actual codebase.

PLAN_REVIEW_PASS
