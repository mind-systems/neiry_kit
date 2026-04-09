## Plan Review: EmotionsBridge (iOS)

**Plan file:** `.ai-factory/plans/24-emotionsbridge.md`
**Files reviewed:** 9 (plan + NfbBridge.swift, NeiryKitPlugin.swift, DeviceBridge.swift, channel_names.dart, emotions_classifier.dart, emotions_states.dart, 10-explore-physio-emotions.md, ARCHITECTURE.md)
**Risk Level:** 🟢 Low

### Context Gates

- **ARCHITECTURE.md:** PASS — `EmotionsBridge.swift` goes in `ios/Classes/classifiers/`, wired through `NeiryKitPlugin.swift`. Matches the architecture's "one bridge class per C API module" principle and the folder structure template exactly.
- **RULES.md:** WARN — file does not exist; no project-specific conventions to check.
- **ROADMAP.md:** PASS — the plan implements the `EmotionsBridge` milestone (currently `[ ]` under iOS bridges). Scope is correctly scoped to iOS only; Android is a separate roadmap item.

### Verification Summary

**Task 1 — EmotionsBridge.swift:**

- Channel IDs `neiry_kit/events/emotionsState` and `neiry_kit/events/emotionsError` match `NeiryEvents.emotionsState` and `NeiryEvents.emotionsError` in `channel_names.dart`. Confirmed both are already registered in `NeiryKitPlugin.registerEventChannels()` (currently falling through to `StubStreamHandler`). ✅
- Map keys (`ts`, `attention`, `relaxation`, `cognitiveLoad`, `cognitiveControl`, `selfControl`) match `EmotionsStates.fromMap()` in `emotions_states.dart` exactly. ✅
- Error event shape `["message": message]` matches Dart decoder `(map) => map['message'] as String` in `emotions_classifier.dart`. ✅
- `clCEmotions_Create` takes `clCError*` — correct to wrap with `checkCError()`. `checkCError` is defined in `DeviceLocatorBridge.swift` and accessible project-wide. ✅
- `clCEmotions_SetOnEmotionalStatesUpdateEvent` and `clCEmotions_SetOnErrorEvent` take NO `clCError*` — correct NOT to wrap. Confirmed in `10-explore-physio-emotions.md` function table. ✅
- No `clCEmotions_Destroy` — correct to only nil handle and unregister callbacks. ✅
- Weak `activeBridge` pattern matches NfbBridge for C callbacks without `void* context`. ✅
- `DeviceStreamHandler` is defined in `DeviceBridge.swift` and used by both `NfbBridge` and `NfbCalibratorBridge` — reuse is correct. ✅
- Target directory `ios/Classes/classifiers/` already exists (contains `NfbBridge.swift`). ✅

**Task 2 — NeiryKitPlugin.swift wiring:**

- Property, instantiation, event channel registration, and method dispatch all follow the established NfbBridge wiring pattern. ✅
- MethodChannel `neiry_kit/emotions` is already registered in `registerMethodChannels()` (line 39) but falls through to `FlutterMethodNotImplemented` (line 63) — the dispatch addition is correct. ✅
- `handleEmotionsCall` guards both `emotionsBridge` and `deviceBridge`, uses `requireDevice()` — matches `handleNfbCall` pattern. ✅
- Only two method cases (`create`, `dispose`) plus `default` — matches the Dart `EmotionsClassifier` which only calls `ClassifierMethods.create` and `ClassifierMethods.dispose`. ✅
- Dispose cleanup in `handleDeviceLocatorCall` `case "dispose"` — correct location. Adding before `nfbBridge?.dispose()` is fine (no ordering dependency since there's no Destroy). ✅

### Critical Issues

None.

### Suggestions

None.

### Positive Notes

- The plan is tightly scoped — two tasks, one new file, one modification. No scope creep.
- Explicit callouts about what NOT to do (no `clCError*` wrapping on callbacks, no Destroy) prevent the most likely implementation mistakes.
- The reference pattern (NfbBridge) is well-chosen — it's the simplest classifier bridge in the codebase (no calibration, no baselines), which is exactly what Emotions needs.
- Channel IDs, map shapes, and Dart model fields were all cross-verified against the actual codebase.

PLAN_REVIEW_PASS
