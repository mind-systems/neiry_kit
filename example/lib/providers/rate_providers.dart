import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/rate_counter.dart';
import 'neiry_service_provider.dart';

/// Measured event rate (Hz) for each raw stream, computed over a 3-second
/// rolling window. Use these providers to observe how often the SDK fires
/// each classifier callback — important for sizing buffers and deciding
/// whether client-side batching is needed.

final nfbRateProvider = StreamProvider<double>((ref) {
  return rateOf(ref.watch(neiryServiceProvider).nfbStream);
});

final emotionsRateProvider = StreamProvider<double>((ref) {
  return rateOf(ref.watch(neiryServiceProvider).emotionsStream);
});

final cardioRateProvider = StreamProvider<double>((ref) {
  return rateOf(ref.watch(neiryServiceProvider).cardioStream);
});

final cardioPpgRateProvider = StreamProvider<double>((ref) {
  return rateOf(ref.watch(neiryServiceProvider).cardioPpgStream);
});

/// Raw EEG callback rate — how many times the SDK fires the EEG batch event
/// per second (not the number of samples per second).
final eegCallbackRateProvider = StreamProvider<double>((ref) {
  return rateOf(ref.watch(neiryServiceProvider).eegStream);
});

final psdRateProvider = StreamProvider<double>((ref) {
  return rateOf(ref.watch(neiryServiceProvider).psdStream);
});
