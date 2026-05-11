# Plan Review 3: 53-ble-runtime-permissions-on-scan

**Plan reviewed:** `.ai-factory/plans/53-ble-runtime-permissions-on-scan.md`
**Risk Level:** 🟢 Low

## Context Gates

- **Architecture (`.ai-factory/ARCHITECTURE.md`)** — OK. The plan stays inside
  `android/src/main/AndroidManifest.xml` (plugin) and three files under the
  example app (`example/pubspec.yaml`, `example/ios/Runner/Info.plist`,
  `example/lib/screens/device_screen.dart`). These are the documented places
  for plugin manifest and end‑to‑end SDK demo, no layering breach.
- **Rules (`.ai-factory/RULES.md`)** — file not present (informational; no WARN).
- **Roadmap (`.ai-factory/ROADMAP.md`)** — OK. The unchecked milestone
  "BLE runtime permissions on Scan" matches the plan title and scope.

## Summary vs Review 2

Plan v3 addresses every issue raised in review 2:

- **Critical issue 1 (review 2):** Task 1 now caps the two legacy location
  permissions in the plugin manifest with `android:maxSdkVersion="30"`. The
  rationale is stated correctly: it is the cap — not `neverForLocation` — that
  makes `Permission.locationWhenInUse.request()` auto-grant on API 31+.
  Task 4's embedded comment was rewritten to match this fact, and the plan
  explicitly warns against re-introducing the old (incorrect) wording in
  future edits.
- **Issue 2 (version probe):** removed. Task 2 now pins `^11.4.0` and
  forbids the conditional bump based on `flutter pub outdated`.
- **Issue 3 (`flutter_lints` behavior):** Task 5 now says the default
  ruleset does not enable `discarded_futures` / `unawaited_futures` and
  instructs the implementer to check `example/analysis_options.yaml` for any
  rule overrides before assuming a lint will fire.
- **Issue 4 (iOS deployment target):** Task 3 adds the
  `grep IPHONEOS_DEPLOYMENT_TARGET …` spot‑check and a fallback for the
  unlikely `< 13.0` case.
- **Issue 5 (example manifest untouched):** Task 2 explicitly states the
  example's own `AndroidManifest.xml` needs no `<uses-permission>` entries
  because AGP merges them from the plugin manifest.

## Verification against the repo

All assumptions in the plan were checked against the current code:

- `android/src/main/AndroidManifest.xml` currently declares
  `ACCESS_FINE_LOCATION` and `ACCESS_COARSE_LOCATION` without
  `maxSdkVersion`, alongside `BLUETOOTH_SCAN` (with `neverForLocation`),
  `BLUETOOTH_CONNECT`, `BLUETOOTH`, `BLUETOOTH_ADMIN`, and the
  `bluetooth_le` `uses-feature`. Task 1's edit lands cleanly.
- `example/pubspec.yaml` shows `wakelock_plus: ^1.2.0` as the last runtime
  dep at line 38; Task 2's insertion point ("after `wakelock_plus: ^1.2.0`")
  is correct and indentation is two spaces.
- `example/ios/Runner/Info.plist` has `LSRequiresIPhoneOS` at line 27 and
  `UIApplicationSceneManifest` at line 29 — `N…` sorts between them, so the
  planned alphabetical placement is right.
- `grep IPHONEOS_DEPLOYMENT_TARGET …/Runner.xcodeproj/project.pbxproj`
  returns `13.0` for every configuration, so the
  `NSBluetoothPeripheralUsageDescription` fallback in Task 3 won't be needed
  in practice.
- `example/android/app/build.gradle.kts` line 27 confirms `minSdk = 26`, so
  the API 26–30 / 31+ branch‑free strategy is structurally correct.
- `example/analysis_options.yaml` enables only
  `package:flutter_lints/flutter.yaml` with an empty `linter.rules:` block,
  so `discarded_futures`/`unawaited_futures` will not fire and `onPressed:
  _scan` should land without ignores. The plan's fallback advice (sync
  trampoline or `// ignore: discarded_futures`) remains correct as defence in
  depth.
- `example/lib/screens/device_screen.dart` line 34 has `void _scan()` with
  the exact body the plan describes (`final params = (_selectedType,
  _searchTime);` followed by an `invalidate`/`setState` block). Line 170–173
  has `ElevatedButton(onPressed: _scan, child: const Text('Scan'))`. Both
  insertion points in Tasks 4 and 5 match the live source.
- `_showError(String message)` already exists at line 97 with a `mounted`
  guard, so reusing it is correct and the additional guard before the
  `_showError` call in step 5 is redundant defence — harmless and consistent
  with the policy stated in the plan.

## Minor Notes (non‑blocking)

- Task 5 calls the assignment compatibility "Dart's void‑return‑type
  covariance." The precise rule is that any function type is assignable to
  `void Function(...)` because a `void` return type is allowed to discard the
  actual return — call it "void‑compatibility" if you want to be pedantic,
  but the conclusion (`onPressed: _scan` compiles) is correct.
- Step 5 of Task 4 only checks "not `PermissionStatus.granted`." On Android
  this covers `denied`, `restricted`, and (theoretically) `limited`. For BLE
  permissions on Android none of those edge statuses should appear in
  practice, but the catch‑all branch handles them safely — no change needed.

## Positive Notes

- The Phase 1 ordering (manifest cap → dependency → iOS plist) before Phase 2
  (helper → gate) puts the foundational fixes first, and the explicit
  dependencies on Tasks 1+2 in Task 4 reflect the fact that the helper's
  correctness depends on the manifest cap.
- The mounted‑guard policy is spelled out per `await` site, with an
  explicit note that `openAppSettings()` does not touch `context`.
- The `permanentlyDenied` check is intentionally placed before the generic
  "not granted" check, with a written rationale that protects the helper
  from a future refactor reordering the branches.
- The commit plan groups the configuration changes (Tasks 1–3) into one
  commit and the runtime gate (Tasks 4–5) into a second, which keeps the
  reverts surgical if anything regresses on a specific platform.

## Verdict

All prior review feedback has been incorporated, every file path and API
reference was verified against the current tree, and the remaining
remarks are stylistic. Plan is ready to implement.

PLAN_REVIEW_PASS
