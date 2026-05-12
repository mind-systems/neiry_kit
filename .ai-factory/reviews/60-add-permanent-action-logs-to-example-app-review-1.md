# Code Review: Add permanent action logs to example app

**Plan:** `.ai-factory/plans/60-add-permanent-action-logs-to-example-app.md`
**Files reviewed:** 6 modified files (router + 5 screens), full read of each
**Risk Level:** 🟢 Low — UI-only, additive logging change

---

## Scope verification

`git status` shows only the six expected files modified (plus plan/review markdown). No stray edits, no provider/notifier files touched, Streams screen untouched — matches the plan exactly.

## Task-by-task verification

| Task | Expected | Observed | Status |
|---|---|---|---|
| 1: Router tab logs | `dart:developer` import + `_tabName` helper + `onDestinationSelected` lambda | `router.dart:1,54-55,63-66` — all present | ✓ |
| 2: Device action logs | 6 logs across `_scan`/`_connect`/`_start`/`_stop`/`_disconnect`/`ListTile.onTap` | `device_screen.dart:1,85,99,115,129,143,278-281` — all present with `${d.serial}` | ✓ |
| 3: Calibration logs | 7 logs across Idle/Active/Done/Error | `calibration_screen.dart:1,105-108,112-115,119-122,156-159,192,206-209,234-237` — all present | ✓ |
| 4: Classifiers physio logs | 3 logs (Start Baseline / Import / Export) | `classifiers_screen.dart:1,156-161,170,193` — all present | ✓ |
| 5: MEMS toggle log | 1 log in `onChanged` | `mems_screen.dart:1,51` — present | ✓ |
| 6: Productivity logs | 3 logs (toggle / Start Baseline / Reset Fatigue) | `productivity_cardio_screen.dart:1,88,217-222,230-235` — all present | ✓ |

## Correctness checks

- **Tab name list ordering.** Router branches: `device, streams, classifiers, productivity, mems, calibration` (`router.dart:20-43`). `_tabName` returns `['Device','Streams','Classifiers','Productivity','MEMS','Calibration'][i]`. Order matches the `NavigationDestination` labels at `router.dart:68-76`. Index → name mapping is correct.
- **Plan critical bug avoided.** The previously flawed `'Device selected: $serial'` has been emitted as `'Device selected: ${d.serial}'` (`device_screen.dart:279`). `d` is the loop item in `widget.devices.map((d) => ...)` and is in scope. Compiles cleanly.
- **`_connect()` log nullability.** `log('Connect tapped: $_selectedSerial', ...)` runs before the `serial == null` early-return. When `_selectedSerial` is null, Dart's string interpolation renders `null` — emits `"Connect tapped: null"`. This is intentional per the plan ("log when the user tapped, even on no-op") and not a bug. No crash possible.
- **`_scan()` log placement.** Emitted as the first statement, before `_checkAndRequestPermissions()`. Permission denial still produces a log line — matches the plan's documented intent.
- **Arrow → block conversions.** All seven arrow-bodied callbacks the plan flagged were correctly converted to block bodies. None were left in the dangerous `() => log(...); call();` form. The two already-block bodies (`_DoneContent` Export, classifier Import/Export Baselines, productivity Export — i.e. anywhere with `async`) had the log inserted in-place without restructuring.
- **No `kDebugMode` / `debugPrint` / `print`.** Confirmed — every new line uses `log(..., name: 'Neiry')` from `dart:developer`.
- **Tag consistency.** Every new `log` call uses the literal `'Neiry'` for `name:`. Spot-checked all 21 added log statements.
- **Import hygiene.** `import 'dart:developer';` added once at the top of each of the six files, ordered before `package:` imports (matches dart formatter convention with a blank line between dart core and package groups).
- **No behavior change.** All edits are pre-call log statements; no expressions reordered, no async semantics altered, no `setState` calls moved across `await` boundaries. Side effects of the buttons remain identical.
- **No race conditions / lifecycle hazards.** `log()` is synchronous and has no I/O side effects beyond writing to the developer log stream — safe inside `setState`-adjacent callbacks, async functions, and Riverpod `read` chains.

## Items the plan didn't require but worth noting

- `_connect()` logs the previous-tap serial even when the user has reselected a device just before pressing Connect, because the log uses `_selectedSerial`. This is the intended behavior per the plan and matches what an operator reading logs would expect.
- The `_tabName` helper would throw `RangeError` if called with `i < 0` or `i ≥ 6`. In practice `navigationShell` only emits valid branch indices, so this is fine; not worth defensive coding.

---

## Summary

All six tasks implemented exactly as specified. The compile-breaking bug flagged in plan-review-1 was correctly fixed (`${d.serial}` instead of `$serial`). All arrow→block conversions are syntactically valid. Tag name, log channel, and provider/notifier exclusion all match plan conventions. No correctness, security, or runtime issues found.

REVIEW_PASS
