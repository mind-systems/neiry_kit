# Code Review: PPG peak detection → RR interval stream

**Plan:** `.ai-factory/plans/73-ppg-peak-detection-rr-interval-stream.md`
**Spec:** `.ai-factory/notes/23-ppg-rr-interval-stream.md`
**Risk:** 🟡 Medium — one potential runtime crash on a direct-consumer dispose path, plus a few correctness/style observations.

## Files reviewed

- `lib/src/models/rr_interval.dart` (new)
- `lib/src/processing/ppg_peak_detector.dart` (new)
- `lib/src/api/classifiers/cardio_classifier.dart` (modified)
- `lib/neiry_kit.dart` (modified)
- `example/lib/services/neiry_service.dart` (modified)
- `example/lib/providers/rr_provider.dart` (new)

---

## Findings

### 1. [Important] Race: `controller.add(rr)` can throw after `dispose()` closes the broadcast controller

**Where:** `lib/src/api/classifiers/cardio_classifier.dart:172-189` (the `_rrController` initializer) and `dispose()` at line 273.

```dart
controller = StreamController<RRInterval>.broadcast(
  onListen: () {
    sub = _ppgStream.listen(
      (batch) {
        for (final rr in _peakDetector.processBatch(batch)) {
          controller.add(rr);    // ← throws after controller.close()
        }
      },
      onError: controller.addError,
    );
  },
  onCancel: () async {
    await sub?.cancel();
    sub = null;
  },
);
```

`dispose()` calls `await _rrController.close()`. For a broadcast controller, `close()`:
- Marks the controller as closed (subsequent `add` throws `StateError: 'Cannot add new events after calling close'`).
- Delivers `done` to subscribers via microtask.
- Subscribers cancel themselves on `done`, which eventually fires `onCancel` → cancels the internal PPG `sub`.

Between `close()` and `onCancel` running, the internal `sub` on `_ppgStream` is still live. Any PPG batch that arrives in that window will execute the listener body and call `controller.add(rr)` on a now-closed controller, throwing.

In the `NeiryService` happy path this is fine: `disconnect()` cancels the fan-in subscription before invoking `_cardio!.dispose()`, which drives `onCancel` → `sub.cancel()` *first*, so by the time `dispose()` calls `close()` there is no active internal subscription. However, the `CardioClassifier.dispose` doc already says "After [dispose], all stream getters throw [StateError]" — it does not require consumers to cancel listeners first. A direct consumer of `rrStream` who calls `dispose()` while still listening will hit the race.

**Fix options (one of):**
1. Cancel the internal subscription explicitly in `dispose()` before/instead of relying on `onCancel`. Promote `sub` to a class field (or capture it) and call `await sub?.cancel()` from `dispose()` before `_rrController.close()`.
2. Guard the add: `if (!controller.isClosed) controller.add(rr);`. Cheap and local.

Option 1 is cleaner because it also stops the work the detector does for batches arriving during the close window.

---

### 2. [Minor] `lastPpiMs` is a public field; should be private

**Where:** `lib/src/processing/ppg_peak_detector.dart:59`

```dart
/// The most recent non-artifact PPI (ms). Drives the adaptive refractory.
int? lastPpiMs;
```

All other internal state is `_buffer`, `_lastPeakTs`, `_rrHistory` (underscore-prefixed). `lastPpiMs` is internal bookkeeping for the adaptive refractory and is read by the private `_currentRefractory` getter. Externally it is a leaky implementation detail — a consumer could mutate it and corrupt the detector. Rename to `_lastPpiMs` for consistency and encapsulation.

---

### 3. [Minor] Cold-start gate doesn't reject the first interval if it's below `minRrMs` from a sub-300ms spike — actually behaves correctly, but worth double-checking

The hard lower bound (`rrMs < minRrMs` → artifact) runs before the cold-start clause, so a 100 ms spike on the very first interval is correctly flagged as artifact and never poisons `_rrHistory`. ✅ No issue — flagged here only because the ordering is subtle.

---

### 4. [Minor] `_lastPeakTs` is updated on artifact peaks too

This matches the spec ("Always update `_lastPeakTs := peakTs`"), but it means a single spurious local-maximum that survives `_findPeaks` (e.g. a noise spike farther than `_currentRefractory` after the last real peak but smaller than the next real systolic peak) shifts the reference forward. The next real beat's interval is then measured from the spurious peak. The consistency gate catches gross cases, but during cold-start (first 3 beats) this could seed the median with a slightly skewed value. Documented behavior, no change required; just calling it out.

---

### 5. [Observation] Extreme bradycardia below ~10 BPM falls off the buffer

At PPI = 6000 ms, adaptive refractory ≈ 3300 ms → `halfWindowMs` ≈ 1650 ms. The buffer holds 3000 ms of samples (`bufferDurationMs = 3000`), so the "both-sides ≥ halfWindowMs" requirement can fail (1650 + 1650 = 3300 ms > 3000 ms). Below ~10 BPM (well past clinical concern) detection breaks. Acceptable; mentioned for awareness.

---

### 6. [Observation] `_findPeaks` is O(n²) per batch

The outer loop is over `_buffer`, and for each candidate the inner loop also iterates the whole buffer to check the ±halfWindow neighborhood. With a 3 s buffer at ~256 Hz PPG (~768 samples) and one batch every ~300 ms, this is roughly 590 000 comparisons per batch — well within budget on a modern phone, but if the PPG sample rate ever rises significantly this should switch to a two-pointer sweep bounded by `halfWindowMs`. Not a fix-now issue.

---

### 7. [Observation] No reset hook on `Device.stop()` → `Device.start()`

The plan adds `PpgPeakDetector.reset()` but `CardioClassifier` never calls it. Consumers cycling `Device.stop()`/`Device.start()` within one connection will not benefit from a fresh cold-start grace and will likely see the first new beat flagged as artifact (huge `rrMs` from the stale `_lastPeakTs`). Plan acknowledges this is left to the consumer; just noting that the hook is currently unused.

---

### 8. [Style] Trailing-comma formatting of the new rr subscription line

`example/lib/services/neiry_service.dart:200` is a single-line subscription while every neighbor uses multi-line block style with trailing commas:

```dart
_cardio!.rrStream.listen(_rrController.add, onError: _rrController.addError),
```

A `dart format` run will reformat this to the multi-line style. Trivial, but worth catching to keep diffs clean.

---

## Verified — no issues

- **Barrel export order** (`lib/neiry_kit.dart:34`) — `'rr_interval.dart'` correctly placed after `'resistance_data.dart'` (alphabetical, `'e' < 'r'`).
- **`_eventStream` produces a broadcast stream** — `EventChannel.receiveBroadcastStream()` is broadcast and `Stream.map` preserves that, so the inner `_ppgStream.listen(...)` inside `_rrController.onListen` does not conflict with the separate `_cardio!.ppgStream.listen(...)` subscription in `NeiryService`. Multiple listeners on the same PPG broadcast stream are supported.
- **Adaptive refractory transition** — implemented per plan: `lastPpiMs == null` ⇒ `refractoryMs` (covers both the "before first peak" and "between peak 1 and peak 2" cases); after the first non-artifact interval, switches to `(0.55 * lastPpiMs).round()`. Artifact intervals do not update `lastPpiMs`, so a 100 ms spike cannot collapse the refractory.
- **Both-sides window coverage** — `hasBefore`/`hasAfter` correctly guard against trailing-edge spurious maxima; combined with the `!candidate.ts.isAfter(localLastPeak)` filter, peaks emitted in prior batches are never re-emitted.
- **Buffer eviction anchor** — uses `batch.timestamps.last` (device clock) instead of `DateTime.now()`, matching the plan and avoiding device/system clock drift issues.
- **Cold-start ordering** — `_gate` returns `true` (artifact) before the cold-start branch for sub-300 ms intervals, so noise spikes can never poison the rolling median.
- **NeiryService disconnect ordering** — fan-in `s.cancel()` runs before `_cardio!.dispose()`, which means the internal PPG sub inside Cardio's `_rrController` is cancelled via `onCancel` before `close()` is reached. The race in finding (1) is not triggered along this path.
- **No native/platform changes** — confirmed pure-Dart addition, no platform channel methods, no codecs, no AAR/framework changes.
- **`RRInterval` semantics** — `@immutable`, `const` constructor, doc comment covers wall-clock vs monotonic and artifact filtering.

---

## Recommendation

Address finding **(1)** before shipping — it's a real (if uncommon) crash on a documented dispose path. The remaining findings are minor / observational and can be folded into a follow-up.

