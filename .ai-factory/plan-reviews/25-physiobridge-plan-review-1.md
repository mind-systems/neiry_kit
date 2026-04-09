## Plan Review: PhysioBridge

**Plan file:** `.ai-factory/plans/25-physiobridge.md`
**Files reviewed:** Plan + 10 codebase files (existing bridges, plugin, Dart classifiers, channel contract, explore notes, models)
**Risk Level:** 🟡 Medium

### Context Gates

- **ARCHITECTURE.md:** WARN — plan follows established bridge patterns (static weak activeBridge, DeviceStreamHandler, one bridge per C module). No boundary violations.
- **RULES.md:** file not present. WARN — skipped.
- **ROADMAP.md:** Plan targets the unchecked `PhysioBridge` milestone. Aligned. ✓

### Issues

#### 1. `registerCallbacks()` error handling description is wrong — will cause a compile error or swallowed errors

**Task 1, `registerCallbacks()`** says:

> "every `SetOn*Event` takes `clCError*`, so each registration must use `do/catch checkCError` inline (cannot use `try` inside a C callback — expand manually like in the Explore notes: check `error.success`, if false build message via `withUnsafePointer(to: error.message)` and call `sendError`)"

This conflates two unrelated things:

- The `clCError*` is a parameter of the **registration function** (`clCPhysiologicalStates_SetOnStatesUpdateEvent(handle, handler, &error)`), not of the callback handler itself. The callback type is `(clCPhysiologicalStates, const clCPhysiologicalStates_Value*) NOEXCEPT` — no error.
- Swift's `try checkCError(error)` works perfectly fine at the registration call site (outside the closure). The "cannot use `try` inside a C callback" caveat is true but irrelevant — nobody needs to `try` inside the callback.

The instruction to "expand manually" with `error.success` checks and `sendError` describes a completely different pattern (manual error checking inside a C closure) that doesn't apply here.

**Fix:** Replace the entire parenthetical. `registerCallbacks()` must be marked `throws`. Each registration call uses `try checkCError(error)` at the call site — identical to how `DeviceBridge`, `NfbBridge`, and `NfbCalibratorBridge` already use `checkCError`:

```swift
private func registerCallbacks() throws {
    guard let physio = physio else { return }
    PhysioBridge.activeBridge = self

    var error1 = clCError()
    clCPhysiologicalStates_SetOnStatesUpdateEvent(physio, { _, data in
        // ...
    }, &error1)
    try checkCError(error1)

    // repeat for the other 3
}
```

Since `create()` already wraps in `do/catch`, errors propagate to the Dart caller.

#### 2. `unregisterCallbacks()` will not compile — missing `&error` parameter

**Task 1, `unregisterCallbacks()`** says:

> "nil out all 4 callbacks by passing `nil` to each `SetOn*Event`"

But every `clCPhysiologicalStates_SetOn*Event` requires three parameters: `(handle, handler, &error)`. The plan omits the `clCError*` argument. Calling with only two args will not compile.

**Fix:** Each unregistration call needs a throwaway error variable:

```swift
private func unregisterCallbacks() {
    guard let physio = physio else { return }
    var e = clCError()
    clCPhysiologicalStates_SetOnStatesUpdateEvent(physio, nil, &e)
    clCPhysiologicalStates_SetOnCalibrationProgressUpdateEvent(physio, nil, &e)
    clCPhysiologicalStates_SetOnCalibratedEvent(physio, nil, &e)
    clCPhysiologicalStates_SetOnIndividualNFBUpdateEvent(physio, nil, &e)
    if PhysioBridge.activeBridge === self {
        PhysioBridge.activeBridge = nil
    }
}
```

Errors during unregistration can be safely ignored (reusing the same `e` variable is fine).

#### 3. `importBaselines` struct deserialization uses wrong numeric cast for timestamp

**Task 1, `importBaselines(map:)`** says:

> `if let ts = map["ts"] as? Int { baselines.timestampMilli = Int64(ts) }`

On the Dart side, `PhysiologicalStatesBaselines.toMap()` emits `timestamp?.millisecondsSinceEpoch ?? -1`. Flutter's platform channel encodes Dart `int` as `NSNumber`. In Swift, an `NSNumber` from a Dart `int` arrives as `Int` on 64-bit platforms but could arrive as `Int64` depending on the value size. The safe cast pattern used elsewhere in the codebase (e.g., `NfbCalibratorBridge` line 52–53) is `as? Int` then `Int64(ts)`, which matches what the plan says. However, the sentinel value `-1` from `toMap()` should be passed through as-is — the plan does this correctly since `-1` casts to `Int64(-1)`.

No action needed — verified correct on closer inspection.

#### 4. Trailing closure syntax won't work — mention in plan to avoid confusion

**Task 1** — The existing bridges (`NfbBridge`, `EmotionsBridge`) use Swift trailing closure syntax:
```swift
clCEmotions_SetOnEmotionalStatesUpdateEvent(emotions) { _, data in
```

This works because those `SetOn*Event` functions take 2 params (handle, handler). For PhysioBridge, `SetOn*Event` takes 3 params (handle, handler, `&error`), so trailing closure syntax is impossible — the `&error` argument comes after the closure. The plan should note this to prevent the implementer from copying the trailing-closure style from existing bridges and hitting a compile error.

### Positive Notes

- Event channel IDs in the plan (`neiry_kit/events/physiologicalState`, etc.) match `channel_names.dart` constants exactly — all 4 are already registered in `NeiryKitPlugin.registerEventChannels()`.
- `clCError*` asymmetry between Physio (YES) and Emotions (NO) is correctly identified.
- The `IndividualNFBUpdateHandler` empty-signal pattern (`[:]` → `Stream<void>`) is the right fix for the `NfbUserState.fromMap` crash.
- Baselines struct field names match both the C struct and the Dart `PhysiologicalStatesBaselines.fromMap`/`toMap` keys.
- Cleanup ordering in `handleDeviceLocatorCall.dispose` is correct (classifiers before locator/device).
- The plan correctly follows the `activeBridge` static-weak-reference pattern required by C callbacks that lack a `void* context` parameter.

### Observation (out of scope)

`ProductivityClassifier.individualNfbStream` (line 148 of `productivity_classifier.dart`) has the identical `Stream<NfbUserState>` + `NfbUserState.fromMap` type on the same empty-signal event. It will crash the same way when ProductivityBridge is implemented. Worth fixing in the ProductivityBridge plan when the time comes.
