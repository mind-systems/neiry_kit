# Code Review 1: 53-ble-runtime-permissions-on-scan

**Plan:** `.ai-factory/plans/53-ble-runtime-permissions-on-scan.md`
**Files changed:**
- `android/src/main/AndroidManifest.xml`
- `example/ios/Runner/Info.plist`
- `example/lib/screens/device_screen.dart`
- `example/pubspec.yaml`
- `example/pubspec.lock` (regenerated)

## Summary

All five planned tasks landed. The plugin manifest now caps the two legacy
location permissions at API 30, the example app pins
`permission_handler: ^11.4.0` (resolved to 11.4.0 / `permission_handler_android`
12.1.0), the iOS `NSBluetoothAlwaysUsageDescription` key is in
`Info.plist` in the right alphabetical slot, and the Scan flow gates on a new
`_checkAndRequestPermissions()` helper that follows the plan's exact ordering
(iOS short-circuit → request all three → `permanentlyDenied` first → plain
`denied` → success).

Verified independently:
- `IPHONEOS_DEPLOYMENT_TARGET = 13.0` in
  `example/ios/Runner.xcodeproj/project.pbxproj` — so
  `NSBluetoothAlwaysUsageDescription` alone is sufficient (no need for the
  deprecated `NSBluetoothPeripheralUsageDescription`).
- `example/analysis_options.yaml` only includes
  `package:flutter_lints/flutter.yaml` and adds no custom rules → neither
  `discarded_futures` nor `unawaited_futures` is enabled, so
  `onPressed: _scan` lands cleanly (matches plan expectation).
- `permission_handler` resolved to `11.4.0` with
  `permission_handler_android: 12.1.0` — current 11.x line.

The findings below are concerns to verify and one small robustness gap; none
of them are pre-existing regressions and none block landing on iOS.

## Issues / Concerns

### 1. `Permission.locationWhenInUse` behavior on Android 12+ after the manifest cap should be smoke-tested

The plan claims that capping `ACCESS_FINE_LOCATION` and
`ACCESS_COARSE_LOCATION` at `android:maxSdkVersion="30"` causes
`Permission.locationWhenInUse.request()` to *auto-grant* on API 31+ (because
those permissions no longer appear in the merged manifest at runtime for that
SDK level). This is the documented behavior for several BLE wrapper plugins
and is the pattern reviewer 2 endorsed.

However, `permission_handler_android`'s `LocationPermissionStrategy` has its
own logic. If on API 31+ it sees zero manifest entries for the location group
and returns `PermissionStatus.denied` (rather than `granted`), then the helper
will fall into:

```dart
if (statuses.values.any((s) => s != PermissionStatus.granted)) {
  if (!mounted) return false;
  _showError('Bluetooth permissions required');
  return false;
}
```

…and block scanning on every modern Android device with a misleading toast —
the exact failure mode reviewer 2 was trying to prevent.

I have not been able to verify this from source in this review. Before merging
this for use on Android 12+ hardware:

- **Action:** run the example app on an emulator or device with API 31+ and
  confirm `_checkAndRequestPermissions()` returns `true` after the user grants
  the two BLE prompts. If it returns `false` and shows the "Bluetooth
  permissions required" toast, the location request must be made conditional
  on `permission_handler_android` returning the underlying permissions as
  granted-by-omission; in that case the simplest fix is to drop
  `Permission.locationWhenInUse` from `permissions` on API 31+ (i.e.,
  reintroduce a one-call `device_info_plus` check, or use
  `Permission.bluetoothScan.shouldShowRequestRationale` as a proxy).

This is the single highest-risk runtime question in this changeset. The iOS
path and the legacy-Android path (API 26–30, where the location prompt is the
only thing requested and the BLE-pair `request()` is a no-op) are both
straightforward.

### 2. `_scan` calls `setState` after `await` without a `mounted` guard

`device_screen.dart:83-91`:

```dart
Future<void> _scan() async {
  if (!await _checkAndRequestPermissions()) return;
  final params = (_selectedType, _searchTime);
  if (_scanParams == params) {
    ref.invalidate(deviceScanProvider(params));
  }
  setState(() => _scanParams = params);
}
```

`_checkAndRequestPermissions()` awaits the OS permission dialog. If the user
navigates away from the Device screen while the dialog is up (e.g. switches
tabs, backgrounds the app on Android, then dismisses), the state can be
disposed before this method resumes. When the function returns `true`,
`setState` will be called on an unmounted `State` and throw a
"setState() called after dispose()" error.

The plan only required mounted guards around `context` access, but `setState`
is also a runtime hazard on a disposed state. Fix is a one-liner before the
`setState` call:

```dart
if (!mounted) return;
setState(() => _scanParams = params);
```

The same applies (less critically) to the `ref.invalidate` call — Riverpod is
forgiving about invalidating providers after dispose, but it's still a hint
that the helper now needs a post-await guard.

### 3. Rapid double-tap on Scan launches concurrent permission flows

Because `_scan` is now async and the button stays enabled while the dialog is
up, tapping Scan twice in quick succession will fire two concurrent
`permissions.request()` calls. In practice `permission_handler` queues these
and Android dedupes the dialog, but the `_showError` branch could fire twice
and queue duplicate snackbars on first-time denial. This is minor and matches
the pre-existing UX (the Scan button was never disabled mid-scan), so it's
flagged for awareness only — no fix required unless we want Scan to disable
itself while a permission request is in flight.

## Positive Notes

- **Manifest cap is exact.** Lines 12–15 of
  `android/src/main/AndroidManifest.xml` apply `android:maxSdkVersion="30"`
  to both legacy location permissions; the BLE-pair entries and the
  `bluetooth_le` `uses-feature` are untouched. Plugin scope, consuming apps
  inherit the cap.
- **Info.plist insertion is correct.** `NSBluetoothAlwaysUsageDescription` /
  the description string land between `LSRequiresIPhoneOS` and
  `UIApplicationSceneManifest` (lines 29–30) — alphabetical order is
  preserved (L < N < U).
- **Permission helper logic mirrors the plan.** iOS short-circuit, unconditional
  three-permission request, `permanentlyDenied` checked before plain `denied`
  (deliberate ordering captured in an inline comment), `openAppSettings()`
  called without a mounted guard (correct — no `context` access), `_showError`
  guarded by a mounted check (correct — touches `context`).
- **Inline comments explain *why*, not *what*.** The block at
  `device_screen.dart:42-52` accurately describes the API 26–30 vs API 31+
  split and explicitly calls out that `neverForLocation` is *not* what makes
  `locationWhenInUse` auto-grant (the manifest cap is) — directly addressing
  reviewer 2's critical finding.
- **`onPressed: _scan` lands cleanly under current lints.**
  `example/analysis_options.yaml` only includes `flutter_lints/flutter.yaml`
  and adds no rules, so neither `discarded_futures` nor `unawaited_futures` is
  enabled and Dart's `Future<void> Function() → VoidCallback` covariance is
  used as intended.
- **Pubspec entry is in the right place.**
  `permission_handler: ^11.4.0` is appended to the runtime `dependencies:`
  block after `wakelock_plus`, not into `dev_dependencies`. Lockfile resolves
  to a single 11.4.0 line and no transitive conflicts.
- **iOS deployment target is 13.0.** All three build configurations report
  `IPHONEOS_DEPLOYMENT_TARGET = 13.0`, so `NSBluetoothAlwaysUsageDescription`
  alone covers the iOS surface. No deprecated key is needed.

## Verdict

iOS surface and API 26–30 Android path look correct and reversible.

Concern 1 (Android 12+ behavior of the capped-manifest + `locationWhenInUse`
request combination) needs a real-device smoke test before this can be
considered safe to ship to Android users; the implementation is right per the
plan, but the plan's runtime assumption deserves to be confirmed empirically
because the failure mode is silent and global on Android 12+.

Concern 2 (missing `mounted` guard before `setState` in `_scan`) is a
straightforward post-implementation fix and should be made before landing.

Concern 3 is informational.
