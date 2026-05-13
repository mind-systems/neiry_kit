import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neiry_kit/neiry_kit.dart';

import 'neiry_service_provider.dart';

/// One-shot scan provider.
///
/// `AsyncValue.loading` = scan in progress.
/// `AsyncValue.data`    = scan complete with discovered devices.
///
/// To re-scan, call `ref.invalidate(deviceScanProvider((type, time)))`.
final deviceScanProvider =
    FutureProvider.family<List<DeviceInfo>, (NeiryDeviceType, int)>(
  (ref, params) {
    final service = ref.read(neiryServiceProvider);
    final (type, searchTime) = params;
    return service.scan(type: type, searchTime: searchTime).first;
  },
);
