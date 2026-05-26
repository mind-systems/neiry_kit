# PPG Peak Detection — RR Interval Stream

**Date:** 2026-05-24
**Source:** conversation context

## Key Findings

- Raw PPG with per-millisecond timestamps is already available in `CardioClassifier.ppgStream` — zero native changes required.
- PPG fires at ~3.3 Hz; at a typical PPG sample rate of ~256 Hz each batch carries ~77 samples — enough for reliable peak detection within a single batch window.
- Motion artifacts **can and do** produce false short RR intervals (e.g. 100 ms spike → 700 ms real beat). A hard lower gate (RR < 300 ms) plus a consistency filter against a rolling median catches virtually all of these. There is no upper bound — diving reflex can produce 5.6 BPM (10 700 ms RR), documented in cold-water immersion research.
- The stream emits `RRInterval` for every detected beat including artifacts (`isArtifact: true`) so the consumer can choose its own fallback behaviour. The consumer must never use `isArtifact: true` ticks for animation.
- This is a pure-Dart addition. `CardioClassifier` gains one new `Stream<RRInterval> get rrStream` backed by `PpgPeakDetector`. No iOS or Android bridge changes.

## Details

### Model — `lib/src/models/rr_interval.dart`

```dart
class RRInterval {
  /// Duration between this beat and the previous one, in milliseconds.
  final int intervalMs;

  /// Timestamp of the beat that ended this interval (the later peak).
  final DateTime timestamp;

  /// True when this interval was flagged as a likely artifact. Do not use
  /// for animation or HRV calculation. The consumer should hold the last
  /// valid interval or fall back to a timer.
  final bool isArtifact;

  const RRInterval({
    required this.intervalMs,
    required this.timestamp,
    this.isArtifact = false,
  });
}
```

Export from `lib/neiry_kit.dart`.

### Algorithm — `lib/src/processing/ppg_peak_detector.dart`

Pure Dart class. No imports from Flutter or native layers.

**Constants (tunable via constructor):**

| Constant | Default | Rationale |
|---|---|---|
| `minRrMs` | 300 | 200 BPM hard ceiling. Cardiac muscle cannot physically contract faster than this in sustained rhythm. |
| `refractoryMs` | 250 | Minimum spacing between candidate peaks during peak detection — used only as a cold-start floor before the first peak is detected. After the first peak, the detector uses an **adaptive refractory** of 55% of the previous PPI (peer-reviewed standard). This matters at low HR: at 19 BPM (PPI ≈ 3160 ms), adaptive refractory = 1740 ms, which prevents the dicrotic notch from being misread as a second beat. At 60 BPM (PPI = 1000 ms), adaptive refractory = 550 ms — well above the dicrotic notch timing. |
| `consistencyThreshold` | 0.40 | 40% deviation from rolling median triggers artifact flag. This is the **primary** artifact detector — it catches missed-peak artifacts (doubled interval ≈ 100% deviation) at any heart rate including extreme bradycardia (diving reflex, elite athletes, cold-water immersion). Do not add a `maxRrMs` upper bound — it has no valid physiological basis and will false-flag real slow HRs. 19 BPM has been observed on Garmin during cold-water immersion; 35–40 BPM is normal for professional cyclists at rest. |
| `coldStartBeats` | 3 | Number of initial beats accepted without consistency check (no history yet). These first intervals seed the rolling median. |
| `medianWindow` | 5 | Rolling window size for median. |
| `bufferDurationMs` | 3000 | How far back to keep PPG samples in memory. |

**Processing loop (called on every `PpgData` batch):**

```dart
List<RRInterval> processBatch(PpgData batch) {
  // 1. Append new samples with their native timestamps.
  for (var i = 0; i < batch.values.length; i++) {
    _buffer.add((
      value: batch.values[i],
      ts: DateTime.fromMillisecondsSinceEpoch(batch.timestamps[i]),
    ));
  }

  // 2. Evict samples older than bufferDurationMs to bound memory.
  final cutoff = DateTime.now().subtract(Duration(milliseconds: bufferDurationMs));
  _buffer.removeWhere((s) => s.ts.isBefore(cutoff));

  // 3. Find local maxima respecting the refractory period.
  final peaks = _findPeaks(); // returns List<DateTime>

  // 4. For each new peak after the first, compute RR and gate.
  final results = <RRInterval>[];
  for (final peakTs in peaks) {
    if (_lastPeakTs == null) { _lastPeakTs = peakTs; continue; }
    final rrMs = peakTs.difference(_lastPeakTs!).inMilliseconds;
    _lastPeakTs = peakTs;
    final isArtifact = _gate(rrMs);
    if (!isArtifact) _recordValid(rrMs);
    results.add(RRInterval(intervalMs: rrMs, timestamp: peakTs, isArtifact: isArtifact));
  }
  return results;
}
```

**Peak detection (`_findPeaks`):**

Iterate `_buffer` forward. A sample at index `i` is a peak if:
1. Its value is greater than all samples within a local window of ±`_currentRefractory / 2` ms, AND
2. More than `_currentRefractory` ms have elapsed since the last accepted peak.

`_currentRefractory` is **adaptive**: after the first peak is detected, it equals `0.55 × lastPPI` (peer-reviewed standard for PPG). Before the first peak it falls back to the constant `refractoryMs = 250`. The adaptive value is critical at low HR — at 19 BPM (PPI ≈ 3160 ms), `_currentRefractory` grows to ~1740 ms, preventing the dicrotic notch (a smaller secondary hump that appears ~200–400 ms after the systolic peak in a slow PPG waveform) from being misread as a second heartbeat.

**Artifact gate (`_gate`):**

```dart
bool _gate(int rrMs) {
  if (rrMs < minRrMs) return true;  // only hard lower bound; no upper bound
  // Cold-start: accept first coldStartBeats intervals unconditionally so the
  // median seeds correctly at any HR (including extreme bradycardia).
  if (_rrHistory.length < coldStartBeats) return false;
  final sorted = [..._rrHistory]..sort();
  final median = sorted[sorted.length ~/ 2].toDouble();
  if ((rrMs - median).abs() / median > consistencyThreshold) return true;
  return false;
}
```

### Integration into `CardioClassifier`

In `lib/src/api/classifiers/cardio_classifier.dart`, add:

```dart
final _peakDetector = PpgPeakDetector();

/// Emits beat-to-beat intervals derived from the raw PPG signal.
/// [RRInterval.isArtifact] is true when the interval was flagged by the
/// physiological gate or consistency filter — skip these in animation logic.
late final Stream<RRInterval> rrStream =
    ppgStream.expand(_peakDetector.processBatch).asBroadcastStream();
```

No new EventChannel, no platform method — the stream is a pure Dart transformation of the existing `ppgStream`.

### Integration into `NeiryService`

Add in `example/lib/services/neiry_service.dart`:

```dart
// StreamController mirror (same pattern as cardioStream):
final _rrController = StreamController<RRInterval>.broadcast();

// In _connect(), after subscribing cardio streams:
_subscriptions.add(
  _cardio!.rrStream.listen(_rrController.add, onError: _rrController.addError),
);

// Public getter:
Stream<RRInterval> get rrStream => _rrController.stream;
```

Add `_rrController.close()` in `disconnect()` cleanup block alongside other controllers.

### Riverpod provider

Create `example/lib/providers/rr_provider.dart`:

```dart
final rrProvider = StreamProvider<RRInterval>((ref) {
  return ref.watch(neiryServiceProvider).rrStream;
});
```

No throttle — animation consumers need every beat.

### Consumer guide — `ITickService` wrapper in `mind_mobile`

`ITickService` in `mind_mobile/packages/breath_module/lib/src/ITickService.dart`:

```dart
abstract class ITickService {
  Stream<TickData> get tickStream;
  TickSource get source;
  void dispose();
}
class TickData { final int intervalMs; TickData(this.intervalMs); }
```

Implement `CardioTickService` in mind_mobile:

```dart
class CardioTickService implements ITickService {
  final Stream<RRInterval> _rrStream;
  int _lastValidIntervalMs = 1000; // fallback until first valid beat

  CardioTickService(this._rrStream);

  @override
  Stream<TickData> get tickStream => _rrStream
      .where((rr) => !rr.isArtifact)           // drop artifact beats
      .map((rr) {
        _lastValidIntervalMs = rr.intervalMs;
        return TickData(rr.intervalMs);
      });

  @override
  TickSource get source => TickSource.heartbeat;

  @override
  void dispose() {}
}
```

The calling code picks between `TimerTickService` (constant 1000 ms) and `CardioTickService` at runtime. If cardio loses signal, the stream goes quiet — the animation layer should detect silence (no tick for 2× last interval) and fall back to `TimerTickService` automatically. This fallback belongs in `mind_mobile`, not in neiry_kit.

### Artifact question — what actually happens

A PPG motion artifact is a mechanical displacement of the sensor that briefly saturates or deflects the signal, creating a spike that the peak detector misreads as a heartbeat.

**Scenario:** real RR = 800 ms, artifact spike at t + 100 ms after last real beat.

```
t=0    real beat (peak)  → _lastPeakTs = t
t=100  artifact spike    → detected as peak, rrMs = 100 ms → gate: 100 < 300 → isArtifact=true, emitted but skipped by consumer
t=800  real beat (peak)  → rrMs = 700 ms → gate: ok? 700 > 300, median check (history has real RRs ≈ 800 ms): |700-800|/800 = 12.5% < 40% → valid
```

With the gate in place the consumer never sees 100 ms. It sees a valid 700 ms tick (slightly short but within tolerance). The animation beats once, at a slightly accelerated pace — indistinguishable from a normal beat. Without the gate the animation would stutter with a micro-flash at 100 ms + a beat at 700 ms.

**Missed peak scenario:** artifact suppresses a real beat. Consumer sees 1600 ms instead of 800 ms. Consistency filter: |1600 − 800| / 800 = 100% > 40% → `isArtifact=true`, skipped. Animation pauses for one expected beat, then resumes. This is the worst-case user experience — one missed pulse in the animation. Works correctly at any HR including extreme bradycardia because the filter compares against the actual rolling median, not a fixed threshold.

`CardioData.motionArtifacts` reflects the SDK's own PPG quality assessment over a longer window. Both flags are complementary — the consumer should treat `isArtifact=true` OR `motionArtifacts=true` as reasons to coast on the last known interval.

## Open Questions

- PPG sample rate is queried at runtime via `Device.getPPGSampleRate()` — the peak detection algorithm does not currently use it (it uses timestamps directly). If timestamps are unreliable on some firmware versions, the sample rate could be used as a fallback for peak spacing. Worth validating on real hardware.
- The algorithm assumes a standard PPG morphology (one dominant systolic peak per beat). If the Neiry sensor produces a different waveform shape (e.g. inverted), the peak detector should switch to valley detection. Check raw PPG plot on first real-device run.
