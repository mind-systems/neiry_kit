import 'package:flutter/foundation.dart';

import '../channel/enums.dart';

/// Immutable description of a discovered Neiry device.
///
/// Mirrors the device list entry returned by `clCDeviceLocator_SetOnDeviceListEvent`.
@immutable
class DeviceInfo {
  const DeviceInfo({
    required this.serial,
    required this.name,
    required this.type,
  });

  /// Hardware serial number that uniquely identifies the device.
  final String serial;

  /// Human-readable device name.
  final String name;

  /// Device category (headband, buds, simulator, etc.).
  final NeiryDeviceType type;

  factory DeviceInfo.fromMap(Map<Object?, Object?> map) {
    return DeviceInfo(
      serial: map['serial'] as String,
      name: map['name'] as String,
      type: NeiryDeviceType.fromCode(map['type'] as int),
    );
  }
}
