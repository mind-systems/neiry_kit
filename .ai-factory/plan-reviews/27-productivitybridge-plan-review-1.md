## Code Review Summary

**Plan Reviewed:** `27-productivitybridge.md`
**Files Affected:** `ios/Classes/classifiers/ProductivityBridge.swift`, `ios/Classes/NeiryKitPlugin.swift`
**Risk Level:** 🟢 Low

### Context Gates

- **ARCHITECTURE.md:** PASS — plan follows the established "one bridge class per C API module" pattern, uses `DeviceStreamHandler` for EventChannels, matches the folder layout (`ios/Classes/classifiers/ProductivityBridge.swift`). No dependency boundary violations.
- **RULES.md:** WARN — file does not exist. No explicit convention violations detected; plan follows the style of all other bridge files.
- **ROADMAP.md:** PASS — plan implements the `ProductivityBridge` milestone (the last unchecked item under "iOS bridges"). Event channel IDs, method names, and C API references match the roadmap description.

### Critical Issues

None.

### Suggestions

1. **Task 1 — "11 float fields" should be "10 float fields"**
   The plan says the Metrics callback has "11 float fields" then lists only 10: `fatigueScore`, `reverseFatigueScore`, `gravityScore`, `relaxationScore`, `concentrationScore`, `productivityScore`, `currentValue`, `alpha`, `productivityBaseline`, `accumulatedFatigue`. The C header (`CProductivity.h:26-36`) confirms exactly 10 float fields. The listed names are correct — just the count word is wrong. Fix the text to avoid confusing the implementer.

2. **Tasks 1 `create` and `createCalibrated` — missing explicit handle assignment step**
   Both factory method descriptions say "Call `clCProductivity_Create(device, &error)`" and "Call `clCProductivity_CreateWithIndividualData(device, &data, &error)`" but neither says to store the return value in `self.productivity`. Compare with the `create` description pattern: the step-by-step reads like fire-and-forget. An implementer following the plan literally (without referencing `CardioBridge.create`) would omit the `productivity = clCProductivity_Create(...)` assignment. Add explicit assignment steps, e.g.: "Set `productivity = clCProductivity_Create(device, &error)`."

3. **Task 4.3 — `createCalibrated` dispatch needs a guard for nil `calibrationData`**
   The plan correctly notes that "calibrationData is required (non-nil) since `clCProductivity_CreateWithIndividualData` always needs the struct." But the dispatch description only says `extract args?["calibrationData"] as? [String: Any]` — following the CardioBridge pattern where nil is gracefully handled. Since Productivity differs from Cardio here (Cardio uses a calibrator handle, Productivity passes the data struct directly), the dispatch should include an explicit `guard let calibrationData = args?["calibrationData"] as? [String: Any] else { result(FlutterError(code: "INVALID_ARGS", ...)); return }`. Without this, a nil dictionary produces a zeroed `clCIndividualNFBData` struct — functionally equivalent to no calibration, silently defeating the purpose of `createCalibrated`.

### Positive Notes

- The plan correctly identifies the key architectural difference between Productivity and Cardio/NFB: Productivity takes `clCIndividualNFBData*` directly, not a `clCNFBCalibrator` handle. This is verified against the C header (`CProductivity.h:81`).
- The dual-emit from `SetOnBaselineUpdateEvent` — sending parsed fields to `baselinesHandler` and raw bytes to `calibratedHandler` — is a clean solution for the absence of a separate `SetOnCalibratedEvent` in the Productivity C API. Both Dart streams (`baselineStream` and `calibrated`) get their expected data types from a single callback.
- All 5 callback signatures correctly match the C header: no `clCError*` parameter on any `SetOn*Event`, `registerCallbacks()` is correctly marked non-throwing. Contrast with PhysioBridge where all callbacks DO take `clCError*` — the plan avoids the common mistake of cargo-culting the Physio pattern.
- The `importBaselines` raw-bytes approach (struct → `Data` → `FlutterStandardTypedData` → persist → reimport → deserialize → struct) is the right choice for an opaque struct that the Dart side shouldn't parse. Size validation guard is included.
- Plugin wiring (Task 4) is thorough — covers all 5 integration points (property, init, method dispatch, event channels, dispose chain) with correct line references.
