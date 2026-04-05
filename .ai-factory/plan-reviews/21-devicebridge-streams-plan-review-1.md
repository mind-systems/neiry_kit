## Plan Review: DeviceBridge — streams

**Files Reviewed:** 12 (plan + 2 Swift bridges + plugin + channel_names.dart + 4 Dart models + sentinel.dart + C SDK headers + spec notes)
**Risk Level:** Low

### Context Gates

- **ARCHITECTURE.md** (WARN: none) — Plan follows the layered bridge architecture: one bridge class per C module, EventChannel per data source, main-thread dispatch before sink, `@convention(c)` closures with static weak bridge. All consistent.
- **RULES.md** — File does not exist. WARN (non-blocking).
- **ROADMAP.md** (WARN: none) — Plan directly addresses the unchecked milestone "DeviceBridge — streams" with the exact scope described: 8 EventChannels, per-channel `DeviceStreamHandler`, `clCError*`-checked accessors.

### Verification Summary

**C SDK callback signatures** — all 8 `clCDevice_SetOn*Event` typedefs verified against `CDevice.h`:
- EEG, PSD, Artifacts: handler receives opaque data handle, accessors take `clCError*` — plan correctly skips event on any error.
- Resistance: `clCResistance_*` accessors take NO `clCError*` — plan correctly omits error checking.
- Battery (`uint8_t`), Error (`const char*`), ConnectionStatus (`clCDevice_ConnectionStatus`), Mode (`clCDevice_Mode`) — all primitive/enum, no accessors needed — plan matches.

**Map key alignment with Dart models** — every key emitted by the plan matches the corresponding `fromMap` factory:
- `EegData.fromMap`: `ts`, `rawValues`, `processedValues`, `channelCount`, `sampleCount` — match.
- `PsdData.fromMap`: `ts`, `values`, `frequencies`, `channelCount`, `frequencyCount`, 10 band boundaries, 4 individual alpha/beta keys — match.
- `EegArtifactData.fromMap`: `ts`, `artifacts`, `qualities`, `channelCount` — match.
- `ResistanceData.fromMap`: `channelNames`, `values`, `channelCount` — match.
- Battery: `charge` — match. Error: `message` — match. ConnectionStatus: `state` — match. Mode: `mode` — match.

**Sentinel handling** — plan emits `-1` for individual alpha/beta when `HasIndividualAlpha/Beta` returns false. Dart `orNull()` in `sentinel.dart` casts via `(v as num).toDouble()` and returns `null` for negatives. Works for both `Int(-1)` and `Float(-1)` from the platform channel.

**EventChannel IDs** — all 8 IDs listed in Task 3 match `NeiryEvents` constants in `channel_names.dart` and the `registerEventChannels()` array in `NeiryKitPlugin.swift`.

**Static weak `activeBridge` pattern** — mirrors the working pattern in `DeviceLocatorBridge`. `NeiryKitPlugin` holds the strong reference. `@convention(c)` closures access only the static property.

**Lifecycle timing** — `registerCallbacks()` at end of `setDevice()` (called during `createDevice`) means callbacks are in place before `connect()`. Non-blocking connect means Dart has time to subscribe to EventChannels via `_startStateTracking()` before BLE connection completes.

**Unregister via nil** — C function pointer parameters are imported as optional in Swift. Passing `nil` to `clCDevice_SetOn*Event` to clear callbacks is valid.

### Critical Issues

None.

### Suggestions

None.

### Positive Notes

- Map keys were meticulously aligned with the Dart `fromMap` factories, including the correct sentinel strategy for PSD individual bands.
- Correctly classifies which C accessors take `clCError*` and which don't — matching the actual header signatures.
- Cleanup path is thorough: Task 8 handles device swap (unregister old, register new), release (unregister first), and the `send()` nil-sink guard covers onCancel during active callbacks.
- Commit plan groups logically: infrastructure first, then all callbacks, then cleanup — minimizes broken intermediate states.
- Uses the same patterns proven in the existing `DeviceLocatorBridge` rather than inventing new approaches.

PLAN_REVIEW_PASS
