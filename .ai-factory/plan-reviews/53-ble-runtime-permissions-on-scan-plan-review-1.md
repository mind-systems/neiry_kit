# Plan Review: 53-ble-runtime-permissions-on-scan

**Plan reviewed:** `.ai-factory/plans/53-ble-runtime-permissions-on-scan.md`
**Risk Level:** 🟡 Medium

## Context Gates

- **Architecture (`.ai-factory/ARCHITECTURE.md`)** — OK. Changes are scoped to the
  example app (`example/lib/screens/`, `example/pubspec.yaml`, `example/ios/Runner/Info.plist`),
  which is the documented home for example UI. No dependency-rule violations.
- **Rules (`.ai-factory/RULES.md`)** — file not present (informational; no WARN).
- **Roadmap (`.ai-factory/ROADMAP.md`)** — OK. The unchecked milestone `BLE runtime
  permissions on Scan` matches the plan title and scope verbatim.

## Critical Issues

None blocking, but Task 3 has a clarity defect that will mislead the implementer
(see below).

## Issues / Concerns

### 1. Task 3 is internally contradictory and will confuse the implementer

The task body simultaneously prescribes three different strategies:

1. A platform/API-level conditional list (`bluetoothScan/Connect` on API ≥31,
   `locationWhenInUse` on API 6–11).
2. A warning against `DeviceInfoPlugin` plus a half-finished suggestion to "use
   `Platform.isAndroid` from `dart:io` and check `int.parse(...sdkInt)` only if
   necessary".
3. A final "simplest correct approach: always request all three permissions on
   Android" recommendation.

Pick one and remove the rest. The third option (`[Permission.bluetoothScan,
Permission.bluetoothConnect, Permission.locationWhenInUse]` unconditionally on
Android, short-circuit `true` on iOS) is the right one and is consistent with
how `permission_handler` behaves — pre-Android-12 OS auto-grants
`bluetoothScan/Connect`, post-Android-12 with the plugin manifest's
`neverForLocation` flag auto-grants `locationWhenInUse`. Rewrite the task to
state this single strategy unambiguously.

### 2. "Detect the Android API level via `DeviceInfoPlugin` is **not** allowed here"

The phrasing reads as a hard prohibition but the intent is "not necessary".
Reword to "we don't want a new dependency, so do not introduce
`device_info_plus`" — otherwise a reader might assume there's a real policy ban
to discover.

### 3. `Permission.permanentlyDenied` semantics on first request

The helper returns `false` and calls `openAppSettings()` when any status is
`permanentlyDenied`. On first launch, Android never returns `permanentlyDenied`
until the user has declined at least once with "Don't ask again" (or
twice without checking, on Android 11+). The behavior the plan describes is
correct, but the order of checks matters: when the user denies once,
`permission_handler` will return `denied`, not `permanentlyDenied`, so the
`_showError` branch will fire and the user can retry. Good — but make the
ordering explicit in the task: check `permanentlyDenied` first, then plain
`denied`, then granted. The current bullet ordering already does this; just
state that the order is deliberate so a future edit doesn't reverse them.

### 4. Mounted-guard placement after `await ... request()`

Task 3 says "use `if (!mounted) return false;` guards after each `await` before
touching `context`". Be specific about where this is actually needed:

- `requested.request()` — no `context` touch right after, but the next branch
  may call `_showError` which uses `context`. Guard required there.
- `openAppSettings()` — does not touch `context`; no guard needed.
- Before `_showError(...)` — guard required.

As written, "after each `await`" is over-broad and may produce an unnecessary
guard before `openAppSettings()`. Restating it precisely will avoid pointless
returns.

### 5. Task 4 — `ElevatedButton.onPressed` signature claim

The note "Flutter accepts both `VoidCallback` and `Future<void>` returning
closures for `onPressed`" is true (Dart's void-return-type covariance), but a
project lint set (`flutter_lints` is in `dev_dependencies`) may flag the
unawaited future via `unawaited_futures` / `discarded_futures`. Verify after the
change and, if a lint fires, either add `// ignore: discarded_futures` at the
call site or wrap with a sync trampoline (`onPressed: () { _scan(); }`).

### 6. `permission_handler: ^11.3.1` version pin

11.3.1 exists, but the package has shipped 11.4.x with relevant Android v34/v35
fixes. Either bump to the latest 11.x patch (`^11.4.0` at time of writing) or
leave a note to verify with `flutter pub outdated` post-install. Not a blocker
but worth flagging since this is a permission-sensitive dep.

## Things the plan got right (positive notes)

- **iOS plist key choice is correct.** `NSBluetoothAlwaysUsageDescription` is
  the right key for iOS 13+; the deprecated `NSBluetoothPeripheralUsageDescription`
  is not applicable since the app is a BLE central, not peripheral.
- **iOS plist insertion point is alphabetically valid** — between
  `LSRequiresIPhoneOS` and `UIApplicationSceneManifest` is exactly where an
  `NS…` key sorts, matching the file's existing alphabetical ordering.
- **Manifest permissions already covered by plugin.** The plugin's own
  `android/src/main/AndroidManifest.xml` already declares
  `BLUETOOTH_SCAN` (`neverForLocation`), `BLUETOOTH_CONNECT`, `BLUETOOTH`,
  `BLUETOOTH_ADMIN`, `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`, and the
  `bluetooth_le` `uses-feature`. AGP merges these into the example app's
  manifest, so the plan correctly avoids touching
  `example/android/app/src/main/AndroidManifest.xml`. Confirm this stays true
  by running `flutter build apk` once and inspecting the merged manifest, but
  no plan change is needed.
- **`example/android/app/build.gradle.kts` has `minSdk = 26`**, so the Android
  6 (API 23) edge of the milestone description is moot — the actually-reachable
  range is API 26–30 for the legacy location path and API 31+ for the new BLE
  permissions. Plan logic still handles both, fine.
- **No interaction with `deviceScanProvider` / `activeDeviceProvider`.** The
  Riverpod state machine is unchanged; the permission check is a pure gate in
  front of the existing invalidate/setState. Clean and minimal.
- **iOS-side reasoning is correct.** No runtime call is required; iOS shows the
  dialog automatically when `CBCentralManager` is first touched by the SDK,
  provided the plist key is present.

## Suggested rewrite of Task 3 (for clarity)

> **Task 3: Implement `_checkAndRequestPermissions()` helper** (depends on Task 1)
> Files: `example/lib/screens/device_screen.dart`
> Add `import 'dart:io' show Platform;` and
> `import 'package:permission_handler/permission_handler.dart';`. Add a private
> `Future<bool> _checkAndRequestPermissions() async` to `_DeviceScreenState`:
> 1. If `!Platform.isAndroid` → return `true` (iOS handles its prompt via the
>    Info.plist key).
> 2. Define
>    `final permissions = [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.locationWhenInUse];`
>    Comment: on Android 12+ the BLE pair is required and `locationWhenInUse`
>    is auto-granted because the plugin manifest declares
>    `BLUETOOTH_SCAN` with `neverForLocation`; on Android 8–11 only
>    `locationWhenInUse` is required and the BLE pair is auto-granted. So
>    requesting all three is correct on every supported API level.
> 3. `final statuses = await permissions.request();`
> 4. If any status is `permanentlyDenied` → `await openAppSettings();
>    return false;` (no context touch — no `mounted` guard required).
> 5. Else if any status is not `granted` →
>    `if (!mounted) return false; _showError('Bluetooth permissions required'); return false;`
> 6. Else return `true`.

## Verdict

The plan is structurally sound and the file/path choices are accurate. The only
substantive defect is Task 3's contradictory wording, which is a clarity issue,
not a correctness one — an implementer following any of the three offered
strategies would land on a working result. Fix Task 3's wording (and ideally
adopt the rewrite above), tighten the version pin, and the plan is ready.
