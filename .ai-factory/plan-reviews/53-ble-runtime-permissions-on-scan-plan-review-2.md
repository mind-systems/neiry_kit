# Plan Review 2: 53-ble-runtime-permissions-on-scan

**Plan reviewed:** `.ai-factory/plans/53-ble-runtime-permissions-on-scan.md`
**Risk Level:** 🟡 Medium

## Context Gates

- **Architecture (`.ai-factory/ARCHITECTURE.md`)** — OK. The example app is the
  documented place for end-to-end SDK demos, and the plan stays inside
  `example/lib/screens/`, `example/pubspec.yaml`, and `example/ios/Runner/Info.plist`.
  No layering or dependency-rule violations.
- **Rules (`.ai-factory/RULES.md`)** — file not present (informational; no WARN).
- **Roadmap (`.ai-factory/ROADMAP.md`)** — OK. The unchecked milestone "BLE
  runtime permissions on Scan" matches the plan title and scope verbatim.

## Summary vs Review 1

The plan now resolves every clarity issue raised in review 1:

- Task 3 collapsed to a single strategy (request all three on Android, iOS
  short‑circuit) — contradictions removed.
- `device_info_plus` framed as "we don't add a new dep" rather than a hard ban.
- `permanentlyDenied` ordering called out explicitly as deliberate.
- Mounted‑guard policy spelled out per `await`, with both call sites annotated
  (no guard before `openAppSettings()`, guard required before `_showError`).
- Lint fallback for `onPressed: _scan` documented (sync trampoline or
  `// ignore: discarded_futures`).
- Version bumped to `^11.4.0` with a `flutter pub outdated` verification step.

What follows are the remaining concerns surfaced by reading the plan against
the actual repo state.

## Critical Issues

### 1. `Permission.locationWhenInUse` will NOT auto‑grant on Android 12+ as Task 3 claims

The comment Task 3 instructs the implementer to embed in the code says:

> on Android 12+ the BLE pair is required and `locationWhenInUse` is
> auto-granted (the plugin manifest declares `BLUETOOTH_SCAN` with
> `neverForLocation`)

This is incorrect, and the plan inherits the same incorrect claim from
review 1's "suggested rewrite." Two independent things are being conflated:

- `android:usesPermissionFlags="neverForLocation"` on `BLUETOOTH_SCAN` only
  tells the OS the app will not derive physical location from BLE results. It
  does **not** influence whether a request for `ACCESS_FINE_LOCATION` /
  `ACCESS_COARSE_LOCATION` shows a runtime dialog.
- `permission_handler.Permission.locationWhenInUse.request()` returns
  `granted` without prompting only when the corresponding manifest entries are
  either absent or capped via `android:maxSdkVersion="30"`.

The plugin's manifest at `android/src/main/AndroidManifest.xml` currently
declares both location permissions **without** any `maxSdkVersion` attribute:

```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
```

These get merged into the example app via AGP manifest merger. As a result,
on an Android 12+ device the helper as planned will:

1. Show the BLE scan/connect dialog (correct).
2. Then show a location dialog (unintended — the whole point of
   `neverForLocation` was to avoid this).

This is more than a UX wart. If the user denies the location prompt on
Android 12+:

- Both BLE permissions are `granted` and a scan would technically work.
- But the helper sees one `denied` status and falls into the
  `_showError('Bluetooth permissions required')` branch and returns `false`,
  blocking the scan with a misleading message.

**Remediation (pick one — option A is the right one):**

A. Add `android:maxSdkVersion="30"` to the two location declarations in
   `android/src/main/AndroidManifest.xml`:

   ```xml
   <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"
       android:maxSdkVersion="30" />
   <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"
       android:maxSdkVersion="30" />
   ```

   With this cap, `Permission.locationWhenInUse` auto‑grants on API 31+
   (because the permission no longer exists for that SDK level in the merged
   manifest), and the comment in `_checkAndRequestPermissions()` becomes
   accurate. This is also the Android 12+ best practice for apps that only
   need location for legacy BLE scanning.

B. Keep manifest as is and accept that Android 12+ users see a location
   prompt that, if denied, blocks scanning. Update the comment to state this
   honestly. Not recommended.

C. Reintroduce SDK‑level branching with `device_info_plus`. The plan
   explicitly rejected this and option A is cleaner; mention only for
   completeness.

Add a new task (likely Phase 0 or 1) that performs change (A) before Task 3
lands, and rephrase Task 3's embedded comment accordingly.

## Issues / Concerns

### 2. Task 1's "post‑install version probe" is a minor process wart

Task 1 says: after editing pubspec, run `flutter pub outdated` and bump the
constraint if a newer 11.x patch ships. In a deterministic plan/implement
flow this turns a one‑shot edit into an "edit, run, maybe re‑edit" loop and
will not be replayable from the commit alone. Pin a single concrete version
(`^11.4.0` is fine) and drop the conditional bump — if a newer patch needs
to be picked up, that's a separate maintenance ticket. Non‑blocking.

### 3. Task 4 — `flutter_lints` does not actually enable `discarded_futures`

`flutter_lints: ^6.0.0` is in `dev_dependencies`, but the `flutter`
recommended rule set does **not** enable `discarded_futures` or
`unawaited_futures` by default. Unless the project has a custom
`analysis_options.yaml` enabling those rules, neither lint will fire on
`onPressed: _scan`. The plan's fallback advice is still correct as defence in
depth — just note that under the current ruleset the lint is unlikely to
trigger, so the simple `onPressed: _scan` form should land cleanly. Verifying
the project's `analysis_options.yaml` once is worth a one‑line addition to
the task.

### 4. iOS deployment target not verified for `NSBluetoothAlwaysUsageDescription`

The plan correctly notes `NSBluetoothAlwaysUsageDescription` is the iOS 13+
key. The example's `Podfile` / `project.pbxproj` deployment target is not
checked in the plan. If it ever sits below iOS 13, the legacy
`NSBluetoothPeripheralUsageDescription` key would also be needed. Spot‑check
the deployment target during implementation (`grep IPHONEOS_DEPLOYMENT_TARGET
example/ios/Runner.xcodeproj/project.pbxproj`); if it is ≥ 13.0 (very
likely given Flutter 3.x defaults), nothing else is required.

### 5. The example app's own `AndroidManifest.xml` is intentionally untouched

Worth stating explicitly in the plan that the example's
`example/android/app/src/main/AndroidManifest.xml` does **not** need new
`<uses-permission>` entries because AGP merges from the plugin's
`android/src/main/AndroidManifest.xml`. The plan implicitly relies on this
but never asserts it; an implementer who doesn't know AGP merge rules might
duplicate permission entries in the example manifest. One‑line note is
enough.

## Positive Notes

- **iOS plist key + alphabetical placement verified.** `LSRequiresIPhoneOS`
  is at line 27, `UIApplicationSceneManifest` at line 29 — `N` sorts between
  `L` and `U`, so the planned insertion point is correct.
- **No interaction with Riverpod providers.** `deviceScanProvider` and
  `activeDeviceProvider` are unchanged; the permission gate is a pure pre‑check
  in front of the existing `invalidate` + `setState`. Clean, minimal,
  reversible.
- **Plugin manifest already declares the BLE and legacy location permissions.**
  Confirmed by reading `android/src/main/AndroidManifest.xml`:
  `BLUETOOTH_SCAN` (with `neverForLocation`), `BLUETOOTH_CONNECT`,
  `BLUETOOTH`, `BLUETOOTH_ADMIN`, `ACCESS_FINE_LOCATION`,
  `ACCESS_COARSE_LOCATION`, plus `bluetooth_le` `uses-feature`. The plan is
  right not to duplicate these.
- **`minSdk = 26` confirmed in `example/android/app/build.gradle.kts`**, so
  the reachable range is API 26–30 (legacy location path) and 31+ (new BLE
  permissions). The plan's branch‑free strategy is structurally fine for
  this range *once* issue 1 is addressed.
- **Mounted‑guard policy is precise and correct.** The decision to skip the
  guard around `openAppSettings()` and require it only before `_showError`
  is right — `openAppSettings()` doesn't touch `context`.
- **Ordering rationale for `permanentlyDenied` vs `denied`** is stated
  explicitly, which protects the helper from a future refactor that reorders
  the checks.
- **Dart void‑covariance claim for `onPressed: _scan`** is accurate; a
  `Future<void> Function()` is assignable to `VoidCallback`.

## Verdict

The plan is structurally sound and resolves every wording defect from review
1, but issue 1 (incorrect `neverForLocation` ↔ `locationWhenInUse` claim)
is a real functional bug on Android 12+, not just a cosmetic comment: a user
who declines the unintended location prompt on a modern device will be
blocked from scanning with a misleading "Bluetooth permissions required"
toast even though Bluetooth permissions were granted.

Add the `android:maxSdkVersion="30"` cap to the two location permissions in
`android/src/main/AndroidManifest.xml` (as a new task or an addendum to Task
3), and update the inline comment in `_checkAndRequestPermissions()` to
reflect that this cap — not `neverForLocation` — is what makes
`locationWhenInUse` auto‑grant on API 31+. With that change, the plan is
ready to implement.
