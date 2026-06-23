# Code Review: Auto-teardown NeiryService on unexpected disconnect

**Scope reviewed:** `example/lib/services/neiry_service.dart`, `example/lib/screens/device_screen.dart`
**Plan:** `.ai-factory/plans/83-auto-teardown-neiryservice-on-unexpected-disconnect.md`
**Risk:** 🟢 Low — confined to the `example/` test-harness app; pure Dart, no native/plugin change.

## Summary

The implementation faithfully matches the plan and the spec in note 36. All three tasks landed:

- **Task 1/2** — `_tearingDown` flag + `_internalConnSub` field, `_onDeviceConnectionState` handler, internal subscription wired in `connect()`, `disconnect()` restructured into a `try/finally` with the flag set before the synthesized event and reset in `finally`.
- **Task 3** — a `ref.listen` on `deviceConnectionStateProvider` in `device_screen.build()` that resets `deviceIsStartedProvider` and calls `_clearScan()` on `disconnected`.

The core mechanism is correct. I verified the key invariants against the surrounding code:

- **Synthesized event cannot re-enter the handler.** `disconnect()` adds `disconnected` to `_connectionStateController` (the multiplexer), while `_internalConnSub` listens to the device's native `connectionStateStream` (`device.dart:61`, a distinct cached broadcast stream). The two never cross. ✅
- **`_tearingDown` is set synchronously before the first `await`** (neiry_service.dart:280), so `unawaited(disconnect())` flips the guard before control returns to the handler — a second synchronous `disconnected` emission is ignored. ✅
- **Internal sub is cancelled in step 2** (neiry_service.dart:318-323) before the native `_device!.disconnect()` in step 4, so any `disconnected` the native disconnect itself emits cannot reach the handler (sub already cancelled *and* `_tearingDown` true). ✅
- **No native double-teardown.** On a real power-off, `Device._startStateTracking` already set `_connected=false`/`_started=false` (device.dart:140-143); so in the auto-triggered `disconnect()`, step 1 is skipped (`isStarted==false`) and `_device!.disconnect()`'s internal `_connected` guard short-circuits — no native re-invoke. ✅
- **Three listeners on one broadcast stream** (fan-in, `_startStateTracking`, `_internalConnSub`) is legal. ✅
- **Task 3 listener is safe.** `ref.listen` callbacks fire after build, never during it, so `_clearScan()`'s `setState` is safe; `_clearScan()` is `mounted`-guarded and idempotent. `prev` being unused is not an analyzer warning (unused callback params are allowed). ✅

## Findings

Both findings are **Low severity / non-blocking** concurrency observations. They are largely mitigated by the implementation as written; I record them so the trade-off is a documented choice rather than an oversight.

### Low 1 — `connect()` and `dispose()` rely on `await disconnect()` completing, which the new early-return can short-circuit

`disconnect()` now early-returns when `_tearingDown` is already `true` (neiry_service.dart:279). Two existing callers `await disconnect()` *expecting the teardown to finish*:

- `connect()`'s stale-device guard: `if (_device != null) await disconnect();` (neiry_service.dart:136-138).
- `dispose()`: `await disconnect();` then closes all controllers and disposes the locator (neiry_service.dart:433-434).

If an `unawaited` auto-teardown is in flight when one of these runs, the `await disconnect()` returns immediately while the real teardown is still executing (`stopStream` → classifier dispose → `_device!.disconnect()`/`dispose()` → `_locator.dispose()` + `_locator = DeviceLocator()`). Two concrete hazards:

- **connect():** the stale-device `disconnect()` no-ops, so `_device` is not nulled; `connect()` then reassigns `_device = await _locator.createDevice(...)` while the in-flight teardown still reads the `_device`/`_locator` fields — a use-after-reassign / double-locator-dispose race.
- **dispose():** controllers are closed and `_locator.dispose()` is called while the in-flight teardown may also call `_locator.dispose()` and recreate the locator — a double-dispose.

**Why it's Low, not higher:**
- The auto-teardown fires ~7 s after the BLE drop, by which point `uiState` is already `idle` and **Task 3's `_clearScan()` nulls `_selectedSerial`**, which *disables the Connect button* (`_selectedSerial != null` gate, device_screen.dart:344-346). So the user effectively cannot re-enter `connect()` during the teardown window without first scanning+selecting again (which outlasts the teardown). The connect hazard is mostly self-mitigated by this very change.
- `dispose()` is wired to `neiryServiceProvider`, a root-scope provider in the example app, so it realistically only runs at app shutdown — overlapping it with an in-flight teardown is near-impossible in practice.

**Optional hardening (not required):** track the in-flight teardown as a `Future? _teardownFuture` and have `connect()`/`dispose()` `await _teardownFuture` before proceeding, instead of relying on `disconnect()` running to completion. This preserves the re-entrancy guard while restoring the "await means done" contract for the two structural callers.

### Low 2 — connection-stream errors don't trigger teardown (out of scope, noted for completeness)

`_internalConnSub = ...listen(_onDeviceConnectionState)` registers no `onError`, and the Task 3 `ref.listen` uses `whenData` (ignores `AsyncError`). An *error* on the connection stream (as opposed to a `disconnected` event) would neither tear down nor reset the UI. Note 36 verified that power-off delivers a `disconnected` event (not an error), so this is consistent with the spec and explicitly out of scope — recording only so it isn't mistaken for full error coverage.

## Conclusion

The change is correct for the targeted scenario, reuses the existing idempotent teardown rather than duplicating it, and the guards correctly distinguish a spontaneous drop from the synthesized echo. The two findings are low-severity concurrency edge cases — the more plausible one (Low 1, connect path) is already mitigated by the `_clearScan()` added in this same change. No blocking issues; safe to ship as-is, with Low 1's `_teardownFuture` hardening worth considering if `NeiryService` is ever reused outside the single-root-provider example app (e.g. in `mind_mobile`).
