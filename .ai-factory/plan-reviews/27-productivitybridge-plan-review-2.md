## Plan Review Summary

**Plan Reviewed:** `27-productivitybridge.md`
**Files Affected:** `ios/Classes/classifiers/ProductivityBridge.swift`, `ios/Classes/NeiryKitPlugin.swift`
**Risk Level:** 🟡 Medium

### Context Gates

- **ARCHITECTURE.md:** PASS — plan follows "one bridge class per C API module" pattern, correct folder placement, no dependency boundary violations.
- **RULES.md:** WARN — file does not exist.
- **ROADMAP.md:** PASS — plan implements the last unchecked iOS bridges milestone (`ProductivityBridge`). All event channel IDs and C API references match roadmap description.

### Critical Issues

1. **Task 2, callback #5 — `individualNfbStream` will crash at runtime**

   The plan correctly emits `[:]` (empty map) from `SetOnIndividualNFBUpdateEvent`, matching the C API which delivers only the handle with no data. However, the Dart side's `ProductivityClassifier._individualNfbStream` decodes events using `NfbUserState.fromMap`:

   ```dart
   // productivity_classifier.dart, line 148
   late final Stream<NfbUserState> _individualNfbStream = _eventStream(
       const EventChannel(NeiryEvents.productivityIndividualNfb),
       NfbUserState.fromMap,  // ← tries map['ts'] as int on empty map → TypeError
   );
   ```

   `NfbUserState.fromMap` accesses `map['ts'] as int`, which throws `TypeError` on an empty map.

   Compare with `PhysioClassifier`, which handles the identical pattern correctly:

   ```dart
   // physio_classifier.dart, line 94
   late final Stream<void> _individualNfbStream =
       const EventChannel(NeiryEvents.physiologicalIndividualNfb)
           .receiveBroadcastStream({NeiryArgs.serial: _serial})
           .map((_) {});  // ← ignores content, just signals
   ```

   **Fix:** The plan must include a step to change `ProductivityClassifier._individualNfbStream` from `Stream<NfbUserState>` with `NfbUserState.fromMap` decoder to `Stream<void>` with `.map((_) {})`, matching the PhysioClassifier pattern. The public getter return type and its doc comment must also change accordingly. Without this, the bridge implementation is correct but the end-to-end flow crashes the moment the C SDK fires this callback.

### Suggestions

None — all three suggestions from review-1 (float field count, explicit handle assignment, `createCalibrated` guard) have been addressed.

### Positive Notes

- The key architectural insight — Productivity takes `clCIndividualNFBData*` directly, not a `clCNFBCalibrator` handle — is correct and well-documented. The `createCalibrated` factory path correctly builds the struct from the Dart map instead of calling `clCNFBCalibrator_CreateOrGet`.
- The dual-emit from `SetOnBaselineUpdateEvent` (parsed map → `baselinesHandler`, raw bytes → `calibratedHandler`) is a clean solution that serves both Dart streams from a single C callback.
- All 5 callback signatures correctly omit `clCError*`, and `registerCallbacks()` is correctly marked non-throwing. This avoids cargo-culting the PhysioBridge pattern where all callbacks DO take `clCError*`.
- Plugin wiring is thorough and accurate — property, init, method dispatch, event channel handlers, and dispose chain all have correct references to the existing code.
- The `importBaselines` raw-bytes round-trip with size validation is the right approach for an opaque C struct the Dart side shouldn't parse.
