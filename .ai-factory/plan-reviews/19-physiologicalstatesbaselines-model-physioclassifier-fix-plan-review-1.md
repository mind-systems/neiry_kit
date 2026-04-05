## Code Review Summary

**Plan Reviewed:** `19-physiologicalstatesbaselines-model-physioclassifier-fix.md`
**Risk Level:** 🟢 Low

### Context Gates

- **ARCHITECTURE.md:** WARN — no violations. Model follows the immutable value type pattern (principle #2), sentinel-to-null conversion at the Dart boundary (principle #5), barrel export as public API (principle #4). `toMap()` re-emits sentinels for the bridge, which is the correct direction (Dart → native needs C-compatible values).
- **RULES.md:** file does not exist — WARN (non-blocking).
- **ROADMAP.md:** plan aligns with the unchecked milestone "PhysiologicalStatesBaselines model + PhysioClassifier fix". Bridge changes are correctly deferred to the PhysioBridge milestones (iOS/Android). No linkage issues.

### Critical Issues

None.

### Suggestions

1. **Barrel export insertion point is wrong (Task 3)**
   The plan says to insert `physio_baselines.dart` "alphabetically between the `physio_states.dart` and `ppg_data.dart` export lines (between current lines 24 and 25)". This is incorrect — `physio_baselines` sorts before `physio_states` alphabetically (`b` < `s`), so the correct insertion point is between `nfb_user_state.dart` (line 23) and `physio_states.dart` (line 24):
   ```
   export 'src/models/nfb_user_state.dart';
   export 'src/models/physio_baselines.dart';   // ← correct position
   export 'src/models/physio_states.dart';
   export 'src/models/ppg_data.dart';
   ```
   Fix: change the insertion instruction to "between lines 23 and 24" (between `nfb_user_state.dart` and `physio_states.dart`).

2. **`ProductivityClassifier` has the identical `Uint8List` bug**
   `ProductivityClassifier.calibrated` returns `Stream<Uint8List>` and `importBaselines(Uint8List data)` takes raw bytes (lines 143–146, 255 of `productivity_classifier.dart`). This is the same structural issue being fixed for `PhysioClassifier`. The `ProductivityBaselines` model already exists but lacks `toMap()`, and the classifier still passes raw bytes. This is out of scope for this plan, but a follow-up milestone should be created to fix `ProductivityClassifier` the same way — add `toMap()` to `ProductivityBaselines` and switch the classifier to typed baselines.

### Positive Notes

- The plan correctly identifies the mismatch between the C struct (`clCPhysiologicalStates_Baselines` with 6 named fields) and the current Dart API (opaque `Uint8List`), and proposes the right fix.
- The model design is consistent with existing patterns: `@immutable`, `fromMap` with `orNull` sentinel helper, nullable `DateTime` matching the `IndividualNfbData` timestamp pattern.
- The `toMap()` reverse-sentinel design (null → `-1.0` / `-1`) correctly produces C-compatible values for the bridge.
- Test coverage is thorough: all-sentinel, all-valid round-trip, and mixed sentinel/valid cases cover the important edge cases.
- Explicit scoping note about bridges being deferred is accurate — iOS and Android PhysioBridge milestones are unchecked and will consume this contract.
- Single commit plan is appropriate for this tightly-coupled change set.

PLAN_REVIEW_PASS
