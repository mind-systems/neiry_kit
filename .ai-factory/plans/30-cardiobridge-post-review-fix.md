# Plan: CardioBridge — post-review fix

## Context
The PPG callback in `CardioBridge.swift` does not guard `ppgData` for nil before passing it to C accessor functions. Swift imports the C callback parameter as `OpaquePointer?`, so a nil value would trap at runtime when passed to `clCPPGTimedData_GetCount`. The fix adds `ppgData` to the existing `guard let` statement.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Fix

- [x] **Task 1: Guard ppgData for nil in SetOnPPGDataEvent callback**
  Files: `ios/Classes/classifiers/CardioBridge.swift`
  In the `clCCardio_SetOnPPGDataEvent` closure (line 111–126), the `guard let` on line 112 only checks `bridge`. The `ppgData` parameter (`OpaquePointer?`) is used unguarded on line 113 in `clCPPGTimedData_GetCount(ppgData)` and subsequent accessor calls. Change the guard statement from:
  ```swift
  guard let bridge = CardioBridge.activeBridge else { return }
  ```
  to:
  ```swift
  guard let bridge = CardioBridge.activeBridge,
        let ppgData = ppgData else { return }
  ```
  This shadows the optional `ppgData` with a non-optional binding, matching the same pattern already used in the `SetOnIndexesUpdateEvent` closure above (line 93–94) where `data` is guarded with `let data = data`.
