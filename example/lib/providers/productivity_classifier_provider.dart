import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:neiry_kit/neiry_kit.dart';

import 'active_device_provider.dart';
import 'device_state_providers.dart';
import 'nfb_calibration_provider.dart';

/// Toggle shared between Productivity and Cardio classifier providers.
///
/// When `true` and [nfbCalibrationProvider] holds data, classifiers are
/// initialised with individual NFB calibration data.
final useCalibrationToggleProvider = StateProvider<bool>((ref) => false);

/// Creates and manages a [ProductivityClassifier] gated on device connectivity
/// and EEG streaming state.
///
/// Returns `null` when no device is active or streaming has not been started.
///
/// The classifier is created when the device transitions to the started state
/// and destroyed when it stops. The Capsule SDK has no per-classifier destroy
/// function, so re-creating a classifier against an already-streaming device
/// aborts the process on Android. The calibration toggle is therefore only safe
/// to flip while the device is **not** started — the example screens enforce
/// this by disabling the `Switch` during streaming. Calibration data is read
/// once at build time; a newly-imported calibration takes effect on the next
/// `Device.stop()` → `Device.start()` cycle.
///
/// On Android, individual-NFB Productivity calibration is not available
/// (`clCProductivity_CreateWithIndividualData` is not exported by the Capsule
/// AAR). The calibration toggle still gates the [CardioClassifier], which does
/// support calibration on Android.
class ProductivityClassifierNotifier extends Notifier<ProductivityClassifier?> {
  @override
  ProductivityClassifier? build() {
    final device = ref.watch(activeDeviceProvider);
    final isStarted = ref.watch(deviceIsStartedProvider);

    if (device == null || !isStarted) return null;

    final nfbData = ref.read(nfbCalibrationProvider);
    final useCalibration = ref.watch(useCalibrationToggleProvider);

    final ProductivityClassifier classifier;
    if (useCalibration && nfbData != null) {
      ProductivityClassifier? calibrated;
      try {
        calibrated = ProductivityClassifier.withCalibration(device, nfbData);
      } on UnsupportedError {
        debugPrint(
          'ProductivityClassifier.withCalibration unsupported on this platform; '
          'falling back to plain factory',
        );
      }
      classifier = calibrated ?? ProductivityClassifier(device);
    } else {
      classifier = ProductivityClassifier(device);
    }

    // Capture the local instance — do NOT read `state` inside the callback,
    // as state may have been replaced by the time dispose fires.
    ref.onDispose(() {
      classifier.dispose();
    });

    return classifier;
  }

  /// Starts baseline calibration on the active classifier.
  ///
  /// No-ops when no classifier is available.
  Future<void> startBaselineCalibration() async {
    await state?.startBaselineCalibration();
  }

  /// Resets accumulated fatigue on the active classifier.
  ///
  /// No-ops when no classifier is available.
  Future<void> resetAccumulatedFatigue() async {
    await state?.resetAccumulatedFatigue();
  }

  /// Imports [data] baselines into the active classifier.
  ///
  /// No-ops when no classifier is available.
  Future<void> importBaselines(Uint8List data) async {
    await state?.importBaselines(data);
  }
}

final productivityClassifierProvider =
    NotifierProvider<ProductivityClassifierNotifier, ProductivityClassifier?>(
  ProductivityClassifierNotifier.new,
);

/// Emits [ProductivityMetrics] from the active [ProductivityClassifier], or an
/// empty stream when no classifier is available.
final productivityMetricsProvider = StreamProvider<ProductivityMetrics>((ref) {
  final classifier = ref.watch(productivityClassifierProvider);
  if (classifier == null) return Stream.empty();
  return classifier.metricsStream;
});

/// Emits [ProductivityIndexes] from the active [ProductivityClassifier], or an
/// empty stream when no classifier is available.
final productivityIndexesProvider = StreamProvider<ProductivityIndexes>((ref) {
  final classifier = ref.watch(productivityClassifierProvider);
  if (classifier == null) return Stream.empty();
  return classifier.indexesStream;
});

/// Emits [ProductivityBaselines] from the active [ProductivityClassifier], or
/// an empty stream when no classifier is available.
final productivityBaselinesProvider =
    StreamProvider<ProductivityBaselines>((ref) {
  final classifier = ref.watch(productivityClassifierProvider);
  if (classifier == null) return Stream.empty();
  return classifier.baselineStream;
});

/// Emits calibration progress (0.0–1.0) from the active
/// [ProductivityClassifier] during an active baseline calibration.
final productivityCalibrationProgressProvider = StreamProvider<double>((ref) {
  final classifier = ref.watch(productivityClassifierProvider);
  if (classifier == null) return Stream.empty();
  return classifier.calibrationProgress;
});

/// Emits the opaque baselines blob once when baseline calibration completes.
final productivityCalibratedProvider = StreamProvider<Uint8List>((ref) {
  final classifier = ref.watch(productivityClassifierProvider);
  if (classifier == null) return Stream.empty();
  return classifier.calibrated;
});
