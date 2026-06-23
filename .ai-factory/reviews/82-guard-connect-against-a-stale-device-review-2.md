# Code Review (pass 2): Guard connect() against a stale device

**Plan:** `.ai-factory/plans/82-guard-connect-against-a-stale-device.md`
**Files reviewed:** `example/lib/services/neiry_service.dart` (full file)
**Diff scope:** 5-line addition to `NeiryService.connect()`.

## Summary

The change tears down a stale `_device` via the idempotent `disconnect()` at the start of
`connect()`, fixing the `clC… module already exists` → `0xebadde09` / `Fatal signal 64`
reconnect crash. Since review-1 the teardown was moved **inside** the `try` block, after
`_connecting = true` (lines 125–130):

```dart
    _connecting = true;
    try {
      if (_device != null) {
        nlog('[NeiryService] connect: stale device present — tearing down before reconnect', name: 'neiry_kit');
        await disconnect();
      }
      _nfbData = nfbData;
      ...
```

This resolves the only finding from review-1 (re-entrancy window): `_connecting` is now
`true` for the entire teardown await, so a second `connect()` call during teardown hits
`if (_connecting) throw` instead of racing a second `disconnect()` on the same handle.

## Correctness verification

- **Re-entrancy closed.** The `_connecting` guard (line 122) now covers the
  `await disconnect()`. `disconnect()` never reads `_connecting`, so setting it `true`
  first is behavior-preserving, and the function-level `finally` resets it.
- **No exception escapes the teardown.** Every step of `disconnect()` is wrapped in its
  own try/catch (or `Future.wait` + `catchError`) and nothing rethrows, so
  `await disconnect()` always completes normally and `connect()` proceeds.
- **Post-teardown invariant holds.** `disconnect()` sets `_device = null` unconditionally
  (line 349) regardless of per-step errors, so `createDevice` (line 135) starts from a
  clean `_device == null` state — no double-registration of native modules.
- **Fresh locator picked up.** `disconnect()` disposes and recreates `_locator` (lines
  359–366) when `!_disposed`; `connect()` reads `_locator` as a field at call time
  (line 135), so it uses the recreated locator, avoiding the cached stale `clCDevice`.
- **Live-session guard preserved.** `if (isConnected) throw` (line 123) still fires for a
  genuinely-connected double-tap; the teardown only runs for a stale `_device` where
  `isConnected == false`.

No bugs, security issues, race conditions, or type problems found in the code change.

## Non-blocking observation

The plan file's Task 1 text and re-entrancy note (lines 17–19) still describe the
*original* placement — "before `_connecting = true`" and "`_connecting` is still `false`
at this point." The implementation correctly deviated (placing the teardown after
`_connecting = true`, per review-1), which is the better choice. This is stale plan prose
only — it has no effect on the shipped code. No action required for this change.

REVIEW_PASS
