import 'package:flutter/foundation.dart';

/// Mirrors a single MEMS sample from `clCMEMSTimedData`.
///
/// Both [accelerometer] and [gyroscope] are Dart records that map to the
/// native `clCPoint3d` triplet (x, y, z). All fields are always valid —
/// MEMS data carries no sentinel values.
@immutable
class MemsSample {
  const MemsSample({
    required this.accelerometer,
    required this.gyroscope,
    required this.timestamp,
  });

  /// Accelerometer reading in device units, mapped from `clCPoint3d`.
  final ({double x, double y, double z}) accelerometer;

  /// Gyroscope reading in device units, mapped from `clCPoint3d`.
  final ({double x, double y, double z}) gyroscope;

  /// Timestamp of this sample.
  final DateTime timestamp;

  factory MemsSample.fromMap(Map<Object?, Object?> map) {
    return MemsSample(
      accelerometer: (
        x: (map['ax'] as num).toDouble(),
        y: (map['ay'] as num).toDouble(),
        z: (map['az'] as num).toDouble(),
      ),
      gyroscope: (
        x: (map['gx'] as num).toDouble(),
        y: (map['gy'] as num).toDouble(),
        z: (map['gz'] as num).toDouble(),
      ),
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['ts'] as int),
    );
  }
}
