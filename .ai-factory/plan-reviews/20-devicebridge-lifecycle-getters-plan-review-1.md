## Code Review Summary

**Plan Reviewed:** `.ai-factory/plans/20-devicebridge-lifecycle-getters.md`
**Files Affected:** `ios/Classes/DeviceBridge.swift`, `ios/Classes/NeiryKitPlugin.swift`
**Risk Level:** 🟡 Medium

### Context Gates

- **ARCHITECTURE.md:** `WARN` — Task 1's `resolveDevice` helper directly reads `DeviceLocatorBridge.devices[serial]`, which violates the explicit dependency rule: "❌ Platform bridges must never cross-call each other." The plan's own Task 6 acknowledges this rule ("bridges must never cross-call") yet the `resolveDevice` helper does exactly that.
- **RULES.md:** file does not exist — `WARN` (non-blocking).
- **ROADMAP.md:** plan aligns with the "DeviceBridge — lifecycle + getters" milestone. No linkage issues.

### Critical Issues

1. **`resolveDevice` cross-accesses `DeviceLocatorBridge.devices` (architecture violation)**
   Plan: Task 1 — `resolveDevice(_ call:)` looks up `DeviceLocatorBridge.devices[serial]`.
   The architecture explicitly prohibits cross-bridge access. Since `setDevice(serial:handle:)` (also in Task 1) already stores the handle in `self.device` and `self.serial`, `resolveDevice` should verify the incoming serial matches `self.serial` and return `self.device`. If no device has been set, throw `FlutterError(code: "NO_DEVICE", ...)`. Remove the `DeviceLocatorBridge.devices` lookup entirely — the plugin mediates via `setDevice`, which is the correct coordination pattern the plan already defines.

2. **Calling `release()` on `disconnect` destroys the device handle prematurely**
   Plan: Task 6 — "For `disconnect`, also call `deviceBridge.release()` to coordinate handle cleanup."
   `clCDevice_Disconnect` and `clCDevice_Release` are separate C API operations. The Dart `Device.disconnect()` resets connection state but does not dispose — the user can reconnect afterward. If the native side calls `release()` (which calls `clCDevice_Release` and nils the handle) on every `disconnect`, subsequent `connect()` calls will crash or throw `NO_DEVICE` because the handle is gone.
   Fix: do NOT call `release()` in the `disconnect` dispatch. Call `release()` only when the device is truly being disposed — either when the locator is destroyed, when a new device replaces the current one (in `setDevice`), or when a future explicit `Device.dispose()` channel method is added.

### Suggestions

1. **`resolveDevice` is redundant — simplify to stored-handle check**
   Once the architecture violation is fixed (issue #1), `resolveDevice` becomes a simple guard: verify `self.device != nil`, optionally verify `self.serial == args["serial"]`, return the stored handle. The two-path design (lookup + setDevice) adds unnecessary complexity for a single-device bridge. Consider inlining the guard into each method or renaming to `requireDevice()` to clarify intent.

2. **`DeviceMethods.isConnected` exists in the channel contract but is not implemented**
   The Dart side tracks connectivity client-side (`bool get isConnected => _connected`), so this is currently harmless. However, the contract defines it — add a note in the plan that `isConnected` is intentionally omitted (client-side only) or implement it as a simple `clCDevice_GetMode(device) != disconnected` check for contract completeness.

3. **Cache `clCDevice_ChannelNames` handle as a requirement, not a suggestion**
   Task 5 says "consider caching" — make it definitive. There is no release function for `clCDevice_ChannelNames` (confirmed: no `clCDevice_ChannelNames_Release` or `_Destroy` exists in the SDK headers), so repeated calls to `clCDevice_GetChannelNames` may allocate new handles each time with no way to free old ones. Store the handle in a `private var channelNamesHandle: OpaquePointer?` on first access, clear it in `release()`.

4. **`setDevice` should release the previous handle when replacing a device**
   Task 1 defines `setDevice(serial:handle:)` but doesn't mention what happens if it's called a second time (e.g., user creates a new device without explicitly disposing the old one). Add a guard: if `self.device != nil && self.serial != serial`, call `clCDevice_Release(self.device!)` before storing the new handle. This prevents native handle leaks.

5. **`getInfo` return map key `type` should use `.rawValue` consistently**
   Task 3 says return `"type": Int(rawValue)`. Verify the C enum `clCDeviceType` raw values match the Dart `NeiryDeviceType.code` values (0=headband, 1=buds, 2=headphones, 3=impulse, 4=any, 6=brainBit, 100=sinWave, 101=noise). The existing `DeviceLocatorBridge` already does `Int(clCDeviceInfo_GetType(info).rawValue)` and it works — just confirm the plan follows the same pattern.

### Positive Notes

- C API function signatures are correct throughout — `clCDevice_GetMode` and `clCDeviceInfo_Get*` correctly marked as no-`clCError*`, all others correctly wrapped in `checkCError`.
- The `setDevice` mediation pattern via `NeiryKitPlugin` is the right design — matches the architecture's "bridges must never cross-call" rule (when `resolveDevice` is fixed).
- Channel names two-step handle pattern (get handle → call accessors) correctly mirrors the C API surface.
- Error handling trampoline in Task 6 (`do/try/catch FlutterError/catch generic`) is consistent with the existing `handleDeviceLocatorCall` pattern.
- Return types (`Float` for sample rates, `Int32` for amplitudes, `Int` for battery/mode/type) align with both the C API signatures and the Dart side's expectations.
- Commit plan is well-structured: skeleton+lifecycle → getters → wiring.
