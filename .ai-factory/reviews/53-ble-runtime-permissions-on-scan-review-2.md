# Code Review 2: 53-ble-runtime-permissions-on-scan

**Plan:** `.ai-factory/plans/53-ble-runtime-permissions-on-scan.md`
**Previous review:** `.ai-factory/reviews/53-ble-runtime-permissions-on-scan-review-1.md`
**Files changed since review 1:**
- `example/lib/screens/device_screen.dart` — added a `mounted` guard in `_scan` after the permission await

All other code files (`android/src/main/AndroidManifest.xml`,
`example/ios/Runner/Info.plist`, `example/pubspec.yaml`,
`example/pubspec.lock`) are unchanged since review 1; their positive notes
still stand.

## What changed since review 1

`device_screen.dart:83-92`:

```dart
Future<void> _scan() async {
  if (!await _checkAndRequestPermissions()) return;
  if (!mounted) return;                       // ← added
  final params = (_selectedType, _searchTime);
  if (_scanParams == params) {
    ref.invalidate(deviceScanProvider(params));
  }
  setState(() => _scanParams = params);
}
```

This resolves **Concern 2** from review 1: `setState` is no longer reachable
on a disposed state if the user navigates away from the Device screen while
the OS permission dialog is up. Implementation is the minimal, correct fix.

## Remaining concerns

### 1. Android 12+ runtime behavior of `Permission.locationWhenInUse` after the manifest cap — still unverified

(Carried over from review 1, **not** addressed by code changes; flagged here
again because no empirical evidence has been recorded in the plan or in any
review note.)

The plan and the inline comment in `_checkAndRequestPermissions` assert that
on API 31+, `Permission.locationWhenInUse.request()` returns
`PermissionStatus.granted` because `ACCESS_FINE_LOCATION` /
`ACCESS_COARSE_LOCATION` are capped at `maxSdkVersion="30"` in the plugin
manifest and therefore not present in the merged manifest at API 31+. If
`permission_handler_android` instead returns `denied` for a location group
with zero declared manifest entries on the current SDK level, the helper will
silently fall into the `_showError('Bluetooth permissions required')` branch
on every modern Android device — even though both BLE permissions were
granted.

This is the highest-risk remaining unknown in the changeset. Recommendation
unchanged: smoke-test on an Android 12+ emulator or device before the example
app is used on real Android 12+ hardware. The iOS path and the legacy
Android-8–11 path remain straightforward.

If the smoke test fails, the cleanest fix is to drop
`Permission.locationWhenInUse` from the requested list on API 31+ — which is
exactly what would have required `device_info_plus`. The current code is
correct for the plan's stated assumption; the question is only whether the
assumption holds.

### 2. Concurrent Scan taps still produce two parallel permission flows

(Carried over from review 1, informational only.) The Scan button is not
disabled while `_checkAndRequestPermissions()` is in flight, so a rapid
double-tap will launch two concurrent flows. `permission_handler` dedupes
the Android dialog, but a first-time denial would queue two
`_showError` snackbars. Acceptable as-is; flag only if Scan UX becomes a
concern.

## Positive notes new in this review

- **Post-await mounted guard in `_scan` is placed correctly.** It sits after
  the bool check (so a `false` return path still short-circuits cleanly) but
  before *any* `ref` or `setState` access (so Riverpod and state mutation are
  both protected). Single guard, no duplication.

## Verdict

The single actionable item from review 1 has been fixed. The remaining
finding (Concern 1) is an empirical question about
`permission_handler_android` behavior — not a code defect — and the
implementation matches the plan exactly. It is safe to land on iOS today; an
Android 12+ smoke test should accompany the first time this code is exercised
on a real device.

No new blocking issues introduced by the latest change.
