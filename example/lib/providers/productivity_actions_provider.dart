import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'neiry_service_provider.dart';

/// Command-only notifier that owns baseline calibration and fatigue-reset
/// actions for the [ProductivityClassifier].
///
/// This notifier holds no state — it exists solely to issue one-shot commands
/// to the active classifier via [NeiryService]. Screen widgets call its methods
/// directly; it never rebuilds in response to service changes.
class ProductivityActionsNotifier extends Notifier<void> {
  @override
  void build() {}

  /// Starts baseline calibration on the active [ProductivityClassifier].
  ///
  /// No-op when no device is connected (i.e. `productivityClassifier` is null).
  Future<void> startBaselineCalibration() async {
    final service = ref.read(neiryServiceProvider);
    await service.productivityClassifier?.startBaselineCalibration();
  }

  /// Resets accumulated fatigue in the active [ProductivityClassifier].
  ///
  /// No-op when no device is connected (i.e. `productivityClassifier` is null).
  Future<void> resetAccumulatedFatigue() async {
    final service = ref.read(neiryServiceProvider);
    await service.productivityClassifier?.resetAccumulatedFatigue();
  }
}

final productivityActionsProvider =
    NotifierProvider<ProductivityActionsNotifier, void>(
  ProductivityActionsNotifier.new,
);
