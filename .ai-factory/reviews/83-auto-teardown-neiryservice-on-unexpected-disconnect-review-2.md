# Code Review 2: Auto-teardown NeiryService on unexpected disconnect

**Scope reviewed:** `example/lib/services/neiry_service.dart`, `example/lib/screens/device_screen.dart` (read in full, with `lib/src/api/device.dart` for the stream/state contract)
**Plan:** `.ai-factory/plans/83-auto-teardown-neiryservice-on-unexpected-disconnect.md`
**Risk:** 🟢 Low — `example/` test-harness only, pure Dart, no native/plugin/migration surface.

## Summary

Independent second pass. The diff implements all three tasks exactly as planned and is correct for the targeted scenario (power-off / BLE drop → SDK emits `disconnected` ~7 s later → service tears down and UI converges to idle). I re-derived the key safety properties from scratch rather than trusting review 1, and they hold.

### Correctness checks (re-verified independently)

- **Trigger wiring.** `_internalConnSub` subscribes to `_device!.connectionStateStream` (neiry_service.dart:265), the cached broadcast stream from `device.dart:61`. `_onDeviceConnectionState` filters to `disconnected` and bails when `_tearingDown` is set (neiry_service.dart:542-547). Correct.
- **Echo isolation.** The synthesized `disconnected` is published on `_connectionStateController` (the multiplexer, neiry_service.dart:288), never on the device stream, so it cannot reach `_internalConnSub`. The flag is a redundant second guard, not the only one — good defense in depth.
- **Synchronous flag set.** `_tearingDown = true` executes before the first `await` in `disconnect()` (neiry_service.dart:280), and `unawaited(disconnect())` runs the synchronous prefix before returning to the handler. A burst of `disconnected` events therefore collapses to a single teardown.
- **Ordering vs. native re-emit.** `_internalConnSub` is cancelled in step 2 (neiry_service.dart:318-323), before `_device!.disconnect()` in step 4 — so a `disconnected` emitted by the native disconnect itself has no live listener (and `_tearingDown` is true anyway).
- **No native double-free.** On a genuine power-off, `Device._startStateTracking` has already set `_connected=false`/`_started=false` (device.dart:140-143). In the auto-triggered `disconnect()`, step 1 is skipped (`isStarted==false`) and `_device!.disconnect()`'s internal guard short-circuits — consistent with the prior "crash when already stopped" fixes.
- **`finally` reset.** `_tearingDown` is reset in `finally` (neiry_service.dart:394-396); every interior step is independently try/caught, so an escaping throw is unlikely, and even if one occurred the flag is cleared. Matches plan Minor #2.
- **Task 3 listener.** `ref.listen` is registered in `build()` (device_screen.dart:209-217); Riverpod dedupes it across rebuilds, so no listener stacking. The callback fires after build (never during), so `_clearScan()`'s `setState` is safe; `_clearScan()` is `mounted`-guarded with a post-frame `invalidate`. `whenData` correctly ignores `AsyncLoading`/`AsyncError`. Idempotent on the manual path. `prev` unused is not an analyzer warning.

## Findings

All findings are **Low severity / non-blocking**. They concur with review 1's two items and add one UI-coupling observation.

### Low 1 — `await disconnect()` no longer guarantees teardown completion for `connect()` and `dispose()`

The `if (_tearingDown) return;` early-return (neiry_service.dart:279) makes `disconnect()` a no-op while an `unawaited` auto-teardown is in flight. Two structural callers `await disconnect()` *expecting it to finish*:

- `connect()` stale-device guard (neiry_service.dart:136-138) — if it no-ops, `_device` isn't nulled, then `connect()` reassigns `_device`/uses `_locator` while the in-flight teardown still reads those fields (use-after-reassign; double `_locator.dispose()` + recreate).
- `dispose()` (neiry_service.dart:433-434) — proceeds to close controllers and dispose `_locator` while the in-flight teardown may also be disposing/recreating `_locator`.

**Why Low:** the auto-teardown fires ~7 s after the drop, by which point Task 3's `_clearScan()` has nulled `_selectedSerial`, *disabling the Connect button* (`_selectedSerial != null` gate, device_screen.dart:344-346) — so re-entering `connect()` during the window requires a fresh scan+select that outlasts the teardown. And `dispose()` is bound to the root-scope `neiryServiceProvider`, so it realistically only runs at app shutdown. The hazard is real but practically unreachable in this example app.

**Optional hardening (only if `NeiryService` is reused in `mind_mobile`):** store the in-flight teardown as `Future? _teardownFuture` and have `connect()`/`dispose()` `await` it before proceeding, restoring the "await means done" contract without weakening the re-entrancy guard.

### Low 2 — UI reset (`deviceIsStartedProvider` / scan) is coupled to DeviceScreen being mounted

The Task 3 `ref.listen` lives in `DeviceScreen.build`, and `ref.listen` only fires on a *change after registration*. If a spontaneous disconnect happens while the user is on another screen, the listener never sees that past event, so `deviceIsStartedProvider` can remain stale-`true` and the scan stays uncleared until the next manual action.

**Why Low / likely no action:** the resource teardown itself is screen-independent (it runs inside `NeiryService`, the part that actually prevents the `module already exists` crash). The stale `deviceIsStartedProvider=true` is masked by `deviceUiStateProvider`, which returns `idle` whenever the connection state isn't `connected` regardless of the started flag (device_state_providers.dart:42-46); and `_connect()` resets the flag to `false` before reconnecting (device_screen.dart:109). So there's no functional regression — only a note that the UI-side reset is best-effort, not guaranteed, for off-screen drops. Acceptable for a hardware test harness.

### Nit — no `onError` on the internal subscription

`_internalConnSub = ...listen(_onDeviceConnectionState)` registers no `onError`, and the Task 3 listener uses `whenData`. A stream *error* (vs. a `disconnected` event) would neither tear down nor reset the UI. Note 36 verified power-off delivers a `disconnected` event, not an error, so this is in line with the spec and explicitly out of scope — recorded only so it isn't mistaken for full error coverage.

## Conclusion

The implementation is correct, faithful to the plan, and reuses the existing idempotent teardown rather than duplicating it. The guards correctly separate a spontaneous drop from the synthesized echo, and the worst-case interleavings are either prevented by the `_clearScan()` button-gating added in this same change or confined to app-shutdown. No blocking issues. The two Low items are worth carrying forward as a comment/TODO if and when `NeiryService` graduates from the example app into `mind_mobile`, where multi-screen navigation and explicit `dispose()` calls make them reachable.
