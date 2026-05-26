# Plan Review: PPG peak detection → RR interval stream

**Plan:** `.ai-factory/plans/73-ppg-peak-detection-rr-interval-stream.md`
**Spec:** `.ai-factory/notes/23-ppg-rr-interval-stream.md`
**Risk Level:** 🟡 Medium

## Context Gates

- **Architecture (`.ai-factory/ARCHITECTURE.md`)** — PASS. ARCHITECTURE.md uses `lib/src/api/`, `lib/src/models/`, `lib/src/channel/` as the three internal directories. The plan introduces a new `lib/src/processing/` sibling for the pure-Dart detector. This is a reasonable extension (it isn't an `api/` wrapper, a model, or a channel constant), but it is a new top-level subtree not described in ARCHITECTURE.md. Consider a brief ARCHITECTURE.md note if more pure-Dart DSP utilities are expected; otherwise WARN only.
- **Rules (`.ai-factory/RULES.md`)** — N/A, file not present.
- **Roadmap (`.ai-factory/ROADMAP.md`)** — Not checked against; the plan number 73 follows the established numbering, so milestone linkage is implicit.

## Critical Issues

None that block implementation. All concerns below are correctness/clarity items the implementer must resolve in code.

## Important Issues

### 1. Wrong alphabetical position in `lib/neiry_kit.dart`

Task 3 says insert `export 'src/models/rr_interval.dart';` **between** `psd_data.dart` and `resistance_data.dart`. That is incorrect alphabetically. Compare:

- `resistance_data.dart` → `r`, **`e`**, …
- `rr_interval.dart`     → `r`, **`r`**, …

`'e' < 'r'`, so `resistance_data` sorts before `rr_interval`. The correct insertion point is **after `resistance_data.dart`** (currently the last export). Fix the task wording to "insert after `resistance_data.dart`" — otherwise the implementer will produce an out-of-order barrel.

### 2. Buffer eviction uses `DateTime.now()` instead of the device timestamp clock

Task 2 step 2 anchors the buffer cutoff at `DateTime.now()`, while the samples in the buffer carry **device timestamps** decoded from `batch.timestamps[i]` (millis since epoch from the SDK / firmware). If the device clock and the system clock differ — which is common with BLE peripherals that have their own epoch or drift relative to the phone — buffer eviction will either:

- evict samples that just arrived (when device clock lags system clock), starving peak detection, or
- never evict samples (when device clock leads), letting the buffer grow unboundedly.

Safer: anchor the cutoff at the latest timestamp **in the current batch** (`batch.timestamps.last`) and subtract `bufferDurationMs`. The spec note 23 wrote `DateTime.now()` but the plan can correct it. Worth flagging explicitly in Task 2.

### 3. Adaptive refractory transition is ambiguous

Task 2 step 4 states: "before the first peak, `refractoryMs` (250 ms). After the first detected peak, `(0.55 * lastPpiMs).round()`."

The first detected peak produces no PPI (no previous peak). `lastPpiMs` is only defined after the **second** peak. So the literal transition rule has a gap: between peak 1 and peak 2, what is `_currentRefractory`?

Resolution should be explicit in the plan: keep the 250 ms floor until the **first PPI** is computed (i.e. after the second peak), then switch to `(0.55 * lastPpiMs).round()`.

### 4. Adaptive refractory must not update on artifact PPIs

The plan does not specify whether `_currentRefractory` should be updated from `rrMs` when `_gate(rrMs)` returned `true` (artifact). It must not — a 100 ms artifact spike would otherwise collapse the refractory to ~55 ms, opening the gate to a cascade of false peaks. The implementer should update `lastPpiMs` (and therefore `_currentRefractory`) only on non-artifact intervals. Add one sentence to Task 2 making this explicit.

### 5. Real-time peak confirmation latency / partial-window edge case

The peak rule says: "value is greater than every other sample within ±`_currentRefractory / 2` ms in the buffer." At the trailing edge of the buffer, the candidate sample has no future samples beyond it yet. Without a guard, the **most recent** sample in every batch can momentarily appear as a maximum (no future evidence to disqualify it), causing premature emission or repeated re-emission across batches.

The detector must require that the candidate has at least `_currentRefractory / 2` ms of samples **on both sides** in the buffer before declaring a peak. Otherwise the algorithm either lies or relies on the cross-batch "skip already-emitted peaks" guard to compensate (which still gives jitter and wrong timestamps).

Task 2 mentions "Prevent re-detection of peaks already emitted across batches" but does not require both-sides window coverage. Add this constraint explicitly.

### 6. `asBroadcastStream()` re-listen behaviour for `_rrStream`

```dart
late final Stream<RRInterval> _rrStream =
    _ppgStream.expand(_peakDetector.processBatch).asBroadcastStream();
```

Default `asBroadcastStream()` cancels its source subscription when the last downstream listener cancels. A subsequent `.listen(...)` cannot reopen the source. For the immediate consumer (`NeiryService` holds the single subscription for the connection lifetime, and `CardioClassifier` is re-created on each `connect()`), this is fine — but the public getter `rrStream` invites direct subscribers in the example app (and `mind_mobile`) who may listen/cancel/listen.

Two options:

- Document this constraint clearly on `rrStream` ("subscribe once per connection lifetime"), or
- Wire the source through a `StreamController.broadcast(onListen:..., onCancel:...)` or use `Stream.multi`/`StreamTransformer` so re-subscription works.

Other classifier streams (`stateStream`, `ppgStream`) do **not** suffer from this because they go straight off the EventChannel broadcast (which is re-listenable). `_rrStream` is the first synthetic broadcast in this codebase, so it deserves an explicit note.

### 7. Detector state persistence vs cold-start gate

`_peakDetector` is a single instance per `CardioClassifier`. `_rrHistory` and `_lastPeakTs` survive for the full connection. If the user temporarily stops/starts the device mid-connection (or PPG goes silent for a long gap and then resumes), the next peak yields a huge `rrMs` from `_lastPeakTs`, which will likely be flagged as artifact by the consistency gate (good) — but `_lastPeakTs` is still updated to the new peak, so the very next interval is computed from a real peak-to-peak distance (good).

However, `_rrHistory` cap of 5 means the cold-start grace already expired. A genuine session restart cannot benefit from cold-start again. Consider exposing a `reset()` method on `PpgPeakDetector` and calling it on `Device.stop()` → `Device.start()` cycles. Non-blocking but worth a brief mention.

## Minor / Style

- **Task 5 placement.** The plan instructs adding the rr subscription right after `_cardio!.ppgStream` in the fan-in list. That sits at lines ~195–198 in the current file. The wording is correct; just confirm the implementer keeps the trailing comma style consistent with neighbours.
- **Task 5 controller placement.** "Multiplexer controllers" section is correct; `_rrController` should sit adjacent to `_cardioPpgController` per the plan, which matches the file's ordering convention.
- **Task 5 `dispose()` close order.** `dispose()` closes controllers in the order they were declared. The plan says "close alongside the other controller closures" — be explicit: close it adjacent to `_cardioPpgController.close()` so declaration order and dispose order stay in lockstep (existing convention).
- **Task 4 doc update.** Plan adds a usage-doc example for `rrStream`. Good. Also consider documenting that `_lastPeakTs` is wall-clock (DateTime) so consumers know not to compare `RRInterval.timestamp` against monotonic clocks.
- **Provider header style.** Task 6 says mirror file/header of other `example/lib/providers/*.dart`. Files reviewed (`stream_providers.dart`) use no header comment, just imports and `final xProvider = …`. That matches.
- **Throttling on the provider.** Task 6 explicitly skips throttling. PPG batches arrive ~3.3 Hz and each batch can yield ≥1 RR. Worst-case downstream rebuild rate is one per beat (~1 Hz at resting HR, up to ~3 Hz at 180 BPM). Acceptable.

## Architectural / Cross-cutting Notes

- **`lib/src/processing/` is new.** The directory does not exist yet. Dart will create it on first file write — no scaffolding tasks needed. ARCHITECTURE.md could be amended in a separate housekeeping task if the team plans more DSP utilities (filters, downsamplers).
- **No platform/native changes.** Confirmed: the plan is pure-Dart on top of an already-available `ppgStream`. iOS/Android bridges, channel constants, and codecs are untouched. ✅
- **No migrations.** N/A.
- **No security surface.** Pure local DSP over an in-process broadcast stream.

## Positive Notes

- Plan is well-scoped: model + detector + export + classifier wiring + service wiring + provider — six small tasks with a clean two-commit grouping.
- Detector is correctly placed outside `api/` (no native coupling) and is not exported (internal implementation detail). Good encapsulation.
- Cardio classifier integration mirrors existing `_stateStream` / `_ppgStream` patterns (`_checkNotDisposed` / `_checkReady` getters, "Cached streams" / "Streams" sections).
- Provider follows existing example-app idioms (`StreamProvider` watching the service).
- Spec correctly identifies that no upper RR bound should exist (bradycardia tolerance) and uses median-based consistency as the primary artifact gate.
- Consumer contract (`isArtifact` semantics) is clear, and the doc comment requirement reinforces it.

## Recommended Plan Revisions Before Implementation

1. Fix the alphabetical insertion point in Task 3 (after `resistance_data.dart`, not between `psd_data.dart` and `resistance_data.dart`).
2. In Task 2, switch the buffer cutoff anchor from `DateTime.now()` to the latest batch device timestamp, or explicitly justify the system-clock choice.
3. In Task 2, clarify the adaptive refractory transition: keep `refractoryMs` until the first PPI is computed (i.e., second peak), then switch to `0.55 × lastPpiMs`.
4. In Task 2, state that `_currentRefractory` updates only from non-artifact PPIs.
5. In Task 2, require both-sides window coverage before declaring a peak, to avoid trailing-edge false positives.
6. In Task 4, either document "single subscriber per connection" on `rrStream` or implement it via a `StreamController.broadcast` with proper `onListen`/`onCancel` to support re-subscription cleanly.
7. Optionally add a `reset()` on `PpgPeakDetector` for stop/start cycles inside a single connection.
