import 'package:flutter/foundation.dart';

import 'internal/sentinel.dart';

/// Per-sample output from the physiological states classifier.
///
/// Mirrors `clCPhysiologicalStates_Value`. Float fields are `null` when the SDK
/// has not yet produced a valid reading (sentinel `-1` / `-1.0`). Boolean
/// artifact flags are always valid once received.
@immutable
class PhysiologicalStatesValue {
  const PhysiologicalStatesValue({
    required this.timestamp,
    required this.nfbArtifacts,
    required this.cardioArtifacts,
    this.relaxation,
    this.fatigue,
    this.none,
    this.concentration,
    this.involvement,
    this.stress,
  });

  /// When this sample was produced.
  final DateTime timestamp;

  /// Relaxation score (0–1 normalized), or `null` if not yet available.
  final double? relaxation;

  /// Fatigue score (0–1 normalized), or `null` if not yet available.
  final double? fatigue;

  /// None/baseline state score (0–1 normalized), or `null` if not yet available.
  final double? none;

  /// Concentration score (0–1 normalized), or `null` if not yet available.
  final double? concentration;

  /// Involvement score (0–1 normalized), or `null` if not yet available.
  final double? involvement;

  /// Stress score (0–1 normalized), or `null` if not yet available.
  final double? stress;

  /// `true` when EEG artifacts were detected during this sample window.
  final bool nfbArtifacts;

  /// `true` when cardio artifacts were detected during this sample window.
  final bool cardioArtifacts;

  factory PhysiologicalStatesValue.fromMap(Map<Object?, Object?> map) {
    return PhysiologicalStatesValue(
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['ts'] as int),
      relaxation: orNull(map['relaxation']),
      fatigue: orNull(map['fatigue']),
      none: orNull(map['none']),
      concentration: orNull(map['concentration']),
      involvement: orNull(map['involvement']),
      stress: orNull(map['stress']),
      nfbArtifacts: map['nfbArtifacts'] as bool,
      cardioArtifacts: map['cardioArtifacts'] as bool,
    );
  }
}
