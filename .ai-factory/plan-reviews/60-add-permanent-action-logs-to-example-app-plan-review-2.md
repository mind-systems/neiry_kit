# Plan Review: Add permanent action logs to example app

**Plan file:** `.ai-factory/plans/60-add-permanent-action-logs-to-example-app.md`
**Risk Level:** 🟢 Low
**Verdict:** The plan accurately reflects the codebase and should produce a correct implementation if followed verbatim.

## Verification of plan claims against the codebase

| Plan claim | Verified against | Result |
|---|---|---|
| `router.dart`: `_RootScaffold` is a `StatelessWidget` with `onDestinationSelected: navigationShell.goBranch` | `example/lib/router.dart:47,58` | ✅ |
| Tab order is `['Device', 'Streams', 'Classifiers', 'Productivity', 'MEMS', 'Calibration']` | `router.dart:18-41` (branches order) | ✅ Matches the `StatefulShellRoute` branches index-by-index |
| `device_screen.dart`: `_scan`, `_connect`, `_start`, `_stop`, `_disconnect` exist; scan results `ListTile.onTap` is arrow-bodied `() => setState(...)` | `device_screen.dart:83,96,111,124,137,272` | ✅ |
| `calibration_screen.dart`: all `onPressed` callbacks are arrow-bodied **except** `_DoneContent`'s Export-to-File (`onPressed: () async { … }`) | `calibration_screen.dart:103,109,115,148,181,195,221` | ✅ |
| `classifiers_screen.dart`: Physio `Start Baseline Calibration` is arrow-bodied; `Import Baselines` / `Export Baselines` are block bodies; uses `PhysioBaselinesFileManager.importFromFile()` / `.exportToFile(baselines)` | `classifiers_screen.dart:154,164,184` | ✅ |
| `mems_screen.dart`: `SwitchListTile.onChanged` writes to `useMemsCalibrationToggleProvider.notifier.state` | `mems_screen.dart:27,46-52` | ✅ Already a block body — the "convert if arrow-bodied" hedge is a no-op here, which is fine |
| `productivity_cardio_screen.dart`: `SwitchListTile.onChanged` already block body; Productivity `Start Baseline Calibration` and `Reset Fatigue` are arrow-bodied; uses `useCalibrationToggleProvider` and `productivityClassifierProvider` | `productivity_cardio_screen.dart:64,83-88,214-217,224-227` | ✅ |
| `streams_screen.dart` has no interactive controls and should be skipped | `streams_screen.dart` (whole file) | ✅ Confirmed — only display widgets |

## Strengths

- **The Dart arrow-vs-block gotcha is called out explicitly** in the Conventions section and the negative example (`onPressed: () => log(...); ref.read(x).y();`) is correct: Dart parses the body as a single expression `log(...)` and the rest becomes top-level statements outside the lambda, which is a real foot-gun. Including the warning prevents an entire class of silent breakage.
- **String-interpolation correction is right.** The note in Task 2 to use `${d.serial}` rather than `$serial` matters because `d` is the only in-scope binding (from `(d) => ListTile(...)`); `$d.serial` would interpolate `d` and append the literal `.serial`. Good catch.
- **Log placement before `_checkAndRequestPermissions()`** in `_scan()` is deliberate and well-justified — the tap is what we want to know about, independent of whether permission gating succeeds.
- **Hoisting the `Device selected` log out of `setState`** is the right call — running side effects inside the `setState` callback is a Flutter anti-pattern.
- **No state/provider files touched.** Constraint is explicit and the listed file scope respects it.
- **Tag consistency.** `name: 'Neiry'` everywhere produces a single, greppable subsystem name in logcat / Console.app — matches the stated goal.
- **`dart:developer` over `debugPrint`/`print`.** Correct choice for permanent diagnostic logs that must survive profile/release builds and carry a tag.

## Minor observations (non-blocking)

1. **Scope of "every interactive control" is narrower than the Context says.** The plan covers buttons/tile-taps/switches but skips two `onChanged` handlers in `device_screen.dart`:
   - The device-type `DropdownButton.onChanged` at `device_screen.dart:200`
   - The "Secs" `TextField.onChanged` at `device_screen.dart:214`

   These configure the Scan parameters but produce no log trace. If a tester reports "Scan didn't find my device", knowing what `(_selectedType, _searchTime)` was used would be more valuable than knowing Scan was tapped. Consider either (a) including a log on the dropdown change, or (b) extending the Scan log to `'Scan tapped: type=$_selectedType secs=$_searchTime'`. Not a defect — but worth a one-line decision in the plan so the implementer doesn't have to guess.

2. **Quick-calibration distinction is opaque from logs alone.** `_IdleContent`'s "Start Full" emits `'Calibration: Start Full tapped'`, "Start Quick" emits `'Calibration: Start Quick tapped'`, and `_DoneContent`'s "Recalibrate" (also `startFull()`) emits `'Calibration: Recalibrate tapped'`. That's good — the button identity is preserved, not the underlying method. Mentioning it just to confirm the choice is intentional (button-name over method-name).

3. **`_RootScaffold._tabName` is fed by the same constant list as the `destinations:` block.** The plan inlines a separate `['Device', 'Streams', ...]` list inside `_tabName`. That introduces a second source of truth that must stay in sync if a tab is ever added/reordered. Not worth refactoring for a 6-element list, but a one-line comment in `_tabName` like `// Keep in sync with destinations: above` would prevent future drift. Optional.

4. **Productivity & Cardio screen — the Cardio card has no interactive controls** (only display widgets and a `ref.listen` for the calibration SnackBar). The plan correctly omits it; flagging only because the screen name might mislead a future reader.

## Critical Issues

None.

## Architectural / Security / Migration concerns

None applicable — this is a logging-only example-app diff. No SDK boundary, no secrets, no schema, no platform-channel changes.

## Commit plan

Two commits split at Phase 3/4 is reasonable and each commit is independently coherent and shippable.

PLAN_REVIEW_PASS
