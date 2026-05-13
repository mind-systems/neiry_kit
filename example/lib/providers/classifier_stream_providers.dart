import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:neiry_kit/neiry_kit.dart';
import 'package:rxdart/rxdart.dart';

import 'neiry_service_provider.dart';

/// Emits [PhysiologicalStatesValue] from the active [PhysioClassifier].
final physioStateProvider = StreamProvider<PhysiologicalStatesValue>((ref) {
  return ref.watch(neiryServiceProvider).physioStream;
});

/// Emits [EmotionsStates] from the active [EmotionsClassifier].
final emotionsStateProvider = StreamProvider<EmotionsStates>((ref) {
  return ref.watch(neiryServiceProvider).emotionsStream;
});

/// Emits [CardioData] from the active [CardioClassifier].
final cardioStateProvider = StreamProvider<CardioData>((ref) {
  return ref.watch(neiryServiceProvider).cardioStream;
});

/// Emits [PpgData] batches from the active [CardioClassifier].
final cardioPpgProvider = StreamProvider<PpgData>((ref) {
  return ref.watch(neiryServiceProvider).cardioPpgStream;
});

/// Emits [MemsSample] batches throttled to ~10 Hz.
final memsProvider = StreamProvider<List<MemsSample>>((ref) {
  return ref
      .watch(neiryServiceProvider)
      .memsStream
      .throttleTime(const Duration(milliseconds: 100));
});

/// Emits [NfbUserState] from the active [NfbClassifier].
final nfbStateProvider = StreamProvider<NfbUserState>((ref) {
  return ref.watch(neiryServiceProvider).nfbStream;
});

/// Emits [ProductivityIndexes] from the active [ProductivityClassifier].
final productivityIndexesProvider = StreamProvider<ProductivityIndexes>((ref) {
  return ref.watch(neiryServiceProvider).productivityIndexesStream;
});

/// Emits [ProductivityMetrics] from the active [ProductivityClassifier].
final productivityMetricsProvider = StreamProvider<ProductivityMetrics>((ref) {
  return ref.watch(neiryServiceProvider).productivityMetricsStream;
});

/// Emits Physio baseline-calibration progress (0.0–1.0).
final physioCalibrationProgressProvider = StreamProvider<double>((ref) {
  return ref.watch(neiryServiceProvider).physioCalibrationProgressStream;
});

/// Emits Productivity baseline-calibration progress (0.0–1.0).
final productivityCalibrationProgressProvider = StreamProvider<double>((ref) {
  return ref.watch(neiryServiceProvider).productivityCalibrationProgressStream;
});

/// Emits [PhysiologicalStatesBaselines] once when physio baseline calibration
/// completes.
final physioCalibratedProvider =
    StreamProvider<PhysiologicalStatesBaselines>((ref) =>
        ref.watch(neiryServiceProvider).physioCalibratedStream);

/// Emits once when the Cardio classifier's internal calibration completes.
final cardioCalibratedProvider = StreamProvider<DateTime>(
    (ref) => ref.watch(neiryServiceProvider).cardioCalibratedStream);

/// Holds the last calibrated or imported [PhysiologicalStatesBaselines].
///
/// Written by `PhysioActionsNotifier` in the next milestone; consumed by the
/// Export Baselines button on the Classifiers screen.
final physioBaselinesProvider =
    StateProvider<PhysiologicalStatesBaselines?>((ref) => null);
