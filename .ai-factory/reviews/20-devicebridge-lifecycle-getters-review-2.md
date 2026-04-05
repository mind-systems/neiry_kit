## Code Review: DeviceBridge — lifecycle + getters (review 2)

**Plan:** `.ai-factory/plans/20-devicebridge-lifecycle-getters.md`
**Files Changed:** `ios/Classes/DeviceBridge.swift` (new), `ios/Classes/NeiryKitPlugin.swift` (modified)
**Risk Level:** Low

### Review-1 Fix Verification

All issues from review-1 were addressed:

1. **Critical: `setDevice` same-serial handle leak** — fixed. `DeviceBridge.swift:38` now compares pointers (`old != handle`) instead of serials. If `createDevice` is called twice with the same serial, the old handle is properly released. ✓
2. **Suggestion: `getMode()` returned `0` (= `resistance`)** — fixed. `DeviceBridge.swift:138` now returns `-1` when no device is set. `-1` is not a valid `NeiryDeviceMode` code, so `fromCode(-1)` would throw `ArgumentError` — making the problem visible rather than returning a misleading mode. Dart `Device` doesn't invoke `getMode` directly (mode is tracked via event stream), so this path is unreachable in normal use. ✓
3. **Suggestion: locator `dispose` didn't release DeviceBridge** — fixed. `NeiryKitPlugin.swift:124-125` now calls `deviceBridge?.release()` after `bridge.dispose()` in the `"dispose"` case. ✓
4. **Suggestion: dangling pointer in `DeviceLocatorBridge.devices`** — fixed. `NeiryKitPlugin.swift:90` removes the entry from `DeviceLocatorBridge.devices` after handoff to `DeviceBridge`, making ownership transfer explicit. ✓

### Architecture Compliance

- **No cross-bridge access.** `DeviceBridge.requireDevice()` uses only the stored handle. `NeiryKitPlugin` mediates the handoff at `NeiryKitPlugin.swift:88-90`. ✓
- **Dispatch pattern consistent.** `handleDeviceCall` error trampoline matches `handleDeviceLocatorCall`. ✓

### Contract Alignment

All 16 switch cases match `DeviceMethods` constants (channel_names.dart:84-102):
- Lifecycle: `connect`, `disconnect`, `start`, `stop` ✓
- Info/state: `getInfo`, `getBatteryCharge`, `getMode` ✓
- Sample rates: `getEEGSampleRate`, `getPPGSampleRate`, `getMEMSSampleRate` ✓
- Amplitudes: `getPPGIrAmplitude`, `getPPGRedAmplitude` ✓
- Channels: `getChannelNames`, `getChannelsCount`, `getChannelIndexByName`, `getChannelNameByIndex` ✓

Correctly omitted: `createDevice` (locator channel), `isConnected` (client-side only).

Argument keys match `NeiryArgs`: `bipolarChannels`, `channelName`, `index` ✓

Return types match Dart expectations: `Float` for sample rates (`(result! as num).toDouble()`), `Int32` for amplitudes (`invokeMethod<int>`), `[String: Any]` map keys for `getInfo` match `DeviceInfo.fromMap` (`serial`, `name`, `type`). ✓

### Handle Lifecycle

- `createDevice` → handle stored in `DeviceLocatorBridge.devices` → handed to `DeviceBridge.setDevice` → removed from `devices` dict. Single owner at all times. ✓
- `setDevice` releases old handle if pointer differs. No leak on repeated `createDevice`. ✓
- `disconnect` does NOT call `release()`. Handle survives for reconnection. ✓
- Locator `dispose` calls `deviceBridge?.release()`. No stale handles after teardown. ✓
- `DeviceBridge.deinit` calls `release()` as safety net. `release()` is idempotent (checks `device != nil`). No double-free. ✓

### Critical Issues

None.

### Suggestions

None.

REVIEW_PASS
