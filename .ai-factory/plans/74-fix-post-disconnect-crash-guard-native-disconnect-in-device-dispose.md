# Plan: Fix post-disconnect crash — guard native disconnect in Device.dispose()

## Context
`Device.dispose()` unconditionally calls native disconnect a second time after `disconnect()` already ran, corrupting the Capsule SDK state machine and crashing with `Fatal signal 64`. Guarding the native call behind `_connected` skips the redundant second disconnect.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Fix

- [x] **Task 1: Guard native disconnect in `dispose()`**
  Files: `lib/src/api/device.dart`
  In `dispose()` (around line 221–234), wrap the `await _channel.invokeMethod<void>(DeviceMethods.disconnect, {NeiryArgs.serial: serial})` call in an `if (_connected) { ... }` block. Replace the misleading comment `// Idempotent on the native side even if already disconnected.` with an accurate note: the Capsule SDK is NOT idempotent — calling native disconnect while a prior disconnect is still completing its async GATT teardown corrupts internal state and causes `Fatal signal 64`. Skip the native call when `!_connected` (which is already `false` after `disconnect()` returns). Keep the unconditional state resets that follow (`_started = false; _connected = false; _connectionState = ...; _mode = null; _battery = null;`) so the object is still fully locked down. No API surface change.
