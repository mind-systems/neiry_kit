import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:neiry_kit/neiry_kit.dart';

import 'active_device_provider.dart';

/// Holds the last calibrated or imported [PhysiologicalStatesBaselines].
///
/// Used to drive the enabled/disabled state of the Export Baselines button and
/// to carry the baselines value into the export call.
final physioBaselinesProvider =
    StateProvider<PhysiologicalStatesBaselines?>((ref) => null);

/// Creates and manages a [PhysioClassifier] gated on device connectivity.
///
/// Returns `null` when no device is active (disconnected). When the device
/// disconnects, the old classifier is disposed and a new one is created on the
/// next connection automatically.
class PhysioClassifierNotifier extends Notifier<PhysioClassifier?> {
  @override
  PhysioClassifier? build() {
    final device = ref.watch(activeDeviceProvider);

    if (device == null) return null;

    final classifier = PhysioClassifier(device);

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

  /// Imports [baselines] into the active classifier and persists them to
  /// [physioBaselinesProvider] so the export button becomes enabled.
  Future<void> importBaselines(PhysiologicalStatesBaselines baselines) async {
    await state?.importBaselines(baselines);
    ref.read(physioBaselinesProvider.notifier).state = baselines;
  }
}

final physioClassifierProvider =
    NotifierProvider<PhysioClassifierNotifier, PhysioClassifier?>(
  PhysioClassifierNotifier.new,
);

/// Emits [PhysiologicalStatesValue] from the active [PhysioClassifier], or an
/// empty stream when no classifier is available.
final physioStateProvider = StreamProvider<PhysiologicalStatesValue>((ref) {
  final classifier = ref.watch(physioClassifierProvider);
  if (classifier == null) return Stream.empty();
  return classifier.stateStream;
});

/// Emits calibration progress (0.0–1.0) from the active [PhysioClassifier]
/// during an active baseline calibration.
final physioCalibrationProgressProvider = StreamProvider<double>((ref) {
  final classifier = ref.watch(physioClassifierProvider);
  if (classifier == null) return Stream.empty();
  return classifier.calibrationProgress;
});

/// Emits [PhysiologicalStatesBaselines] once when baseline calibration completes.
///
/// As a side effect, each emitted value is also written to [physioBaselinesProvider]
/// so the export button becomes enabled immediately after calibration.
final physioCalibratedProvider =
    StreamProvider<PhysiologicalStatesBaselines>((ref) {
  final classifier = ref.watch(physioClassifierProvider);
  if (classifier == null) return Stream.empty();

  return classifier.calibrated.map((baselines) {
    ref.read(physioBaselinesProvider.notifier).state = baselines;
    return baselines;
  });
});
