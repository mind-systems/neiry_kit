# Code Review: CardioBridge — post-review fix

**Plan:** `.ai-factory/plans/30-cardiobridge-post-review-fix.md`
**Scope:** 1 file changed (`ios/Classes/classifiers/CardioBridge.swift`), 1 line added

## Changes Reviewed

### `ios/Classes/classifiers/CardioBridge.swift` (line 111–113)

The `SetOnPPGDataEvent` closure's `guard let` now includes `let ppgData = ppgData`, shadowing the optional `OpaquePointer?` parameter with a non-optional binding before it reaches `clCPPGTimedData_GetCount` and subsequent accessor calls.

**Before:**
```swift
guard let bridge = CardioBridge.activeBridge else { return }
let count = clCPPGTimedData_GetCount(ppgData)  // ppgData is OpaquePointer? — nil traps
```

**After:**
```swift
guard let bridge = CardioBridge.activeBridge,
      let ppgData = ppgData else { return }
let count = clCPPGTimedData_GetCount(ppgData)  // ppgData is now OpaquePointer — safe
```

## Verification

1. **Fix correctness** — The guard unwraps the optional before any C function call. All three uses of `ppgData` in the closure body (lines 114, 118, 119) now receive a non-optional `OpaquePointer`. Correct.

2. **Pattern consistency** — The adjacent `SetOnIndexesUpdateEvent` closure (lines 92–94) uses the identical `guard let bridge ..., let data = data` pattern. The `SetOnCalibratedEvent` closure (line 131) receives no data pointer so needs no guard. All three callbacks in this file are now consistent.

3. **No behavioral change when ppgData is non-nil** — The guard only adds an early return for the nil case. When the SDK delivers a valid pointer, execution is identical to before.

4. **No other unguarded optional pointers in this file** — Checked all three callbacks. `SetOnIndexesUpdateEvent` guards `data` (line 94). `SetOnCalibratedEvent` has no data param. `SetOnPPGDataEvent` now guards `ppgData` (line 113). Complete.

5. **No missing changes** — The plan specified a single-line fix in a single file. The diff matches exactly. No other files required changes.

## Critical Issues

None.

## Non-Critical Issues

None.

REVIEW_PASS
