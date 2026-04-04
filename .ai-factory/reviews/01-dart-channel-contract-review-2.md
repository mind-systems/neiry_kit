## Code Review: Dart Channel Contract (Iteration 2)

**Plan file:** `.ai-factory/plans/01-dart-channel-contract.md`
**Files reviewed:** `lib/src/channel/channel_names.dart`, `lib/src/channel/enums.dart`, `lib/neiry_kit.dart`, `test/channel_names_test.dart`, `example/lib/main.dart`, `example/integration_test/plugin_integration_test.dart`, deleted `test/neiry_kit_test.dart`, deleted `test/neiry_kit_method_channel_test.dart`
**Analyzer result:** No issues found
**Test result:** 48/48 pass

### Previous Review Issues — Resolution Check

1. **Example app and integration test fail to compile (critical, 3 errors)** — RESOLVED. `example/lib/main.dart` replaced with a minimal `StatelessWidget` placeholder — no `NeiryKit` reference, no unused imports. `example/integration_test/plugin_integration_test.dart` replaced with an empty stub with a comment deferring to the "Example app" roadmap milestone. Both compile cleanly.

2. **Unused import warning in example app** — RESOLVED. The rewritten `main.dart` no longer imports `package:neiry_kit/neiry_kit.dart` at all, which is correct for a placeholder that doesn't use any plugin API.

3. **Dangling library doc comments (info-level)** — RESOLVED. Top-of-file comments in both `channel_names.dart` and `enums.dart` changed from `///` (doc comments) to `//` (plain comments), eliminating the `dangling_library_doc_comments` lint.

4. **Unnecessary string interpolation in tests (info-level)** — RESOLVED. `'${v.name}'` replaced with `v.name` in fromCode round-trip tests.

### Verification Against Spec Note

Every constant was cross-checked against `.ai-factory/notes/01-channel-contract.md`:

**MethodChannel IDs (8):** `deviceLocator`, `device`, `nfb`, `physiological`, `emotions`, `productivity`, `cardio`, `nfbCalibrator` — all match spec, all prefixed `neiry_kit/`.

**EventChannel IDs (26):** All 26 IDs from the spec note are present in `NeiryEvents`, in the same order, with `neiry_kit/events/` prefix. The `cardioCalibratedEvent` entry includes the correct code comment about native confirmation. Test asserts `ids.length == 26`.

**Method names:** `DeviceLocatorMethods` (4), `DeviceMethods` (18), `ClassifierMethods` (6), `NFBCalibratorMethods` (5) — all match spec.

**Argument keys (11):** `serial`, `deviceType`, `searchTime`, `mode`, `level`, `enabled`, `baselines`, `calibrationData`, `calibratorData`, `channelName`, `index` — spec lists 9, plan adds `channelName` and `index` from method signatures. All present.

**Enums vs SDK:**

| Enum | Values | SDK match |
|------|--------|-----------|
| `NeiryDeviceType` | headband(0), buds(1), headphones(2), impulse(3), any(4), brainBit(6), sinWave(100), noise(101) | All correct |
| `NeiryDeviceMode` | resistance(0), signal(1), signalAndResist(2), startMEMS(3), stopMEMS(4), startPPG(5), stopPPG(6) | All correct (PPG indices confirmed by CDevice.h) |
| `NeiryConnectionState` | disconnected(0), connected(1), unsupportedConnection(2) | All correct |

### Verification Against Plan

| Plan Task | Status |
|-----------|--------|
| Task 1: MethodChannel + EventChannel IDs in `channel_names.dart` | Complete — 8 + 26 constants |
| Task 2: Method name string classes | Complete — 4 classes, all methods present |
| Task 3: Argument key strings class | Complete — 11 keys |
| Task 4: Enums in separate `enums.dart` | Complete — 3 enums with `code` field, `fromCode` with descriptive errors |
| Task 5: Barrel export + delete scaffolding tests + fix example | Complete — barrel exports both files, old tests deleted, example fixed |
| Task 6: Unit tests | Complete — uniqueness, SDK int codes, round-trips, invalid input |

### Structural Checks

- `lib/src/channel/channel_names.dart` has no imports (pure constants, `channel/ → nothing` dependency rule respected).
- `lib/src/channel/enums.dart` has no imports (pure Dart enhanced enums).
- `lib/neiry_kit.dart` barrel exports exactly `channel_names.dart` and `enums.dart`.
- `neiry_kit_platform_interface.dart` and `neiry_kit_method_channel.dart` remain on disk, not re-exported — correct per plan.
- All `abstract final class` containers are uninstantiable (Dart 3 pattern for constant namespaces).
- No security concerns — this is pure constants and enums with no I/O, no platform calls, no user input handling.

### Issues

None.

### Suggestions

None.

REVIEW_PASS
