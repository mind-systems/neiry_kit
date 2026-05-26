# Plan: PPG peak detection → RR interval stream

## Context
Add a beat-to-beat RR interval stream to `CardioClassifier` by running a pure-Dart peak detector over the existing `ppgStream`. No native changes — `Stream<RRInterval> get rrStream` is a derived transformation, wired through `NeiryService` and exposed in the example app via a Riverpod `StreamProvider`.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Model & detector

- [x] **Task 1: Add `RRInterval` model**
  Files: `lib/src/models/rr_interval.dart`
  Create an immutable Dart class `RRInterval` with three fields: `int intervalMs`, `DateTime timestamp`, `bool isArtifact` (default `false`). Mark `@immutable` and provide a `const` constructor with named parameters (`intervalMs` and `timestamp` required, `isArtifact` optional with default `false`). Follow the style of existing models such as `lib/src/models/ppg_data.dart` and `lib/src/models/nfb_user_state.dart`. No `fromMap` factory — this model is constructed in Dart, not decoded from a platform channel. Add a short doc comment explaining that `timestamp` is the wall-clock `DateTime` of the later peak (the one that ends the interval) — it is the phone-decoded device timestamp, not a monotonic clock, so consumers must not compare it to monotonic time sources — and that consumers must not use `isArtifact: true` ticks for animation or HRV calculation.

- [x] **Task 2: Implement `PpgPeakDetector`**
  Files: `lib/src/processing/ppg_peak_detector.dart`
  Pure-Dart class — no Flutter or platform imports. Only depends on `lib/src/models/ppg_data.dart` and `lib/src/models/rr_interval.dart`. (`lib/src/processing/` is a new directory; the file write creates it. No other scaffolding required.) Expose constructor parameters with defaults per the spec: `minRrMs = 300`, `refractoryMs = 250`, `consistencyThreshold = 0.40`, `coldStartBeats = 3`, `medianWindow = 5`, `bufferDurationMs = 3000`. Implement `List<RRInterval> processBatch(PpgData batch)` per the spec in `.ai-factory/notes/23-ppg-rr-interval-stream.md`:
    1. Append `(value, ts)` records from `batch.values` / `batch.timestamps` (decoding ms-since-epoch into `DateTime`) into an internal sample buffer. Skip empty batches early (`if (batch.values.isEmpty) return const [];`).
    2. Evict samples older than `bufferDurationMs` from the buffer. **Anchor the cutoff at the latest device timestamp in the current batch** (`batch.timestamps.last`), not `DateTime.now()`. Rationale: PPG samples carry device-clock timestamps from the SDK/firmware. The device clock can drift relative to the phone's system clock — using `DateTime.now()` either evicts fresh samples (when the device clock lags) or never evicts (when it leads). Anchoring on the latest in-batch timestamp keeps the buffer window consistent with the data clock.
    3. Call `_findPeaks()` — scans the buffer forward, returns a `List<DateTime>` of **newly accepted** peak timestamps. A sample at index `i` qualifies as a peak when **all three** hold:
       - (a) its value is greater than every other sample within `±_currentRefractory / 2` ms in the buffer, AND
       - (b) the buffer contains samples that extend at least `_currentRefractory / 2` ms **before** AND `_currentRefractory / 2` ms **after** the candidate (both-sides window coverage — without this, the most recent sample in every batch can momentarily appear as a maximum, causing premature/repeated emission), AND
       - (c) more than `_currentRefractory` ms have elapsed since the last accepted peak.
       Only consider samples newer than `_lastPeakTs` so peaks already emitted in earlier batches are never re-emitted across batch boundaries.
    4. `_currentRefractory` is adaptive with an explicit transition:
       - Before the first peak is detected: `refractoryMs` (250 ms).
       - After the first peak but **before** the first PPI is computed (i.e. between peak 1 and peak 2): still `refractoryMs` (250 ms) — there is no `lastPpiMs` yet.
       - After the second peak (first PPI exists): `(0.55 * lastPpiMs).round()`.
       `lastPpiMs` (and therefore `_currentRefractory`) is updated **only from non-artifact PPIs**. A 100 ms artifact spike must not be allowed to collapse the refractory to ~55 ms and unlock a cascade of false peaks.
    5. For each newly detected peak: if `_lastPeakTs == null`, store and continue (no interval emitted). Otherwise compute `rrMs = peakTs.difference(_lastPeakTs!).inMilliseconds`, run `_gate(rrMs)`, and:
       - When NOT artifact: append `rrMs` to `_rrHistory` (cap length at `medianWindow`, oldest dropped) AND update `lastPpiMs := rrMs` (recomputes adaptive refractory).
       - When artifact: do NOT touch `_rrHistory` or `lastPpiMs`.
       Always update `_lastPeakTs := peakTs` and always append the `RRInterval` to the result list (artifacts included, with `isArtifact: true`).
  Implement `_gate(int rrMs)` exactly per spec: return `true` (artifact) if `rrMs < minRrMs`; if `_rrHistory.length < coldStartBeats` return `false` (cold-start passes consistency check); otherwise compute the median of `_rrHistory` and return `true` when `(rrMs - median).abs() / median > consistencyThreshold`. No upper bound — extreme bradycardia is real. State kept across batches: sample buffer, `_lastPeakTs`, `_rrHistory`, `lastPpiMs`. Keep the class allocation-light per batch.
  **Also expose `void reset()`** that clears the sample buffer, `_lastPeakTs`, `_rrHistory`, and `lastPpiMs`. This lets callers re-seed the cold-start grace after a PPG silence (e.g. `Device.stop()` → `Device.start()` within one connection). The integration in Task 4 does not need to call it yet; it's provided for the consumer's future use.

- [x] **Task 3: Export `RRInterval`**
  Files: `lib/neiry_kit.dart`
  Add `export 'src/models/rr_interval.dart';` after `export 'src/models/resistance_data.dart';` (which is currently the last `src/models/*` export). Note: `'resistance_data'` < `'rr_interval'` alphabetically (`'e' < 'r'` at index 1), so `rr_interval` must come **after** `resistance_data`, not before. The detector class stays internal — do not export `ppg_peak_detector.dart`.

### Phase 2: Wire into CardioClassifier

- [x] **Task 4: Add `rrStream` to `CardioClassifier`** (depends on Tasks 1–3)
  Files: `lib/src/api/classifiers/cardio_classifier.dart`
  Import `../../models/rr_interval.dart` and `../../processing/ppg_peak_detector.dart`. Inside the class, allocate one detector instance: `final _peakDetector = PpgPeakDetector();`. Add a cached private stream in the "Cached streams" section that runs the existing PPG `EventChannel` output through the detector. Because `_ppgStream.expand(...).asBroadcastStream()` would cancel the source PPG subscription when the last downstream listener disconnects (and a later `.listen` cannot reopen it), back the stream with an explicitly managed broadcast `StreamController` so re-subscription works cleanly across listener cycles:
  ```dart
  late final StreamController<RRInterval> _rrController = () {
    StreamSubscription<PpgData>? sub;
    final controller = StreamController<RRInterval>.broadcast(
      onListen: () {
        sub = _ppgStream.listen(
          (batch) {
            for (final rr in _peakDetector.processBatch(batch)) {
              controller.add(rr);
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
    return controller;
  }();
  late final Stream<RRInterval> _rrStream = _rrController.stream;
  ```
  Close `_rrController` inside `dispose()` after the existing native dispose call (mirrors the resource-cleanup convention of the class).
  Add the public getter in the "Streams" section, mirroring the style of `ppgStream` / `stateStream` (call `_checkNotDisposed()` and `_checkReady()` then return `_rrStream`). Update the class-level Usage doc comment with a brief example showing `classifier.rrStream.listen(...)` and a note that `RRInterval.isArtifact` must be filtered out before driving animations, and that `RRInterval.timestamp` is a wall-clock `DateTime` decoded from the device timestamp (not monotonic).

### Phase 3: NeiryService & example app

- [x] **Task 5: Expose `rrStream` from `NeiryService`** (depends on Task 4)
  Files: `example/lib/services/neiry_service.dart`
  Add a broadcast controller in the "Multiplexer controllers" section immediately after `_cardioPpgController` (declaration order is the convention used for `dispose()` close order):
  ```dart
  final _rrController = StreamController<RRInterval>.broadcast();
  ```
  In `connect()`, inside the fan-in subscription list, place the new subscription immediately after the existing `_cardio!.ppgStream` subscription, matching the trailing-comma style of its neighbours:
  ```dart
  _cardio!.rrStream.listen(_rrController.add, onError: _rrController.addError),
  ```
  Add a public getter in the "Data streams" section right after `cardioPpgStream`:
  ```dart
  /// Emits beat-to-beat RR intervals derived from the raw PPG signal.
  /// Filter [RRInterval.isArtifact] before using for animation or HRV.
  Stream<RRInterval> get rrStream => _rrController.stream;
  ```
  In `dispose()`, close `_rrController` immediately after `_cardioPpgController.close()` so declaration order and close order stay in lockstep with the existing convention.

- [x] **Task 6: Add `rrProvider`** (depends on Task 5)
  Files: `example/lib/providers/rr_provider.dart`
  Create a new Riverpod provider file. Match the header/import style of `example/lib/providers/stream_providers.dart` (no header comment, just imports + provider). Import `package:flutter_riverpod/flutter_riverpod.dart`, `package:neiry_kit/neiry_kit.dart`, and `neiry_service_provider.dart`. Define an unthrottled `StreamProvider<RRInterval>`:
  ```dart
  final rrProvider = StreamProvider<RRInterval>((ref) {
    return ref.watch(neiryServiceProvider).rrStream;
  });
  ```
  No throttling — animation consumers need every beat. Worst-case downstream rebuild rate is one per beat (~1 Hz at rest, up to ~3 Hz at 180 BPM), which is well within Riverpod's comfort zone.

## Commit Plan
- **Commit 1** (after tasks 1–3): "Add RRInterval model and PpgPeakDetector"
- **Commit 2** (after tasks 4–6): "Expose rrStream through CardioClassifier, NeiryService, and example provider"

<!-- orchestrator-sessions
planner: 5a774772-b20f-430b-971b-9cde63245f36
implementer: 94e1be5a-1c51-41fe-98cd-08f315f7bcb2
-->
