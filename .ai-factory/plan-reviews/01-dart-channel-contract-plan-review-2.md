## Plan Review: Dart Channel Contract (Iteration 2)

**Plan file:** `.ai-factory/plans/01-dart-channel-contract.md`
**Files reviewed:** Plan, spec note (`01-channel-contract.md`), ARCHITECTURE.md, ROADMAP.md, DESCRIPTION.md, SDK HTML docs, all existing `lib/` and `test/` source files, `pubspec.yaml`, previous plan review
**Risk Level:** 🟢 Low

### Context Gates

- **Architecture:** PASS — File paths (`lib/src/channel/channel_names.dart`, `lib/src/channel/enums.dart`) match ARCHITECTURE.md folder structure. Dependency rule (`lib/src/channel/ → nothing`) is respected — both files are pure constants with no imports beyond `dart:core`. Barrel export via `lib/neiry_kit.dart` aligns with principle #4 ("the barrel export is the public API"). Splitting enums into a separate file from string constants is cleaner than the illustrative flat example and does not violate any architectural rule.
- **Rules:** WARN — No `.ai-factory/RULES.md` present (non-blocking).
- **Roadmap:** WARN — Two cosmetic discrepancies remain between roadmap milestone text and plan: (1) roadmap says `lib/src/channel_names.dart`, plan correctly uses `lib/src/channel/channel_names.dart` per architecture; (2) roadmap says "28 EventChannels", plan correctly uses 26 per spec. Both are documentation drift in the roadmap — the plan follows the authoritative sources (ARCHITECTURE.md and spec note). Neither affects implementation correctness.
- **Skill-context:** No `.ai-factory/skill-context/aif-review/SKILL.md` present — WARN (non-blocking).

### Previous Review Issues — Resolution Check

The first plan review raised 5 issues and 3 suggestions. Checking how this iteration addresses them:

1. **Existing tests will break (Issue #1)** — ✅ RESOLVED. Task 5 now explicitly deletes both `test/neiry_kit_test.dart` and `test/neiry_kit_method_channel_test.dart` with clear rationale (they import the removed `NeiryKit` class and will fail to compile).

2. **EventChannel count discrepancy (Issue #2)** — ✅ RESOLVED. Plan states 26, matches the spec exactly, and explicitly notes the roadmap says 28 but the spec enumerates 26. No placeholder padding.

3. **File path mismatch with roadmap (Issue #3)** — ✅ RESOLVED. Plan explicitly calls out the discrepancy in the Context section and states it follows ARCHITECTURE.md as authoritative.

4. **Device mode PPG enum open question (Issue #4)** — ✅ RESOLVED. Plan states "the SDK header `CDevice.h` confirms `StartPPG=5, StopPPG=6` — this is resolved." Verified against SDK HTML docs: `clCDevice_Mode_StartPPG = 5`, `clCDevice_Mode_StopPPG = 6`. Correct.

5. **Manual test enumeration (Issue #5)** — ✅ RESOLVED. Task 6 now includes the instruction: "Add a comment at the top of the test file: `// When adding new constants to channel_names.dart or enums.dart, add them to the corresponding list here.`"

6. **Split enums into separate file (Suggestion #6)** — ✅ ADOPTED. Task 4 creates `lib/src/channel/enums.dart` as a separate file. Task 5 barrel exports both `channel_names.dart` and `enums.dart`.

7. **`fromCode` error message (Suggestion #7)** — ✅ ADOPTED. Task 4 specifies: "throws `ArgumentError` with a descriptive message including the invalid code value (e.g. `'Unknown NeiryDeviceType code: $code'`)."

8. **Cardio channel unconfirmed (Suggestion #8)** — ✅ ACKNOWLEDGED. Plan includes `cardioCalibratedEvent` with the note: "the exact native callback name needs confirmation from `_c_cardio_8h` when implementing the iOS/Android bridges — for now the string constant is defined." Acceptable for a constants-only milestone.

### Verification Against SDK Docs

All three enum int mappings in the plan were verified against the vendored SDK HTML documentation:

| Enum | Plan values | SDK docs | Match |
|------|------------|----------|-------|
| `NeiryDeviceType` | headband(0), buds(1), headphones(2), impulse(3), any(4), brainBit(6), sinWave(100), noise(101) | `clCDeviceType_Headband=0` through `clCDeviceType_Noise=101` | ✅ |
| `NeiryDeviceMode` | resistance(0), signal(1), signalAndResist(2), startMEMS(3), stopMEMS(4), startPPG(5), stopPPG(6) | `clCDevice_Mode_Resistance=0` through `clCDevice_Mode_StopPPG=6` | ✅ |
| `NeiryConnectionState` | disconnected(0), connected(1), unsupportedConnection(2) | `clCDevice_ConnectionState_Disconnected=0` through `..._UnsupportedConnection=2` | ✅ |

### Verification Against Codebase

- `lib/src/channel/` directory does not exist yet — plan creates it. ✅
- `lib/neiry_kit.dart` currently exports `NeiryKit` class from `neiry_kit_platform_interface.dart`. Plan replaces with barrel exporting `channel_names.dart` and `enums.dart`. ✅
- `neiry_kit_platform_interface.dart` and `neiry_kit_method_channel.dart` are kept on disk but no longer re-exported — correct, later milestones may reference them. ✅
- Both scaffolding test files (`neiry_kit_test.dart`, `neiry_kit_method_channel_test.dart`) are deleted. New `test/channel_names_test.dart` replaces them. ✅
- `pubspec.yaml` needs no changes — `flutter_test` is already a dev dependency, and the new code is pure Dart with no new packages. ✅

### Critical Issues

None.

### Suggestions

None. All issues from the first review have been addressed. The plan is well-structured with clear task boundaries, correct file paths, verified enum values, proper test coverage, and a sensible two-commit strategy.

### Positive Notes

- Clean iteration: every issue and suggestion from the first review was addressed substantively — not just acknowledged but integrated into the task descriptions with the right level of detail.
- The Context section at the top proactively documents the two roadmap discrepancies (file path and EventChannel count), preventing implementer confusion.
- Enum file split (Task 4 → `enums.dart`) is a genuine improvement over the first iteration's single-file approach. String constants and enhanced enums with factories serve different purposes and belong in separate files.
- Task 6 test coverage is thorough: uniqueness checks across all constant classes, SDK int verification for every enum value, `fromCode` round-trip for every member, and `throwsArgumentError` for invalid codes.
- The plan correctly notes that `cardioCalibratedEvent` is provisional and defers confirmation to the native bridge milestone — appropriate scoping for a constants-only deliverable.

PLAN_REVIEW_PASS
