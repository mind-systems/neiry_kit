# Plan Review: Add permanent action logs to example app

**Plan:** `.ai-factory/plans/60-add-permanent-action-logs-to-example-app.md`
**Files reviewed:** 6 source files referenced by the plan (router + 5 screens)
**Risk Level:** 🟡 Medium (one compile-breaking bug, several under-specified edits)

---

## Context Gates

- **Architecture (`.ai-factory/ARCHITECTURE.md`):** WARN — read only the size; this is a pure UI/logging change with no architectural surface (no native bridges, no models, no providers). No boundary or dependency concern.
- **Rules (`.ai-factory/RULES.md`):** WARN — file is not present in `.ai-factory/`. No project-rule violations to check against; falling back to plan-internal "Notes" section, which already encodes the relevant rules (no `kDebugMode`, no `debugPrint`, no `print`).
- **Roadmap (`.ai-factory/ROADMAP.md`):** PASS — this work matches the last unchecked milestone in **Bug fixes & hardening** (`"Add permanent action logs to example app"`). Plan text and roadmap text are consistent on tag name (`'Neiry'`), control list, and "no Streams screen, no provider/notifier files".
- **Skill-context (`.ai-factory/skill-context/aif-review/SKILL.md`):** absent — no project-level overrides to honor.

---

## Critical Issues

### 1. `'Device selected: $serial'` references an undefined variable — compile error
**File:** `example/lib/screens/device_screen.dart` — Task 2, ListTile `onTap` in `_buildScanResults()`

The plan instructs:

> add `log('Device selected: $serial', name: 'Neiry');` inside the `setState(() => _selectedSerial = d.serial)` callback (before the assignment)

There is no `serial` identifier in scope at that point. The visible identifiers are `d` (the loop item, `DeviceInfo`) and `_selectedSerial` (the field, still holding the *old* value before the assignment). A literal implementation will fail with `Undefined name 'serial'` in `dart analyze` / build.

Two valid fixes — pick one explicitly in the plan:
- Use the device under the user's finger: `log('Device selected: ${d.serial}', name: 'Neiry');`
- Use the field name: `log('Device selected: $_selectedSerial', name: 'Neiry');` *(but this prints the previous selection because the log fires before the assignment — almost certainly not what was intended).*

Recommendation: `${d.serial}`. The roadmap milestone description has the same typo and should be amended too if reachable.

---

## Issues / Under-specifications

### 2. Arrow-bodied `onPressed` callbacks need conversion to block bodies — not stated
Several controls the plan touches are written as arrow expressions today; inserting a statement *before* the call requires switching the callback to a block body. The plan says "immediately before the call" without flagging this. The affected callbacks (an implementer should not miss them but explicit guidance prevents ambiguity):

- `calibration_screen.dart` — `_IdleContent` buttons `startFull` / `startQuick` / `importFromFile`
  Current: `onPressed: () => ref.read(calibrationProvider.notifier).startFull(),`
  Required: convert to `onPressed: () { log(...); ref.read(...).startFull(); },`.
- `calibration_screen.dart` — `_ActiveContent` `abort` button (arrow today).
- `calibration_screen.dart` — `_DoneContent` `Recalibrate` button (arrow today). Note: the `Export to File` button is *already* a block body (`onPressed: () async { … }`), so it needs only an `log(...)` inserted before `await ref.read(...).exportToFile()`.
- `calibration_screen.dart` — `_ErrorContent` `Retry` button (arrow today).
- `classifiers_screen.dart` — Physio "Start Baseline Calibration" button (arrow today). "Import Baselines" and "Export Baselines" are already block bodies — log can be inserted in place.
- `productivity_cardio_screen.dart` — Productivity "Start Baseline Calibration" and "Reset Fatigue" buttons (both arrow today).

No code change is required to behavior, but the plan should either say "convert the `=>` body to a `{ … }` body" or hand the implementer the rewritten snippets to avoid an over-literal edit that produces invalid Dart (e.g. `() => log(...); ref.read(...)...` parses as a one-expression arrow body returning the log result and silently drops the second statement).

### 3. Device-screen `ListTile.onTap` also needs body conversion
Related to issue 1: the `onTap` is currently
```dart
onTap: () => setState(() => _selectedSerial = d.serial),
```
Both the outer and inner callbacks are arrow. To insert a `log(...)` "inside the `setState(...)` callback before the assignment", the inner arrow must become a block:
```dart
onTap: () => setState(() {
  log('Device selected: ${d.serial}', name: 'Neiry');
  _selectedSerial = d.serial;
}),
```
or hoist the log out of `setState` (cheaper, equally correct):
```dart
onTap: () {
  log('Device selected: ${d.serial}', name: 'Neiry');
  setState(() => _selectedSerial = d.serial);
},
```
Plan should pick one form so the patch is unambiguous.

### 4. Ordering of "Scan tapped" log vs. permission gate
Plan: "Insert `log('Scan tapped', name: 'Neiry');` as the first statement of `_scan()`."

`_scan()`'s current first statement is `if (!await _checkAndRequestPermissions()) return;`. Putting the log before the permission check is correct (the user *did* tap Scan even if permissions get denied), but it does mean an "Scan tapped" line is emitted on every permission denial. That's fine for diagnostics, but worth confirming the intent. No change needed unless the author preferred "log only after the permission gate".

### 5. `_tabName` style — `static` on `StatelessWidget`
Plan: "Add a private static helper `String _tabName(int i)` inside `_RootScaffold`".

`_RootScaffold` is a `StatelessWidget`. A `static String _tabName(int i)` on it is legal Dart but slightly unusual; an instance method would also work. Either is fine — no action required, just noting the choice is stylistic. The label list matches the router branch order: `Device, Streams, Classifiers, Productivity, MEMS, Calibration` ✓.

---

## Verified-Correct Items

- Tag name `'Neiry'` is consistent across all 7 control families and matches the roadmap.
- `dart:developer` is the correct logging channel for permanent diagnostic logs (survives profile/release; surfaces in `flutter logs`, logcat, Console.app). Plan correctly forbids `debugPrint`/`print`/`kDebugMode`.
- Tab labels in `_tabName` match the router branch order one-to-one.
- All file paths exist and match the listed identifiers (`useMemsCalibrationToggleProvider`, `useCalibrationToggleProvider`, `PhysioBaselinesFileManager.{import,export}FromFile/ToFile`, `productivityClassifierProvider.notifier`, etc.).
- The `_connect()` log `'Connect tapped: $_selectedSerial'` is correctly scoped — `_selectedSerial` is an instance field accessible at the method head.
- Streams screen correctly excluded (no interactive controls — only `ListTile`s rendering data).
- Provider/notifier files correctly excluded (matches the roadmap's "do not touch any provider/notifier files").
- Commit plan is reasonable; two commits split along a natural seam (navigation+device+calibration ↔ classifiers+MEMS+productivity).

---

## Suggested Plan Amendments

Before implementation, the plan should be updated to:
1. Fix the `$serial` → `${d.serial}` typo in Task 2 (the compile-breaker).
2. Either (a) provide the post-edit snippet for each arrow-bodied callback that becomes a block, or (b) add a one-line note: *"Where the existing `onPressed: () => …` is an arrow expression, convert it to a block body `onPressed: () { log(...); …; }` — never use `() => log(...); call();` which parses as a single-expression body."*
3. Pick a concrete form for the `ListTile.onTap` rewrite in `_buildScanResults()`.

The rest of the plan is sound and ready to implement once those amendments land.
