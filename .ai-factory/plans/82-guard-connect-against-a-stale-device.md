# Plan: Guard connect() against a stale device

## Context
Prevent the `Fatal signal 64` / `0xebadde09` crash that occurs when reconnecting after a silent headset drop, by tearing down any stale `_device` at the start of `connect()` before re-creating native modules.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Stale-device teardown guard

- [x] **Task 1: Tear down stale session at the top of `connect()`**
  Files: `example/lib/services/neiry_service.dart`
  In `NeiryService.connect()` (≈ lines 120–125), after the existing `_checkNotDisposed()` / `if (_connecting)` / `if (isConnected)` guards and **before** `_connecting = true`, add a stale-device teardown: if `_device != null`, log a single `nlog` line (`'[NeiryService] connect: stale device present — tearing down before reconnect'`, `name: 'neiry_kit'`) and `await disconnect();`. This relies on the existing idempotent `disconnect()` (returns early on `_device == null`, releases classifiers + native modules + device handle, recreates the locator). After it returns, `_device == null`, so the subsequent `createDevice` + classifier construction starts clean with no `clC… module already exists`.
  Keep the `if (isConnected) throw StateError(...)` guard unchanged so a genuinely-live session (user double-tapping Connect) still throws rather than silently reconnecting. Note: after a silent drop `isConnected == false`, so that guard does not fire and the new teardown handles the stale handle.
  Re-entrancy is safe: `disconnect()` sets no `_connecting` flag, and `_connecting` is still `false` at this point (set to `true` only after the teardown).

## Verification (manual)
Connect → Start → power the headset off → Scan → Connect again. Expect: no `clC… module already exists` errors, no `0xebadde09` / signal 64; the second session connects cleanly.
