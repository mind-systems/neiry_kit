import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neiry_kit/neiry_kit.dart';

import 'classifier_stream_providers.dart';
import 'neiry_service_provider.dart';

/// Command-only notifier that owns baseline calibration and import actions for
/// the [PhysioClassifier].
///
/// This notifier holds no state — it exists solely to issue one-shot commands
/// to the active classifier via [NeiryService]. Screen widgets call its methods
/// directly; it never rebuilds in response to service changes.
class PhysioActionsNotifier extends Notifier<void> {
  @override
  void build() {}

  /// Starts baseline calibration on the active [PhysioClassifier].
  ///
  /// No-op when no device is connected (i.e. `physioClassifier` is null).
  Future<void> startBaselineCalibration() async {
    final service = ref.read(neiryServiceProvider);
    await service.physioClassifier?.startBaselineCalibration();
  }

  /// Imports [baselines] into the active [PhysioClassifier] and stores them in
  /// [physioBaselinesProvider] on success.
  ///
  /// No-op (including the provider write) when no device is connected.
  Future<void> importBaselines(PhysiologicalStatesBaselines baselines) async {
    final service = ref.read(neiryServiceProvider);
    final classifier = service.physioClassifier;
    if (classifier == null) return;
    await classifier.importBaselines(baselines);
    ref.read(physioBaselinesProvider.notifier).state = baselines;
  }
}

final physioActionsProvider =
    NotifierProvider<PhysioActionsNotifier, void>(PhysioActionsNotifier.new);
