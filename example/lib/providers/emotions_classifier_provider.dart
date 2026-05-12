import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neiry_kit/neiry_kit.dart';

import 'active_device_provider.dart';

/// Creates and manages an [EmotionsClassifier] gated on device connectivity.
///
/// Returns `null` when no device is active (disconnected). When the device
/// disconnects, the old classifier is disposed and a new one is created on the
/// next connection automatically.
class EmotionsClassifierNotifier extends Notifier<EmotionsClassifier?> {
  @override
  EmotionsClassifier? build() {
    final device = ref.watch(activeDeviceProvider);

    if (device == null) return null;

    final classifier = EmotionsClassifier(device);

    // Capture the local instance — do NOT read `state` inside the callback,
    // as state may have been replaced by the time dispose fires.
    ref.onDispose(() {
      classifier.dispose();
    });

    return classifier;
  }
}

final emotionsClassifierProvider =
    NotifierProvider<EmotionsClassifierNotifier, EmotionsClassifier?>(
  EmotionsClassifierNotifier.new,
);

/// Emits [EmotionsStates] from the active [EmotionsClassifier], or an empty
/// stream when no classifier is available.
final emotionsStateProvider = StreamProvider<EmotionsStates>((ref) {
  final classifier = ref.watch(emotionsClassifierProvider);
  if (classifier == null) return Stream.empty();
  return classifier.stateStream;
});
