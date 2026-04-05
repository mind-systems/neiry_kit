# Plan: DeviceBridge — streams

## Context

Add 8 EventChannel stream handlers to the iOS `DeviceBridge` so the Dart side receives live device data (EEG, PSD, artifacts, resistance, battery, error, connection status, mode). Each stream is backed by a per-channel `DeviceStreamHandler` inner class; all C SDK callbacks dispatch to the main thread before calling the sink; any C accessor that takes `clCError*` is checked and the entire event is skipped on failure.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Stream handler infrastructure

- [x] **Task 1: Add `DeviceStreamHandler` inner class to `DeviceBridge.swift`**
  Files: `ios/Classes/DeviceBridge.swift`
  Add a `DeviceStreamHandler` class (nested inside DeviceBridge or as a private class in the same file) that conforms to `FlutterStreamHandler`. It stores a `FlutterEventSink?` and a `channelId: String` (set at init). `onListen` saves the sink, `onCancel` nils it. Add a thread-safe `send(_ map: [String: Any])` convenience that dispatches `sink(map)` on `DispatchQueue.main.async`, guarding for nil sink. Also add a `sendError(_ code: String, _ message: String)` that dispatches `sink(FlutterError(...))` on main queue. The class must be `NSObject` to satisfy `FlutterStreamHandler` protocol.

- [x] **Task 2: Create 8 `DeviceStreamHandler` instances as stored properties on `DeviceBridge`**
  Files: `ios/Classes/DeviceBridge.swift`
  Add 8 `lazy` or `let` properties on `DeviceBridge`, one per stream — `eegHandler`, `psdHandler`, `artifactsHandler`, `resistanceHandler`, `batteryHandler`, `errorHandler`, `connectionStatusHandler`, `modeHandler` — each initialized with the corresponding channel ID string (e.g. `"eeg"`, `"psd"`). These are the objects that `NeiryKitPlugin` will register as stream handlers. Add a public `streamHandlers` computed property (or a method `allStreamHandlers() -> [(String, FlutterStreamHandler)]`) that returns pairs of `(eventChannelId, handler)` so the plugin can iterate and register without knowing internal details.

- [x] **Task 3: Wire handlers into `NeiryKitPlugin.swift` EventChannel registration**
  Files: `ios/Classes/NeiryKitPlugin.swift`
  In `registerEventChannels()`, replace the `StubStreamHandler` for the 8 device EventChannel IDs (`neiry_kit/events/eeg`, `neiry_kit/events/psd`, `neiry_kit/events/eegArtifacts`, `neiry_kit/events/resistance`, `neiry_kit/events/battery`, `neiry_kit/events/error`, `neiry_kit/events/connectionStatus`, `neiry_kit/events/modeSwitched`) with the corresponding `DeviceStreamHandler` from `deviceBridge`. Use the `allStreamHandlers()` helper or access each handler property directly. All other EventChannels stay as `StubStreamHandler`.

### Phase 2: Register C SDK callbacks

- [x] **Task 4: Add `registerCallbacks()` / `unregisterCallbacks()` to `DeviceBridge`**
  Files: `ios/Classes/DeviceBridge.swift`
  Add a `static weak var activeBridge: DeviceBridge?` (same pattern as `DeviceLocatorBridge`). Add `registerCallbacks()` that sets `DeviceBridge.activeBridge = self`, then calls all 8 `clCDevice_SetOn*Event` functions passing `@convention(c)` closures. Add `unregisterCallbacks()` that passes `nil` to all 8 `clCDevice_SetOn*Event` calls to unregister and clears `activeBridge`. Call `registerCallbacks()` at the end of `setDevice(serial:handle:)` (after the handle is stored). Call `unregisterCallbacks()` at the start of `release()` (before the handle is destroyed). This ensures callbacks are only active while a device handle exists.

- [x] **Task 5: Implement EEG stream callback**
  Files: `ios/Classes/DeviceBridge.swift`
  Inside the `clCDevice_SetOnEEGDataEvent` closure: resolve `DeviceBridge.activeBridge`, then call C accessors to build the map. Use `clCEEGTimedData_GetChannelsCount(data, &error)`, `clCEEGTimedData_GetSamplesCount(data, &error)`, `clCEEGTimedData_GetTimestampMilli(data, 0, &error)` for timestamp, then nested loops calling `clCEEGTimedData_GetRawValue` and `clCEEGTimedData_GetProcessedValue` for each `[channel][sample]`. Every accessor takes `clCError*` — allocate a fresh `var error = clCError()` before each call, check `error.success` after, and `return` (skip entire event) if any fails. Build map with keys: `ts` (Int64), `rawValues` ([[Float]]), `processedValues` ([[Float]]), `channelCount` (Int), `sampleCount` (Int). Dispatch via `eegHandler.send(map)`.

- [x] **Task 6: Implement PSD stream callback**
  Files: `ios/Classes/DeviceBridge.swift`
  Inside the `clCDevice_SetOnPSDDataEvent` closure: build map with all PSD accessors. All take `clCError*` — skip event on any failure. Keys: `ts`, `values` ([[Double]] — `[channel][frequencyBin]`), `frequencies` ([Double]), `channelCount`, `frequencyCount`, plus 10 band boundary keys (`deltaLower/Upper`, `thetaLower/Upper`, `alphaLower/Upper`, `smrLower/Upper`, `betaLower/Upper`) using `clCPSDData_GetBandLower/Upper` with the `clCPSDData_Band` enum values. For individual alpha/beta: call `clCPSDData_HasIndividualAlpha(data, &error)` — if accessor fails skip event; if returns `true`, read `GetIndividualAlphaLower/Upper` and add keys `individualAlphaLower/Upper`; if `false` or accessor error, emit `-1` for those keys (Dart `orNull` handles sentinel). Same pattern for beta. Use `psdHandler.send(map)`.

- [x] **Task 7: Implement artifacts, resistance, battery, error, connectionStatus, mode callbacks**
  Files: `ios/Classes/DeviceBridge.swift`
  Implement the remaining 6 C callback closures:
  - **Artifacts** (`clCDevice_SetOnEEGArtifactsEvent`): accessors all take `clCError*`. Keys: `ts` (UInt64), `artifacts` ([Int] — per-channel uint8), `qualities` ([Float] — per-channel), `channelCount`. Skip on error.
  - **Resistance** (`clCDevice_SetOnResistanceUpdateEvent`): accessors do NOT take `clCError*` (no error checking needed). Keys: `channelNames` ([String]), `values` ([Float]), `channelCount`.
  - **Battery** (`clCDevice_SetOnBatteryChargeUpdateEvent`): callback receives `uint8_t` directly — no accessors, no `clCError*`. Map: `{"charge": Int(charge)}`.
  - **Error** (`clCDevice_SetOnErrorEvent`): callback receives `const char*` — no `clCError*`. Map: `{"message": String(cString: msg)}`.
  - **ConnectionStatus** (`clCDevice_SetOnConnectionStatusChangedEvent`): callback receives `clCDevice_ConnectionStatus` enum — no `clCError*`. Map: `{"state": Int(status.rawValue)}`.
  - **Mode** (`clCDevice_SetOnModeSwitchedEvent`): callback receives `clCDevice_Mode` enum — no `clCError*`. Map: `{"mode": Int(mode.rawValue)}`.
  All use `DispatchQueue.main.async` via their handler's `send()`.

### Phase 3: Cleanup on disconnect/release

- [x] **Task 8: Nil all sinks and unregister callbacks on release and device swap**
  Files: `ios/Classes/DeviceBridge.swift`
  Ensure `release()` calls `unregisterCallbacks()` first (done in Task 4), then nils the device handle. In `setDevice(serial:handle:)`, if an old handle is being replaced, call `unregisterCallbacks()` on the old handle before releasing it, then `registerCallbacks()` on the new one. Verify `deinit` → `release()` chain still works. Ensure that if `onCancel` fires (Dart side stops listening) while callbacks are still active, the nil sink in the handler silently drops events without crashing — the `send()` guard from Task 1 handles this.

## Commit Plan
- **Commit 1** (after tasks 1-3): "Add DeviceStreamHandler class and wire into plugin EventChannel registration"
- **Commit 2** (after tasks 4-7): "Register all 8 C SDK device callbacks with error-checked data extraction"
- **Commit 3** (after task 8): "Handle cleanup on device release and device swap"
