# Plan Review: CardioBridge — post-review fix

**Plan file:** `.ai-factory/plans/30-cardiobridge-post-review-fix.md`
**Files in scope:** 1
**Risk Level:** 🟢 Low

## Context Gates

- **ARCHITECTURE.md** — WARN: no issues. The fix is a one-line guard addition inside an existing iOS bridge callback, fully consistent with the layered SDK bridge architecture and the established callback pattern.
- **RULES.md** — file does not exist. WARN (non-blocking).
- **ROADMAP.md** — OK. The plan maps directly to the unchecked milestone "CardioBridge — post-review fix" under iOS bridges.

## Verification Against Codebase

### Bug existence confirmed

`CardioBridge.swift` line 111–112: the `SetOnPPGDataEvent` closure receives `ppgData` as `OpaquePointer?` (Swift's import of a C pointer parameter). The current guard on line 112 only checks `bridge`:

```swift
guard let bridge = CardioBridge.activeBridge else { return }
let count = clCPPGTimedData_GetCount(ppgData)  // ppgData is optional — runtime trap if nil
```

`ppgData` is then passed unguarded to `clCPPGTimedData_GetCount`, `clCPPGTimedData_GetValue`, and `clCPPGTimedData_GetTimestampMilli`. If the SDK delivers a nil pointer, this crashes.

### Pattern consistency confirmed

Every other callback across all five bridge files that receives a pointer parameter guards it in the same `guard let` statement:

| File | Callback | Data param guarded? |
|---|---|---|
| `CardioBridge.swift:93` | `SetOnIndexesUpdateEvent` | ✅ `let data = data` |
| `NfbBridge.swift:90` | `SetOnUserStateChangedEvent` | ✅ `let data = data` |
| `EmotionsBridge.swift:57` | `SetOnEmotionalStatesUpdateEvent` | ✅ `let data = data` |
| `PhysioBridge.swift:92` | `SetOnStatesUpdateEvent` | ✅ `let data = data` |
| `PhysioBridge.swift:120` | `SetOnCalibratedEvent` | ✅ `let baselines = baselines` |
| `ProductivityBridge.swift:102` | `SetOnMetricsUpdateEvent` | ✅ `let data = data` |
| `ProductivityBridge.swift:129` | `SetOnIndexesUpdateEvent` | ✅ `let data = data` |
| `ProductivityBridge.swift:148` | `SetOnBaselineUpdateEvent` | ✅ `let baselines = baselines` |
| **`CardioBridge.swift:112`** | **`SetOnPPGDataEvent`** | **❌ unguarded** |

The PPG callback is the **only** unguarded pointer parameter across all iOS bridge files. The plan correctly identifies it as the sole fix needed.

### Proposed fix is correct

The plan proposes changing line 112 from:
```swift
guard let bridge = CardioBridge.activeBridge else { return }
```
to:
```swift
guard let bridge = CardioBridge.activeBridge,
      let ppgData = ppgData else { return }
```

This shadows the optional with a non-optional binding, matching the exact pattern used everywhere else. The fix is minimal, correct, and introduces no behavioral change when `ppgData` is non-nil.

## Critical Issues

None.

## Positive Notes

- The plan is precisely scoped — one bug, one file, one line change. No unnecessary scope creep.
- Correct line numbers and file path verified against the current codebase.
- The referenced pattern (line 93–94) is accurate and the fix follows it exactly.
- Context section clearly explains the root cause (Swift importing C callback parameter as `OpaquePointer?`).

PLAN_REVIEW_PASS
