# Code Review: Guard connect() against a stale device

**Plan:** `.ai-factory/plans/82-guard-connect-against-a-stale-device.md`
**Files reviewed:** `example/lib/services/neiry_service.dart` (full file)
**Scope of diff:** 5-line addition to `NeiryService.connect()`.

## Summary

The change does exactly what the plan and spec note 35 describe: at the top of
`connect()`, after the existing guards and before `_connecting = true`, it tears down a
stale `_device` via the idempotent `disconnect()`. This correctly fixes the targeted
`clC… module already exists` → `0xebadde09` / `Fatal signal 64` reconnect crash:
`disconnect()` releases the six classifiers, the native modules, and the device handle,
nulls `_device`, and recreates the locator, so the subsequent `createDevice` +
classifier construction starts clean.

Verified:
- `disconnect()` cannot escape an exception into `connect()` — every step is wrapped in
  its own try/catch (or `Future.wait` + `catchError`) and nothing rethrows, so
  `await disconnect()` always completes normally.
- `_device = null` is set unconditionally at the end of `disconnect()` (line 349)
  regardless of per-step errors, so the post-teardown invariant (`_device == null`) holds
  even if a teardown step logs an error.
- `connect()` reads `_locator` as a field at call time (line 135), so it picks up the
  locator that `disconnect()` recreates (lines 359–366) rather than the stale one.
- The `if (isConnected) throw` guard is preserved, so a genuinely-live double-tap still
  throws instead of silently reconnecting.

## Findings

### 1. (Low) New re-entrancy window: `_connecting` guard is open across `await disconnect()`

Before this change, there was no `await` between the `if (_connecting) throw` guard
(line 122) and `_connecting = true` (line 130) — the section was fully synchronous, so a
second `connect()` could never slip past the guard. This diff inserts `await
disconnect()` (line 127) into that gap while `_connecting` is still `false`. A second
`connect()` invoked during the teardown await therefore passes all three guards
(`_connecting` is false, and after a silent drop `isConnected` is false) and also enters
the teardown branch, calling `disconnect()` a second time on the same `_device`.

`disconnect()` uses `_device!` (non-null assertion) repeatedly across its own `await`
points; with two interleaved teardowns racing toward `_device = null`, the second call
can hit a null-check assertion / operate on a half-released handle.

Impact is low in practice: in the example app `connect()` is driven from a UI button
typically gated by device state, and the spec (note 35, line 41) explicitly accepts this
placement. But the change does measurably widen the unguarded window that previously did
not exist, so it is worth closing since the fix is free and removes the only new
correctness risk this diff introduces.

**Suggested fix** — set the flag before the teardown so the guard covers it; `disconnect()`
never reads `_connecting`, and the existing `finally` already resets it:

```dart
    if (_connecting) throw StateError('Connect already in flight');
    if (isConnected) throw StateError('Already connected — call disconnect() first');

    _connecting = true;
    try {
      if (_device != null) {
        nlog('[NeiryService] connect: stale device present — tearing down before reconnect', name: 'neiry_kit');
        await disconnect();
      }

      _nfbData = nfbData;
      // … rest unchanged
```

(`disconnect()` is independent of `_connecting`, so moving the teardown inside the `try`
is behavior-preserving for the single-call path and closes the re-entrancy window.)

### 2. (Informational) Synthetic `disconnected` event on the reconnect path

When tearing down a stale device, `disconnect()` pushes a synthetic
`NeiryConnectionState.disconnected` onto `_connectionStateController` (line 267). On the
reconnect path this means consumers briefly observe `disconnected` before the new
session's `connecting`/`connected` events arrive. This is harmless and arguably
desirable (it corrects any consumer still showing "connected" after a silent drop). No
action needed.

## Conclusion

The fix is correct and resolves the crash. One low-severity finding (re-entrancy window
newly introduced by moving an `await` ahead of `_connecting = true`) with a free,
behavior-preserving fix; the second item is informational only.
