# Plan: Fix hot restart crash — reorder onDetachedFromEngine cleanup

## Context
On Android hot restart, `onDetachedFromEngine` disposes classifier bridges while the BLE/GATT link is already dead. Each classifier's `dispose()` calls `clCXxx_SetOnXxxUpdateEvent(handle, nullptr)`, which internally invokes `GetAvailableClassifiers()` → `IsClassifierSupported()` and aborts with `Fatal signal 6` on a disconnected device. The fix is to release the device first so its handle is gone before any classifier teardown runs.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Reorder cleanup

- [x] **Task 1: Reorder cleanup in `onDetachedFromEngine`**
  Files: `android/src/main/kotlin/com/neiry/neiry_kit/NeiryKitPlugin.kt`
  In `onDetachedFromEngine` (currently lines 500–519), reorder the teardown so the device and device locator are released **before** any classifier bridge is disposed:
  1. First two lines: `deviceBridge?.release()` then `deviceBridge = null`.
  2. Next two lines: `deviceLocatorBridge?.dispose()` then `deviceLocatorBridge = null`.
  3. Then dispose the classifier bridges in their existing order: `productivityBridge`, `memsBridge`, `cardioBridge`, `physioBridge`, `emotionsBridge`, `nfbCalibratorBridge`, `nfbBridge` (each followed by setting the field to `null`, matching the current pattern).
  4. Keep `nativeBridge = null` and the `methodChannels` / `eventChannels` teardown blocks exactly as they are, in their current positions after the bridge cleanup.
  Do not change the relative order of the classifier bridges among themselves — only their position relative to `deviceBridge.release()` and `deviceLocatorBridge.dispose()`. Do not touch any other method or any other file.
