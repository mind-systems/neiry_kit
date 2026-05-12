# Plan: Fix crash on Disconnect when session already stopped

## Context
Guard the unconditional `device.stop()` calls in the example app with `device.isStarted` so the SDK does not receive a second `clCDevice_Stop` on an already-stopped session, which currently causes a `SIGABRT` in `libCapsuleClient.so`. The fix applies to all three reachable call sites: the explicit Disconnect button path in `active_device_provider.dart`, the existing-device cleanup inside `createAndConnect()`, and the app-shutdown teardown path in `main.dart`.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Guard stop() calls

- [x] **Task 1: Guard `stop()` inside `disconnectAndDispose()`**
  Files: `example/lib/providers/active_device_provider.dart`
  In `disconnectAndDispose()` (around line 57), replace the unconditional `await device.stop();` (wrapped in try/catch) with a conditional that only calls `stop()` when `device.isStarted` is `true`. Keep the surrounding `try { ... } catch (_) {}` so any race-condition error is still swallowed. Leave the subsequent `disconnect()` and `dispose()` calls untouched — they are idempotent on the native side.

- [x] **Task 2: Guard `stop()` inside `createAndConnect()` cleanup path**
  Files: `example/lib/providers/active_device_provider.dart`
  In `createAndConnect()` (lines 27–29), apply the same guard to the existing-device cleanup: only call `await existing.stop()` when `existing.isStarted` is `true`. Preserve the existing `try { ... } catch (_) {}` wrapper. Do not modify the `disconnect()` or `dispose()` calls in this block.

- [x] **Task 3: Guard `stop()` inside `_cleanupAndDispose()` app-shutdown path**
  Files: `example/lib/main.dart`
  In `_AppState._cleanupAndDispose()` (around line 42), apply the same `if (device.isStarted)` guard to the `await device.stop();` call. This closes the "user taps Stop, then closes the app" crash path: after a successful manual stop, `_started` is already `false`, and the app-shutdown teardown would otherwise issue a second `clCDevice_Stop` and hit the same SIGABRT. Same pattern as Tasks 1–2: keep the existing `try { ... } catch (_) {}` wrapper, leave `disconnect()` and `dispose()` calls untouched.
