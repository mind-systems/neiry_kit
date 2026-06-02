import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neiry_kit/neiry_kit.dart';

import '../utils/nlog.dart';
import 'neiry_service_provider.dart';

/// One-shot scan provider.
///
/// `AsyncValue.loading` = scan in progress.
/// `AsyncValue.data`    = scan complete with discovered devices.
///
/// To re-scan, call `ref.invalidate(deviceScanProvider((type, time)))`.
final deviceScanProvider =
    FutureProvider.family<List<DeviceInfo>, (NeiryDeviceType, int)>(
  (ref, params) async {
    final service = ref.read(neiryServiceProvider);
    final (type, searchTime) = params;
    nlog('[ScanProvider] starting scan type=$type searchTime=${searchTime}s', name: 'Neiry');
    try {
      final result = await service.scan(type: type, searchTime: searchTime).first;
      nlog('[ScanProvider] scan done — ${result.length} device(s): ${result.map((d) => d.serial).join(', ')}', name: 'Neiry');
      return result;
    } catch (e, st) {
      nlog('[ScanProvider] scan error: $e\n$st', name: 'Neiry');
      rethrow;
    }
  },
);
