import 'dart:typed_data';

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
/// Re-creates the classifier whenever the device, started-state, calibration
/// toggle, or NFB calibration data changes.
class ProductivityClassifierNotifier extends Notifier<ProductivityClassifier?> {
  @override
  ProductivityClassifier? build() {
    final device = ref.watch(activeDeviceProvider);
    final isStarted = ref.watch(deviceIsStartedProvider);

    if (device == null || !isStarted) return null;

    final nfbData = ref.watch(nfbCalibrationProvider);
    final useCalibration = ref.watch(useCalibrationToggleProvider);

    final ProductivityClassifier classifier;
    if (useCalibration && nfbData != null) {
      classifier = ProductivityClassifier.withCalibration(device, nfbData);
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
