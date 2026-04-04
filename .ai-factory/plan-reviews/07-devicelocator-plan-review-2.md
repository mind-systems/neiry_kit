## Plan Review: 07-devicelocator (iteration 2)

**Plan:** DeviceLocator Dart API class
**Files Reviewed:** plan + `lib/src/channel/channel_names.dart`, `lib/src/channel/enums.dart`, `lib/src/models/device_info.dart`, `lib/neiry_kit.dart`, `lib/neiry_kit_method_channel.dart`, `lib/neiry_kit_platform_interface.dart`, `test/channel_names_test.dart`, `test/models_test.dart`, `.ai-factory/notes/03-dart-api-device.md`, `.ai-factory/ARCHITECTURE.md`, `.ai-factory/ROADMAP.md`, `.ai-factory/DESCRIPTION.md`
**Risk Level:** 🟢 Low

### Context Gates
- **ARCHITECTURE.md:** OK — `lib/src/api/device_locator.dart` matches the folder structure. Dependency direction (`api/ → channel/ + models/`) is respected. Barrel export via `neiry_kit.dart` follows key principle #4.
- **RULES.md:** WARN — file not present.
- **ROADMAP.md:** OK — plan maps to the "DeviceLocator" milestone under "Dart API." All behaviors described in the milestone text (singleton factory, `requestDevices` stream, `createDevice`, `update`, `dispose`, cancel-on-overlap, `setSingleThreaded`) are covered by the plan.

### Review-1 Issue Resolution

All 6 issues from the first review are resolved:

1. ~~`_nativeReady` await inside `requestDevices`~~ — Fixed. `requestDevices` explicitly does NOT await `_nativeReady`; relies on FIFO ordering with a documented code comment.
2. ~~Broken singleton on native create failure~~ — Fixed. `.catchError()` on `_nativeReady` nulls `_instance`, allowing retry.
3. ~~`dispose()` return type ambiguous~~ — Fixed. Explicitly returns `Future<void>` with await semantics documented.
4. ~~`dispose()` while `_nativeReady` pending~~ — Fixed. `dispose()` awaits `_nativeReady` before sending destroy; catches error to skip destroy if create failed.
5. ~~Orphaned `requestDevices` constant~~ — Fixed. Explicit removal with explanation.
6. ~~`EventChannel` not cached~~ — Fixed. Stored as `static const _deviceListEventChannel`.

### Critical Issues

None.

### Suggestions

**1. Task 1 must update `test/channel_names_test.dart` to keep existing tests compiling**

The plan removes `DeviceLocatorMethods.requestDevices` and adds `create`, `createDevice`, `dispose`, `update` to `DeviceLocatorMethods`, plus `logDirectory` to `NeiryArgs`. The existing test file references the removed constant at line 120:

```dart
// test/channel_names_test.dart:119-128
group('DeviceLocatorMethods — unique', () {
  final names = [
    DeviceLocatorMethods.requestDevices,  // ← will not compile after removal
    DeviceLocatorMethods.setSingleThreaded,
    DeviceLocatorMethods.setLogLevel,
    DeviceLocatorMethods.getVersionString,
  ];
```

After Task 1, `flutter test` and `flutter analyze` will fail because of this dangling reference. This is not "adding new tests" (which the plan's `Testing: no` setting would skip) — it is keeping existing tests compilable after a contract change.

**Fix:** Add a sub-step to Task 1: update the `DeviceLocatorMethods` uniqueness test list to remove `requestDevices` and add the four new constants (`create`, `createDevice`, `dispose`, `update`). Also add `NeiryArgs.logDirectory` to the `NeiryArgs` uniqueness test list (line 192-208).

### Positive Notes

- The iteration cleanly addresses every issue from review-1 without overcomplicating the design.
- The FIFO ordering rationale for skipping `_nativeReady` in `requestDevices` is sound and the plan correctly mandates a code comment documenting the assumption.
- The `_nativeReady` failure recovery pattern (`.catchError()` nulling `_instance`) is the right approach — it enables retry without requiring consumers to manually `dispose()` a broken instance.
- The `identical(_scanSubscription, thisSub)` guard in `onCancel`/`onDone` is a subtle but correct detail that prevents stale subscription cancellation from killing an active scan.
- The `dispose()` design is thorough: check → flag → cancel subscription → await native ready (with error catch) → native destroy → null singleton.
- Channel constant names are consistent with existing conventions in `channel_names.dart`.
- Deferring the `Device` return from `createDevice` to a later milestone is the right scope boundary.

PLAN_REVIEW_PASS
