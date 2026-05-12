import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neiry_kit/neiry_kit.dart';

import 'active_device_provider.dart';
import 'nfb_calibration_provider.dart';

/// Creates and manages an [NfbClassifier] gated on device connectivity.
///
/// Returns `null` when no device is active (disconnected). When the device
/// disconnects, the old classifier is disposed and a new one is created on the
/// next connection automatically.
class NfbClassifierNotifier extends Notifier<NfbClassifier?> {
  @override
  NfbClassifier? build() {
    final device = ref.watch(activeDeviceProvider);

    if (device == null) return null;

    final calibrationData = ref.read(nfbCalibrationProvider);
    final classifier = NfbClassifier(device, calibration: calibrationData);

    // Capture the local instance — do NOT read `state` inside the callback,
    // as state may have been replaced by the time dispose fires.
    ref.onDispose(() {
      classifier.dispose();
    });

    return classifier;
  }
}

final nfbClassifierProvider =
    NotifierProvider<NfbClassifierNotifier, NfbClassifier?>(
  NfbClassifierNotifier.new,
);

/// Emits [NfbUserState] from the active [NfbClassifier], or an empty stream
/// when no classifier is available.
final nfbStateProvider = StreamProvider<NfbUserState>((ref) {
  final classifier = ref.watch(nfbClassifierProvider);
  if (classifier == null) return Stream.empty();
  return classifier.stateStream;
});
