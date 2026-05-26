import '../models/ppg_data.dart';
import '../models/rr_interval.dart';

/// Pure-Dart beat detector that converts a stream of [PpgData] batches into
/// [RRInterval] events.
///
/// Feed each [PpgData] batch to [processBatch] in order. The detector
/// maintains state across calls — do not create a new instance per batch.
///
/// Call [reset] to clear all internal state after a PPG silence (e.g.
/// after `Device.stop()` → `Device.start()` within one connection) so that the
/// cold-start grace period restarts on the first new beat.
class PpgPeakDetector {
  PpgPeakDetector({
    this.minRrMs = 300,
    this.refractoryMs = 250,
    this.consistencyThreshold = 0.40,
    this.coldStartBeats = 3,
    this.medianWindow = 5,
    this.bufferDurationMs = 3000,
  });

  /// Hard lower bound on RR intervals (ms). Below this → artifact.
  /// Corresponds to ~200 BPM, the physiological ceiling for sustained rhythm.
  final int minRrMs;

  /// Cold-start refractory period (ms). Used until the first valid PPI is
  /// established, after which the adaptive refractory (55% of last PPI) takes
  /// over.
  final int refractoryMs;

  /// Maximum fractional deviation from the rolling median before an interval
  /// is flagged as an artifact. 0.40 = 40%.
  final double consistencyThreshold;

  /// Number of initial intervals accepted without the consistency check.
  /// Seeds the rolling median before gating begins.
  final int coldStartBeats;

  /// Size of the rolling window used to compute the consistency median.
  final int medianWindow;

  /// How far back (ms) to keep PPG samples in the internal buffer.
  final int bufferDurationMs;

  // ── Internal state ─────────────────────────────────────────────────────────

  final List<({double value, DateTime ts})> _buffer = [];

  /// Timestamp of the last accepted (emitted) peak — `null` before the first
  /// peak is detected.
  DateTime? _lastPeakTs;

  /// Rolling history of non-artifact RR intervals for the consistency median.
  final List<int> _rrHistory = [];

  /// The most recent non-artifact PPI (ms). Drives the adaptive refractory.
  /// `null` until the first non-artifact interval is observed.
  int? _lastPpiMs;

  // ── Adaptive refractory ────────────────────────────────────────────────────

  int get _currentRefractory {
    if (_lastPpiMs == null) return refractoryMs;
    return (0.55 * _lastPpiMs!).round();
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Processes a batch of PPG samples and returns any newly detected
  /// [RRInterval]s.
  ///
  /// Returns an empty list when [batch] is empty or no new peaks were
  /// confirmed. Artifacts are included in the result with
  /// [RRInterval.isArtifact] set to `true`.
  List<RRInterval> processBatch(PpgData batch) {
    if (batch.values.isEmpty) return const [];

    // 1. Append new samples with their device timestamps.
    for (var i = 0; i < batch.values.length; i++) {
      _buffer.add((
        value: batch.values[i],
        ts: DateTime.fromMillisecondsSinceEpoch(batch.timestamps[i]),
      ));
    }

    // 2. Evict samples older than bufferDurationMs.
    // Anchor on the latest device timestamp in the current batch to stay on
    // the data clock rather than the phone's system clock (avoids drift issues
    // when the device clock leads or lags).
    final latestTs =
        DateTime.fromMillisecondsSinceEpoch(batch.timestamps.last);
    final cutoff =
        latestTs.subtract(Duration(milliseconds: bufferDurationMs));
    _buffer.removeWhere((s) => s.ts.isBefore(cutoff));

    if (_buffer.isEmpty) return const [];

    // 3. Detect peaks.
    final peaks = _findPeaks();

    // 4. Compute RR intervals from successive peaks.
    final results = <RRInterval>[];
    for (final peakTs in peaks) {
      if (_lastPeakTs == null) {
        // First peak ever — record it and wait for the next.
        _lastPeakTs = peakTs;
        continue;
      }

      final rrMs = peakTs.difference(_lastPeakTs!).inMilliseconds;
      _lastPeakTs = peakTs;

      final isArtifact = _gate(rrMs);
      if (!isArtifact) {
        // Update rolling history and adaptive refractory only from valid beats.
        _rrHistory.add(rrMs);
        if (_rrHistory.length > medianWindow) {
          _rrHistory.removeAt(0);
        }
        _lastPpiMs = rrMs;
      }

      results.add(RRInterval(
        intervalMs: rrMs,
        timestamp: peakTs,
        isArtifact: isArtifact,
      ));
    }
    return results;
  }

  /// Clears all internal state.
  ///
  /// Call after a PPG silence (e.g. `Device.stop()` → `Device.start()`) to
  /// restart the cold-start grace period on the first new beat.
  void reset() {
    _buffer.clear();
    _lastPeakTs = null;
    _rrHistory.clear();
    _lastPpiMs = null;
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  /// Scans the buffer and returns timestamps of newly accepted peaks.
  ///
  /// A candidate at index [i] is accepted when all three conditions hold:
  /// (a) local maximum within ±[_currentRefractory]/2 ms,
  /// (b) buffer extends ≥ [_currentRefractory]/2 ms both before and after the
  ///     candidate (prevents the trailing edge of every batch from appearing
  ///     as a spurious maximum), and
  /// (c) more than [_currentRefractory] ms have elapsed since the last accepted
  ///     peak.
  List<DateTime> _findPeaks() {
    final halfWindowMs = _currentRefractory ~/ 2;
    final bufferFirstMs = _buffer.first.ts.millisecondsSinceEpoch;
    final bufferLastMs = _buffer.last.ts.millisecondsSinceEpoch;

    DateTime? localLastPeak = _lastPeakTs;
    final accepted = <DateTime>[];

    for (var i = 0; i < _buffer.length; i++) {
      final candidate = _buffer[i];
      final candidateMs = candidate.ts.millisecondsSinceEpoch;

      // Skip samples already emitted in earlier batches.
      if (localLastPeak != null && !candidate.ts.isAfter(localLastPeak)) {
        continue;
      }

      // (c) Refractory guard: at least _currentRefractory ms since last peak.
      if (localLastPeak != null) {
        final elapsed = candidate.ts.difference(localLastPeak).inMilliseconds;
        if (elapsed <= _currentRefractory) continue;
      }

      // (b) Both-sides window coverage. Buffer must have samples reaching at
      // least halfWindowMs before AND after the candidate so the window is
      // fully observable — prevents the most-recent sample in every batch from
      // appearing as a momentary maximum.
      final hasBefore = bufferFirstMs <= candidateMs - halfWindowMs;
      final hasAfter = bufferLastMs >= candidateMs + halfWindowMs;
      if (!hasBefore || !hasAfter) continue;

      // (a) Local maximum: value must exceed every other sample within the
      // ±halfWindowMs window.
      var isMax = true;
      for (var j = 0; j < _buffer.length; j++) {
        if (j == i) continue;
        final s = _buffer[j];
        final diffMs = (s.ts.millisecondsSinceEpoch - candidateMs).abs();
        if (diffMs > halfWindowMs) continue;
        if (s.value >= candidate.value) {
          isMax = false;
          break;
        }
      }
      if (!isMax) continue;

      accepted.add(candidate.ts);
      localLastPeak = candidate.ts;
    }

    return accepted;
  }

  /// Returns `true` when [rrMs] should be flagged as an artifact.
  ///
  /// Hard lower-bound gate → consistency filter against rolling median.
  /// No upper bound is applied: extreme bradycardia (19 BPM observed in
  /// cold-water immersion) produces valid intervals > 3000 ms.
  bool _gate(int rrMs) {
    // Hard lower bound: physically impossible heart rate.
    if (rrMs < minRrMs) return true;

    // Cold-start: accept first [coldStartBeats] intervals unconditionally to
    // seed the median at any HR (including extreme bradycardia).
    if (_rrHistory.length < coldStartBeats) return false;

    // Consistency filter: flag large deviations from the rolling median.
    final sorted = [..._rrHistory]..sort();
    final median = sorted[sorted.length ~/ 2].toDouble();
    return (rrMs - median).abs() / median > consistencyThreshold;
  }
}
