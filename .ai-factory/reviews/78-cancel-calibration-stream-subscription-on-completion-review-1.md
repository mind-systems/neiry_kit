# Code Review: Cancel calibration stream subscription on completion

**Plan:** `.ai-factory/plans/78-cancel-calibration-stream-subscription-on-completion.md`
**Scope reviewed:** `example/lib/providers/calibration_provider.dart` (only code change in the diff; the other staged files are plan/plan-review artifacts).

## Summary

The change adds `_sub?.cancel(); _sub = null;` to both terminal paths of `startFull()`'s subscription — the `CalibrationCompleted` branch and the `onError` handler — after resolving `_fullCompleter`. This matches the spec exactly and fixes the leaked subscription that produced phantom "complete" events on subsequent runs.

## Correctness analysis

- **`_sub` is non-null when callbacks fire.** `_sub` is assigned synchronously from `.listen(...)` (line 71) before the stream delivers any event on a later event-loop turn, so `_sub?.cancel()` always acts on the live subscription. The `?.` guard is harmless defensive code.
- **Cancel-within-callback is safe.** Calling `cancel()` from inside a subscription's own `onData`/`onError` callback is well-defined in Dart.
- **Completer resolved before cancel.** Both branches complete `_fullCompleter` first, so `await _fullCompleter!.future` (line 99) still receives the correct value/error before cancellation. Cancelling does not affect the already-completed completer.
- **No double-cancel hazard.** Nulling `_sub` turns the `ref.onDispose` (line 43) and `abort()` (line 132) backstops into no-ops, as intended.
- **Consistent with existing conventions.** The unawaited `cancel()` matches `abort()` and `ref.onDispose`, which also call `_sub?.cancel()` without awaiting. The listener closures are synchronous, so no `unawaited_futures` lint is introduced.
- **`startQuick()` correctly left unchanged** — it self-cancels via its own subscription, per the spec.

No bugs, security issues, race conditions, or type problems found.

REVIEW_PASS
