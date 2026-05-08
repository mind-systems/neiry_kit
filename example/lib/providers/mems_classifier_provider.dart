import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:neiry_kit/neiry_kit.dart';
import 'package:rxdart/rxdart.dart';

import 'active_device_provider.dart';
import 'device_state_providers.dart';
import 'nfb_calibration_provider.dart';

/// Toggle controlling whether the MEMS classifier is initialised with
/// individual NFB calibration data.
///
/// Ignored when [nfbCalibrationProvider] holds no data.
final useMemsCalibrationToggleProvider = StateProvider<bool>((ref) => false);

/// Creates and manages a [MEMSClassifier] gated on device connectivity and
/// EEG streaming state.
///
/// Returns `null` when no device is active or streaming has not been started.
/// Re-creates the classifier whenever the device, started-state, calibration
/// toggle, or NFB calibration data changes.
class MEMSClassifierNotifier extends Notifier<MEMSClassifier?> {
  @override
  MEMSClassifier? build() {
    final device = ref.watch(activeDeviceProvider);
    final isStarted = ref.watch(deviceIsStartedProvider);

    if (device == null || !isStarted) return null;

    final nfbData = ref.watch(nfbCalibrationProvider);
    final useCalibration = ref.watch(useMemsCalibrationToggleProvider);

    final MEMSClassifier classifier;
    if (useCalibration && nfbData != null) {
      classifier = MEMSClassifier.withCalibration(device, nfbData);
    } else {
      classifier = MEMSClassifier(device);
    }

    // Capture the local instance — do NOT read `state` inside the callback,
    // as state may have been replaced by the time dispose fires.
    ref.onDispose(() {
      classifier.dispose();
    });

    return classifier;
  }
}

final memsClassifierProvider =
    NotifierProvider<MEMSClassifierNotifier, MEMSClassifier?>(
  MEMSClassifierNotifier.new,
);

/// Emits [MemsSample] batches from the active [MEMSClassifier] throttled to
/// ~10 Hz (one event per 100 ms), or an empty stream when no classifier is
/// available.
final memsProvider = StreamProvider<List<MemsSample>>((ref) {
  final classifier = ref.watch(memsClassifierProvider);
  if (classifier == null) return Stream.empty();
  return classifier.memsStream.throttleTime(const Duration(milliseconds: 100));
});
