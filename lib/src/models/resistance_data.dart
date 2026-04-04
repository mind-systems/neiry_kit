import 'package:flutter/foundation.dart';

/// Mirrors data from `clCResistance` accessor functions.
///
/// Contains per-channel electrode resistance values used to verify electrode
/// contact quality before EEG streaming.
@immutable
class ResistanceData {
  const ResistanceData({
    required this.channelNames,
    required this.values,
    required this.channelCount,
  });

  /// Electrode names, one per channel.
  final List<String> channelNames;

  /// Resistance per channel in kOhm.
  ///
  /// Below 500 kOhm indicates good contact; above 1000 kOhm indicates poor
  /// contact.
  final List<double> values;

  /// Number of electrodes / channels.
  final int channelCount;

  factory ResistanceData.fromMap(Map<Object?, Object?> map) {
    return ResistanceData(
      channelNames:
          (map['channelNames'] as List).map((v) => v as String).toList(),
      values:
          (map['values'] as List).map((v) => (v as num).toDouble()).toList(),
      channelCount: map['channelCount'] as int,
    );
  }
}
