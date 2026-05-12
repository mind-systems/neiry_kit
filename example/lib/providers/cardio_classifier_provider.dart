import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neiry_kit/neiry_kit.dart';

import 'active_device_provider.dart';
import 'nfb_calibration_provider.dart';
import 'productivity_classifier_provider.dart';

/// Creates and manages a [CardioClassifier] gated on device connectivity.
///
/// Returns `null` when no device is active (disconnected).
///
/// The classifier is created when the device connects and destroyed when it
/// disconnects. The Capsule SDK has no per-classifier destroy function, so
/// re-creating a classifier against an already-connected device aborts the
/// process on Android. The calibration toggle is therefore only safe to flip
/// while the device is **disconnected** — the example screens enforce this by
/// disabling the `Switch` unless the device is idle. Calibration data is read
/// once at build time; a newly-imported calibration takes effect on the next
/// `Device.disconnect()` → `Device.connect()` cycle.
class CardioClassifierNotifier extends Notifier<CardioClassifier?> {
  @override
  CardioClassifier? build() {
    final device = ref.watch(activeDeviceProvider);

    if (device == null) return null;

    final nfbData = ref.read(nfbCalibrationProvider);
    final useCalibration = ref.watch(useCalibrationToggleProvider);

    final CardioClassifier classifier;
    if (useCalibration && nfbData != null) {
      classifier = CardioClassifier.withCalibration(device, nfbData);
    } else {
      classifier = CardioClassifier(device);
    }

    // Capture the local instance — do NOT read `state` inside the callback,
    // as state may have been replaced by the time dispose fires.
    ref.onDispose(() {
      classifier.dispose();
    });

    return classifier;
  }
}

final cardioClassifierProvider =
    NotifierProvider<CardioClassifierNotifier, CardioClassifier?>(
  CardioClassifierNotifier.new,
);

/// Emits [CardioData] from the active [CardioClassifier], or an empty stream
/// when no classifier is available.
final cardioStateProvider = StreamProvider<CardioData>((ref) {
  final classifier = ref.watch(cardioClassifierProvider);
  if (classifier == null) return Stream.empty();
  return classifier.stateStream;
});

/// Emits [PpgData] batches from the active [CardioClassifier], or an empty
/// stream when no classifier is available.
final cardioPpgProvider = StreamProvider<PpgData>((ref) {
  final classifier = ref.watch(cardioClassifierProvider);
  if (classifier == null) return Stream.empty();
  return classifier.ppgStream;
});

/// Emits once when the Cardio classifier's internal calibration completes.
final cardioCalibratedProvider = StreamProvider<void>((ref) {
  final classifier = ref.watch(cardioClassifierProvider);
  if (classifier == null) return Stream.empty();
  return classifier.calibratedStream;
});
