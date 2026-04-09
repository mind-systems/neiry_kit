# Plan: EmotionsBridge (iOS)

## Context
Add the iOS native bridge for the `clCEmotions` classifier — creates the `EmotionsBridge.swift` class and wires it into `NeiryKitPlugin.swift` so the Dart `EmotionsClassifier` can create, stream, and dispose the native handle.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Bridge implementation

- [x] **Task 1: Create EmotionsBridge.swift**
  Files: `ios/Classes/classifiers/EmotionsBridge.swift`
  Create `EmotionsBridge` following the exact `NfbBridge` pattern (`ios/Classes/classifiers/NfbBridge.swift`):
  - `private static weak var activeBridge: EmotionsBridge?` — required because C callbacks have no `void* context` parameter.
  - Two `DeviceStreamHandler` lets: `emotionsStateHandler` (channelId `neiry_kit/events/emotionsState`) and `emotionsErrorHandler` (channelId `neiry_kit/events/emotionsError`).
  - `func allStreamHandlers() -> [(String, FlutterStreamHandler)]` returning both handlers.
  - `private var emotions: OpaquePointer?` for the `clCEmotions` handle.
  - `func create(device: OpaquePointer) throws` — if handle already exists call `unregisterCallbacks()` first; call `clCEmotions_Create(device, &error)` with `try checkCError(error)`; then call `registerCallbacks()`. The `Create` call is the only one that takes `clCError*`.
  - `func dispose()` — call `unregisterCallbacks()`, nil the handle. No `clCEmotions_Destroy` exists in the SDK.
  - `private func registerCallbacks()` — set `EmotionsBridge.activeBridge = self`, then:
    - `clCEmotions_SetOnEmotionalStatesUpdateEvent(emotions) { _, data in ... }` — guard `activeBridge` and `data`, read `data.pointee`, build map with keys `ts` (Int64 timestampMilli), `attention`, `relaxation`, `cognitiveLoad`, `cognitiveControl`, `selfControl` (all Float), send via `emotionsStateHandler.send(map)`. **No `clCError*`** — do NOT wrap in `do/catch checkCError`.
    - `clCEmotions_SetOnErrorEvent(emotions) { _, msg in ... }` — guard `activeBridge`, convert `msg` to String via `String(cString:)`, send via `emotionsErrorHandler.send(["message": message])`. **No `clCError*`** — do NOT wrap in `do/catch checkCError`.
  - `private func unregisterCallbacks()` — pass `nil` to both `SetOn*Event` functions; nil `activeBridge` if it is still `self`.

- [x] **Task 2: Wire EmotionsBridge into NeiryKitPlugin.swift**
  Files: `ios/Classes/NeiryKitPlugin.swift`
  Four changes following the pattern established by `nfbBridge`:
  1. **Add property** — add `private var emotionsBridge: EmotionsBridge?` next to the existing `nfbBridge` property (around line 13).
  2. **Instantiate in `register(with:)`** — add `instance.emotionsBridge = EmotionsBridge()` after `nfbCalibratorBridge` instantiation (before `registerEventChannels()`).
  3. **Register event channels** — in `registerEventChannels()`, build a `var emotionsHandlers: [String: FlutterStreamHandler]` dictionary from `emotionsBridge.allStreamHandlers()` (same pattern as `nfbHandlers`); add it to the `else if let handler = ...` lookup chain after `nfbCalibratorHandlers` and before the `StubStreamHandler` fallback. This replaces the stub for `neiry_kit/events/emotionsState` and `neiry_kit/events/emotionsError`.
  4. **Add method dispatch** — add `else if channelId == "neiry_kit/emotions" { handleEmotionsCall(call, result: result) }` to `handleMethodCall(_:result:channelId:)` (around line 62). Implement `handleEmotionsCall`:
     - Guard `emotionsBridge` and `deviceBridge`, same pattern as `handleNfbCall`.
     - `case "create"`: call `deviceBridge.requireDevice()`, then `emotionsBridge.create(device:)`, wrap in `do/catch` returning `FlutterError`.
     - `case "dispose"`: call `emotionsBridge.dispose()`, return `nil`.
     - `default`: return `FlutterMethodNotImplemented`.
  5. **Dispose cleanup** — in the `handleDeviceLocatorCall` `case "dispose"` block (around line 131), add `emotionsBridge?.dispose()` before `nfbBridge?.dispose()` so all classifier handles are cleaned up when the locator is disposed.
