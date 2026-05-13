import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neiry_kit/neiry_kit.dart';
import 'package:rxdart/rxdart.dart';

import 'neiry_service_provider.dart';

/// Emits EEG sample batches throttled to ~10 Hz (one event per 100 ms).
final eegProvider = StreamProvider<EegData>((ref) {
  final service = ref.watch(neiryServiceProvider);
  return service.eegStream.throttleTime(const Duration(milliseconds: 100));
});

/// Emits PSD frames throttled to ~2 Hz (one event per 500 ms).
final psdProvider = StreamProvider<PsdData>((ref) {
  final service = ref.watch(neiryServiceProvider);
  return service.psdStream.throttleTime(const Duration(milliseconds: 500));
});

/// Emits battery charge level (0–100) throttled to ~1 Hz.
final batteryProvider = StreamProvider<int>((ref) {
  final service = ref.watch(neiryServiceProvider);
  return service.batteryStream.throttleTime(const Duration(milliseconds: 1000));
});

/// Emits per-channel artifact flags and quality metrics — unthrottled so that
/// artifact events trigger immediate visual feedback.
final artifactsProvider = StreamProvider<EegArtifactData>((ref) {
  final service = ref.watch(neiryServiceProvider);
  return service.artifactsStream;
});

/// Accumulates resistance readings into a channel-name → kOhm map.
///
/// Resistance fires per-channel independently, so individual readings are
/// merged into a single map rather than being exposed as a stream.
/// Subscribes as soon as a device is active — resistance is used for
/// impedance checking before EEG streaming starts.
class ResistanceMapNotifier extends Notifier<Map<String, double>> {
  StreamSubscription<ResistanceData>? _subscription;

  @override
  Map<String, double> build() {
    final service = ref.watch(neiryServiceProvider);
    _subscription?.cancel();
    _subscription = service.resistanceStream.listen((data) {
      final updated = Map<String, double>.of(state);
      for (var i = 0; i < data.channelCount; i++) {
        updated[data.channelNames[i]] = data.values[i];
      }
      state = updated;
    });

    ref.onDispose(() {
      _subscription?.cancel();
      _subscription = null;
    });

    return {};
  }
}

final resistanceMapProvider =
    NotifierProvider<ResistanceMapNotifier, Map<String, double>>(
  ResistanceMapNotifier.new,
);
