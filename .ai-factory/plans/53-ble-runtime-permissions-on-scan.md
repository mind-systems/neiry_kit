# Plan: BLE runtime permissions on Scan

## Context
The example app's Device screen kicks off a BLE scan without requesting Android runtime permissions or declaring an iOS Bluetooth usage description, causing `SecurityException: Need ACCESS_FINE_LOCATION` on Android 8–11 and a `CBCentralManager` crash on iOS 13+. This milestone wires `permission_handler` into the Scan flow, caps the plugin's legacy location permissions to API 30 so `locationWhenInUse` auto-grants on Android 12+, and adds the iOS `NSBluetoothAlwaysUsageDescription` key. (Note: `example/android/app/build.gradle.kts` pins `minSdk = 26`, so the reachable Android range is API 26+; the legacy location path covers API 26–30 and the new BLE permissions cover API 31+.)

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Plugin manifest fix, dependency, and iOS metadata

- [x] **Task 1: Cap legacy location permissions to API 30 in the plugin manifest**
  Files: `android/src/main/AndroidManifest.xml`
  Add `android:maxSdkVersion="30"` to the two legacy location declarations so they no longer get merged into consuming apps on Android 12+. After the edit the relevant lines must read:
  ```xml
  <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"
      android:maxSdkVersion="30" />
  <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"
      android:maxSdkVersion="30" />
  ```
  Leave the `BLUETOOTH_SCAN` / `BLUETOOTH_CONNECT` / `BLUETOOTH` / `BLUETOOTH_ADMIN` / `uses-feature` entries untouched. This is what actually makes `Permission.locationWhenInUse.request()` auto-grant on API 31+ (the permission no longer exists in the merged manifest for those SDK levels). `android:usesPermissionFlags="neverForLocation"` on `BLUETOOTH_SCAN` does **not** suppress the location runtime prompt — it only tells the OS the app will not derive physical location from BLE results. Without this cap, the helper in Task 3 would show an unintended location prompt on Android 12+ and, if denied, block scanning with a misleading toast.

- [x] **Task 2: Add `permission_handler` dependency** (depends on Task 1)
  Files: `example/pubspec.yaml`
  Add `permission_handler: ^11.4.0` to the `dependencies:` section of `example/pubspec.yaml`. Place it next to the other runtime dependencies (after `wakelock_plus: ^1.2.0`). Do not modify `dev_dependencies`. After editing, the file must remain valid YAML — preserve the existing indentation style (two spaces). Pin the single concrete version `^11.4.0` and do **not** perform a conditional bump based on `flutter pub outdated`; if a newer patch is needed later that is a separate maintenance ticket. Run `flutter pub get` from `example/` to confirm the lockfile resolves. Note: the example app's own `example/android/app/src/main/AndroidManifest.xml` does **not** need any new `<uses-permission>` entries — the Android Gradle Plugin manifest merger pulls them from the plugin's `android/src/main/AndroidManifest.xml`. Do not duplicate permission entries in the example manifest.

- [x] **Task 3: Add `NSBluetoothAlwaysUsageDescription` to iOS Info.plist**
  Files: `example/ios/Runner/Info.plist`
  Inside the top-level `<dict>` of `example/ios/Runner/Info.plist`, add a new key/value pair:
  - `<key>NSBluetoothAlwaysUsageDescription</key>`
  - `<string>This app uses Bluetooth to connect to Neiry EEG devices.</string>`
  Place the entry alphabetically among the existing keys (between `LSRequiresIPhoneOS` and `UIApplicationSceneManifest`). Required for iOS 13+; without it `CBCentralManager` crashes on first use. No runtime permission call is needed on iOS — the OS shows the dialog automatically when the SDK touches Bluetooth. `NSBluetoothAlwaysUsageDescription` is the correct key for iOS 13+ since this app is a BLE central; the deprecated `NSBluetoothPeripheralUsageDescription` does not apply. Before relying on this, spot-check the example's iOS deployment target:
  ```sh
  grep IPHONEOS_DEPLOYMENT_TARGET example/ios/Runner.xcodeproj/project.pbxproj
  ```
  If the target is ≥ 13.0 (the Flutter 3.x default), no further key is required. If it is somehow below 13.0, also add `NSBluetoothPeripheralUsageDescription` with the same description string.

### Phase 2: Runtime permission gate on Scan

- [x] **Task 4: Implement `_checkAndRequestPermissions()` helper** (depends on Tasks 1 and 2)
  Files: `example/lib/screens/device_screen.dart`
  Add the following imports at the top of the file:
  - `import 'dart:io' show Platform;`
  - `import 'package:permission_handler/permission_handler.dart';`

  Add a private `Future<bool> _checkAndRequestPermissions() async` method to `_DeviceScreenState` with this exact logic:

  1. **iOS short-circuit.** `if (!Platform.isAndroid) return true;` — iOS handles its prompt via the Info.plist key added in Task 3.
  2. **Build the permission list unconditionally on Android:**
     ```dart
     final permissions = <Permission>[
       Permission.bluetoothScan,
       Permission.bluetoothConnect,
       Permission.locationWhenInUse,
     ];
     ```
     Add a brief comment explaining: requesting all three is correct on every supported API level — on Android 12+ the BLE pair is required and `locationWhenInUse` auto-grants because the plugin manifest caps `ACCESS_FINE_LOCATION` / `ACCESS_COARSE_LOCATION` with `android:maxSdkVersion="30"` (see Task 1), so those permissions don't exist in the merged manifest at API 31+; on Android 8–11 only `locationWhenInUse` is required and the BLE pair is auto-granted by `permission_handler` because the corresponding runtime permissions don't exist on those API levels. We deliberately do **not** introduce `device_info_plus` for SDK-level branching — adding a new dependency just to gate platform code is unnecessary when `permission_handler` already handles the no-op cases correctly. (Specifically: do not state that `neverForLocation` is what makes `locationWhenInUse` auto-grant — it isn't. The `maxSdkVersion="30"` cap is.)
  3. **Request:** `final statuses = await permissions.request();`
  4. **Check `permanentlyDenied` first** (this ordering is deliberate — keep it as written; do not reorder in future edits): if any status in `statuses.values` is `PermissionStatus.permanentlyDenied`, call `await openAppSettings();` and `return false;`. No `mounted` guard is required here because no `context` is touched between the `await` and the return.
  5. **Then check plain denied / restricted / limited:** if any status is not `PermissionStatus.granted`, then:
     ```dart
     if (!mounted) return false;
     _showError('Bluetooth permissions required');
     return false;
     ```
     The `mounted` guard is required here because `_showError` touches `context`. On first denial Android returns `denied` (not `permanentlyDenied`), so this branch fires and the user can retry by tapping Scan again.
  6. Else: `return true;`

  **Mounted-guard policy for this method (be precise — do not sprinkle guards after every `await`):**
  - After `permissions.request()`: a guard is needed only before the `_showError` call in step 5.
  - After `openAppSettings()` in step 4: **no** guard needed (no `context` touch).

- [x] **Task 5: Gate `_scan()` on the permission helper** (depends on Task 4)
  Files: `example/lib/screens/device_screen.dart`
  Convert `void _scan()` to `Future<void> _scan() async`. Before the existing `final params = (_selectedType, _searchTime);` line, call `if (!await _checkAndRequestPermissions()) return;`. Keep the rest of the body unchanged (the `invalidate` + `setState` block).

  **Button call site.** `ElevatedButton.onPressed` accepts both `VoidCallback` and a `Future<void> Function()` thanks to Dart's void-return-type covariance, so `onPressed: _scan` still compiles. The project depends on `flutter_lints` in `dev_dependencies`, but its default ruleset does **not** enable `discarded_futures` or `unawaited_futures`. Before assuming a lint will fire, check `example/analysis_options.yaml` (if it exists) for any `linter: rules:` block that explicitly enables either rule. After the change, run `flutter analyze` on `example/`. If a lint fires:
  - Preferred: wrap with a sync trampoline at the call site — `onPressed: () { _scan(); }`.
  - Alternatively: add `// ignore: discarded_futures` on the `onPressed: _scan` line.

  If no lint fires (the expected outcome under the current ruleset), leave `onPressed: _scan` as-is.

## Commit Plan
- **Commit 1** (after tasks 1–3): "Add BLE permission manifest cap, permission_handler dependency, and iOS Bluetooth usage description"
- **Commit 2** (after tasks 4–5): "Gate Scan on Android runtime BLE permissions in the example app"
