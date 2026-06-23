# Code Review 3: Auto-teardown NeiryService on unexpected disconnect

**Scope reviewed:** `example/lib/services/neiry_service.dart`, `example/lib/screens/device_screen.dart` (full read), cross-checked `lib/src/api/device.dart` and `example/lib/providers/device_state_providers.dart`.
**Plan:** `.ai-factory/plans/83-auto-teardown-neiryservice-on-unexpected-disconnect.md`
**Risk:** 🟢 Low — `example/` test harness, pure Dart, no native/migration surface.

## Summary

Third independent pass. The code is unchanged from reviews 1–2 and implements all three tasks exactly as planned. I deliberately probed paths the earlier reviews touched only lightly — broadcast-stream subscription ordering, partial-construction failure in `connect()`, and the listener/`setState` lifecycle — and found no new defects. The change is correct for its target scenario and safe to ship within the example app.

## Newly probed paths (no defect found)

- **No spurious teardown right after connect.** `connectionStateStream` resolves to a single cached broadcast stream (`device.dart:61`). The fan-in `...listen(_connectionStateController.add)` (neiry_service.dart:181) is the *first* listener and starts the broadcast; `_internalConnSub` (neiry_service.dart:265) subscribes later. A late listener on a broadcast stream sees only events emitted after it attaches, so no buffered/replayed `connected`→`disconnected` can fire `_onDeviceConnectionState` spuriously during a healthy connect.
- **Partial classifier-construction failure is clean.** If any constructor at neiry_service.dart:162-173 throws, control exits before `_internalConnSub` is assigned, leaving it `null`. The next `connect()` runs its stale-device `disconnect()`, whose `_internalConnSub?.cancel()` (neiry_service.dart:319) is null-safe. The new field adds no leak on this pre-existing partial-state path.
- **Listener lifecycle is safe.** The Task 3 `ref.listen` is registered in `build()` and torn down by Riverpod when the `ConsumerState` disposes, so its callback cannot fire post-dispose; `_clearScan()` additionally guards its `invalidate` with `mounted`. Calling `setState` from a `ref.listen` callback is legal (callbacks run after build, never during).
- **Double `_clearScan()` yields a single invalidate.** On the manual path the button handler and the listener both call `_clearScan()`. The first nulls `_scanParams` and schedules `invalidate(params)`; the second sees `params == null` and schedules nothing. No invalidate storm, no rebuild loop (the scan section stops watching `deviceScanProvider(params)` once `_scanParams` is null).

## Re-confirmed core safety (consistent with reviews 1–2)

- Synthesized `disconnected` is published only to `_connectionStateController`, never the device stream, so it cannot re-enter `_onDeviceConnectionState`; `_tearingDown` is a redundant second guard.
- `_tearingDown` is set before the first `await`, collapsing event bursts to one teardown; reset in `finally`.
- `_internalConnSub` is cancelled in step 2 before the native `_device!.disconnect()` in step 4; on a real power-off `_startStateTracking` already cleared `_connected`/`_started` (device.dart:140-143), so steps 1/4 short-circuit — no native double-free.

## Notes (non-blocking, no action required in this change's scope)

These two items are the same forward-looking observations raised in reviews 1–2. On final analysis they are **not defects in the delivered change** — the same changeset's mitigations make them unreachable in the example app. Recorded so they travel with the code if `NeiryService` is later lifted into `mind_mobile`.

1. **`await disconnect()` no longer guarantees completion under the `_tearingDown` early-return.** `connect()`'s stale-device guard and `dispose()` `await disconnect()` expecting it to finish; if an `unawaited` auto-teardown is in flight, those awaits return immediately. Unreachable here because (a) Task 3's `_clearScan()` nulls `_selectedSerial`, disabling the Connect button for the entire teardown window, and (b) `dispose()` is bound to the root-scope `neiryServiceProvider` (app-shutdown only). If reused in a multi-screen app with explicit disposes, harden by tracking `Future? _teardownFuture` and awaiting it in `connect()`/`dispose()`.
2. **Off-screen drops don't reset `deviceIsStartedProvider`/scan.** The Task 3 `ref.listen` only fires while `DeviceScreen` is mounted and only on changes after registration. Harmless: the resource teardown itself is screen-independent, the stale `isStarted=true` is masked by `deviceUiStateProvider` returning `idle` whenever not `connected` (device_state_providers.dart:42-46), and `_connect()` resets the flag before reconnecting.

A spec-conformant nit also stands: no `onError` on `_internalConnSub` and `whenData` in the Task 3 listener mean a stream *error* (vs. a `disconnected` event) wouldn't trigger teardown — consistent with note 36, which verified power-off emits a `disconnected` event.

## Conclusion

Three independent passes converge: the implementation is correct, faithful to the plan, reuses the existing idempotent teardown, and correctly distinguishes a spontaneous drop from the synthesized echo. No correctness, security, or runtime defect manifests within this change's scope (the example app). The two notes are accepted, unreachable-in-scope hardening items for an eventual `mind_mobile` migration, not defects in this changeset.

REVIEW_PASS
