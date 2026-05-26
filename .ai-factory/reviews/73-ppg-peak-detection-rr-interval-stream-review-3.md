# Code Review: PPG peak detection → RR interval stream (round 3)

**Plan:** `.ai-factory/plans/73-ppg-peak-detection-rr-interval-stream.md`
**Spec:** `.ai-factory/notes/23-ppg-rr-interval-stream.md`
**Previous reviews:** `review-1.md`, `review-2.md`
**Risk:** 🟢 Clean — all prior findings resolved, no new findings.

## Resolved since round 2

- ✅ **Dispose leak on native-create failure fixed.** `lib/src/api/classifiers/cardio_classifier.dart:265-282` now runs Dart-side cleanup (`_rrPpgSub.cancel()` + `_rrController.close()`) unconditionally, while gating only the native `invokeMethod` dispose on `_createError == null`. A consumer that subscribes to `rrStream` before the async native create rejects no longer leaks the EventChannel `PpgData` subscription or the broadcast controller. The accompanying comment clearly states the intent.

## Resolved earlier (still verified)

- ✅ **Dispose race** — `_rrPpgSub` cancelled before `_rrController.close()`; `onCancel` is a tolerated idempotent secondary path.
- ✅ **`_lastPpiMs` encapsulation** — underscore-prefixed; adaptive refractory cannot be externally mutated.
- ✅ **NeiryService subscription formatting** — multi-line, trailing commas, matches neighbors.
- ✅ **Adaptive refractory transitions** — null `_lastPpiMs` correctly covers both the pre-first-peak and inter-peak-1-and-2 states; only non-artifact intervals update `_lastPpiMs`.
- ✅ **Both-sides window coverage + cross-batch dedup** — trailing-edge candidates correctly defer; emitted peaks never re-emitted.
- ✅ **Buffer eviction anchor** — uses `batch.timestamps.last` (device clock), not `DateTime.now()`.
- ✅ **`_gate` ordering** — sub-300 ms intervals rejected before the cold-start branch, preventing median poisoning.
- ✅ **Empty-batch / empty-buffer guards** — early returns prevent `_buffer.first` / `_buffer.last` on an empty list.
- ✅ **Barrel export ordering** — `rr_interval.dart` after `resistance_data.dart`.
- ✅ **NeiryService wiring** — controller declared adjacent to `_cardioPpgController`, closed in matching declaration order, fan-in cancelled in `disconnect()` before `_cardio!.dispose()`.
- ✅ **No native or platform-channel changes** — pure-Dart addition.

## Findings

None.

REVIEW_PASS
