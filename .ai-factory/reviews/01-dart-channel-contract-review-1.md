## Code Review: Dart Channel Contract

**Plan file:** `.ai-factory/plans/01-dart-channel-contract.md`
**Files reviewed:** `lib/src/channel/channel_names.dart`, `lib/src/channel/enums.dart`, `lib/neiry_kit.dart`, `test/channel_names_test.dart`, deleted `test/neiry_kit_test.dart`, deleted `test/neiry_kit_method_channel_test.dart`, `example/lib/main.dart`, `example/integration_test/plugin_integration_test.dart`
**Test result:** 48/48 pass (`flutter test test/channel_names_test.dart`)
**Analyzer result:** 3 errors, 1 warning, 5 info

### Issues

**1. Example app and integration test fail to compile (3 analyzer errors)**

`flutter analyze` reports 3 errors:

- `example/lib/main.dart:20` — `The method 'NeiryKit' isn't defined for the type '_MyAppState'`
- `example/integration_test/plugin_integration_test.dart:18` — `Undefined class 'NeiryKit'` and `The function 'NeiryKit' isn't defined`

Both files still reference the `NeiryKit` class that was removed from the barrel export. The plan (Task 5) correctly identified that `test/neiry_kit_test.dart` and `test/neiry_kit_method_channel_test.dart` needed deletion, but missed these two files in `example/`.

The example app is scaffolding from `flutter create --template=plugin` and uses the same `NeiryKit().getPlatformVersion()` pattern. After the barrel change, `import 'package:neiry_kit/neiry_kit.dart'` no longer provides `NeiryKit`.

**Fix:** Replace `example/lib/main.dart` with a minimal placeholder that imports the new barrel (confirming the export works) but doesn't call the removed `NeiryKit` class. Similarly, replace or delete `example/integration_test/plugin_integration_test.dart` — the `getPlatformVersion` integration test is meaningless now. The example app will be rebuilt from scratch in the "Example app" roadmap milestone anyway, so a minimal stub is appropriate.

**2. Analyzer warning: unused import in example app**

`example/lib/main.dart:5` — `Unused import: 'package:neiry_kit/neiry_kit.dart'`. This is a consequence of issue #1 — once the `NeiryKit` references are removed, the import becomes unused. The fix for issue #1 should resolve this too (either use the import for the new exports or remove it if the placeholder doesn't need it).

### Suggestions

**3. Dangling library doc comments (info-level)**

`lib/src/channel/channel_names.dart:3` and `lib/src/channel/enums.dart:4` — the file-level doc comments aren't attached to a `library` directive. This triggers `dangling_library_doc_comments`. Fix: either add `library;` after the doc comment, or convert the doc comments (`///`) to plain comments (`//`). Low priority — info-level lint, not an error.

**4. Unnecessary string interpolation in tests (info-level)**

`test/channel_names_test.dart:252,258,265` — `'${v.name}'` should be `v.name` (no interpolation needed when the expression is the entire string). Cosmetic only.

### Verification

- **MethodChannel IDs:** 8 constants, all match spec note. Prefixed `neiry_kit/`. No duplicates.
- **EventChannel IDs:** 26 constants, all match spec note exactly. Prefixed `neiry_kit/events/`. No duplicates. `cardioCalibratedEvent` included with appropriate comment about native confirmation.
- **Method names:** 4 classes (DeviceLocatorMethods, DeviceMethods, ClassifierMethods, NFBCalibratorMethods) — all method names match spec note. No duplicates within any class.
- **Argument keys:** 11 keys in NeiryArgs, all match spec + the 2 additional keys (channelName, index) referenced by method signatures.
- **Enums:** All 3 enums use enhanced enum syntax with `code` field. Values match SDK headers. `fromCode` includes descriptive error messages with the invalid code value. PPG indices correctly use 5/6 as confirmed by `CDevice.h`.
- **Barrel export:** Clean — exports `channel_names.dart` and `enums.dart` only. Old scaffolding removed.
- **Deleted tests:** Both old scaffolding test files properly removed. New test file covers all plan requirements (uniqueness, SDK int codes, round-trips, invalid input).
- **Test maintenance comment:** Present at top of `test/channel_names_test.dart`.
- **Enum file split:** Clean separation — `channel_names.dart` is pure string constants, `enums.dart` is enhanced enums with factories.

### Positive Notes

- Implementation is clean and matches the plan precisely.
- All 48 unit tests pass.
- Enum `fromCode` error messages include the rejected code value — good for debugging native bridge issues.
- The `cardioCalibratedEvent` note about native confirmation is present in the code comment.
- Test file includes count assertion (`ids.length == 26`) as a guard against accidentally losing an EventChannel constant.
