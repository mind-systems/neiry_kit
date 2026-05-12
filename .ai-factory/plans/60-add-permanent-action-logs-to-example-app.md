# Plan: Add permanent action logs to example app

## Context
Add permanent (non-debug-only) `dart:developer` `log()` calls with the tag `'Neiry'` to every interactive control in the example app so manual on-device testing can be followed via logcat / Console.app without reading source code.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Conventions (apply to every task)
- Use `dart:developer`'s `log(message, name: 'Neiry')` exclusively — do **not** use `debugPrint` (stripped in profile/release) or `print` (no tag).
- Do **not** wrap log calls in `kDebugMode` — these are permanent diagnostic logs.
- **Arrow → block conversion.** Where the existing callback is an arrow expression (e.g. `onPressed: () => ref.read(x).y()`), convert it to a block body before inserting the log:
  ```dart
  onPressed: () {
    log('...', name: 'Neiry');
    ref.read(x).y();
  },
  ```
  Never write `onPressed: () => log(...); ref.read(x).y();` — Dart parses that as a single-expression arrow body returning the `log()` result and silently drops the rest.
- Do **not** modify the Streams screen (no interactive controls) and do **not** touch any provider/notifier files.

## Tasks

### Phase 1: Navigation logging

- [x] **Task 1: Add tab-switch logs in router**
  Files: `example/lib/router.dart`
  Add `import 'dart:developer';` at the top of the file (alongside other imports) if not already present.
  In `_RootScaffold.build`, replace `onDestinationSelected: navigationShell.goBranch` with a lambda `(int index) { log('Tab → ${_tabName(index)}', name: 'Neiry'); navigationShell.goBranch(index); }`.
  Add a private static helper `String _tabName(int i)` inside `_RootScaffold` that returns the value at index `i` of the const list `['Device', 'Streams', 'Classifiers', 'Productivity', 'MEMS', 'Calibration']`. (Static on a `StatelessWidget` is intentional — no instance state is needed.)

### Phase 2: Device screen logging

- [x] **Task 2: Add device action logs**
  Files: `example/lib/screens/device_screen.dart`
  Add `import 'dart:developer';` at the top of the file.
  Insert `log('Scan tapped', name: 'Neiry');` as the first statement of `_scan()` (before the permission gate — we want to record the tap even when permissions get denied).
  Inside `_buildScanResults()`, rewrite the `ListTile.onTap` from
  ```dart
  onTap: () => setState(() => _selectedSerial = d.serial),
  ```
  to
  ```dart
  onTap: () {
    log('Device selected: ${d.serial}', name: 'Neiry');
    setState(() => _selectedSerial = d.serial);
  },
  ```
  (Use `${d.serial}` — not `$serial`, which is undefined in scope. The log is hoisted out of `setState` so it does not run inside the framework's setState callback.)
  Insert `log('Connect tapped: $_selectedSerial', name: 'Neiry');` as the first statement of `_connect()`.
  Insert `log('Start tapped', name: 'Neiry');` as the first statement of `_start()`.
  Insert `log('Stop tapped', name: 'Neiry');` as the first statement of `_stop()`.
  Insert `log('Disconnect tapped', name: 'Neiry');` as the first statement of `_disconnect()`.

### Phase 3: Calibration screen logging

- [x] **Task 3: Add calibration action logs**
  Files: `example/lib/screens/calibration_screen.dart`
  Add `import 'dart:developer';` at the top of the file.
  All `onPressed` callbacks in this file except `_DoneContent`'s `Export to File` are arrow-bodied — convert each to a block body per the Conventions section before inserting the log.
  In `_IdleContent`:
  - `Start Full` button — convert to block; add `log('Calibration: Start Full tapped', name: 'Neiry');` before `ref.read(calibrationProvider.notifier).startFull()`.
  - `Start Quick` button — convert to block; add `log('Calibration: Start Quick tapped', name: 'Neiry');` before `startQuick()`.
  - `Import from File` button — convert to block; add `log('Calibration: Import tapped', name: 'Neiry');` before `importFromFile()`.
  In `_ActiveContent`:
  - `Abort` button — convert to block; add `log('Calibration: Abort tapped', name: 'Neiry');` before `abort()`.
  In `_DoneContent`:
  - `Export to File` button is already a block body (`onPressed: () async { ... }`); just insert `log('Calibration: Export tapped', name: 'Neiry');` before `await ref.read(...).exportToFile()`.
  - `Recalibrate` button — convert to block; add `log('Calibration: Recalibrate tapped', name: 'Neiry');` before `startFull()`.
  In `_ErrorContent`:
  - `Retry` button — convert to block; add `log('Calibration: Retry tapped', name: 'Neiry');` before `ref.invalidate(calibrationProvider)`.

### Phase 4: Classifier-related screens logging

- [x] **Task 4: Add classifiers screen action logs**
  Files: `example/lib/screens/classifiers_screen.dart`
  Add `import 'dart:developer';` at the top of the file.
  Physio `Start Baseline Calibration` button is arrow-bodied — convert to block; add `log('Physio: Start Baseline Calibration tapped', name: 'Neiry');` before the `startBaselineCalibration()` call.
  `Import Baselines` and `Export Baselines` buttons are already block bodies — insert `log('Physio: Import Baselines tapped', name: 'Neiry');` before `PhysioBaselinesFileManager.importFromFile()` and `log('Physio: Export Baselines tapped', name: 'Neiry');` before `PhysioBaselinesFileManager.exportToFile()`.

- [x] **Task 5: Add MEMS screen toggle log**
  Files: `example/lib/screens/mems_screen.dart`
  Add `import 'dart:developer';` at the top of the file.
  In the `SwitchListTile.onChanged` lambda, convert to block body if arrow-bodied and add `log('MEMS: Use NFB Calibration toggled: $val', name: 'Neiry');` before the `ref.read(useMemsCalibrationToggleProvider.notifier).state = val` assignment.

- [x] **Task 6: Add productivity+cardio screen action logs**
  Files: `example/lib/screens/productivity_cardio_screen.dart`
  Add `import 'dart:developer';` at the top of the file.
  In the `SwitchListTile.onChanged` lambda, convert to block body if arrow-bodied and add `log('Productivity: Use NFB Calibration toggled: $val', name: 'Neiry');` before the `ref.read(useCalibrationToggleProvider.notifier).state = val` assignment.
  Productivity `Start Baseline Calibration` button is arrow-bodied — convert to block; add `log('Productivity: Start Baseline Calibration tapped', name: 'Neiry');` before the `startBaselineCalibration()` call.
  `Reset Fatigue` button is arrow-bodied — convert to block; add `log('Productivity: Reset Fatigue tapped', name: 'Neiry');` before the `resetAccumulatedFatigue()` call.

## Commit Plan
- **Commit 1** (after tasks 1-3): "Add permanent action logs to navigation, device, and calibration screens"
- **Commit 2** (after tasks 4-6): "Add permanent action logs to classifiers, MEMS, and productivity screens"
