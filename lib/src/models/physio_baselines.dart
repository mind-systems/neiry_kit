import 'package:flutter/foundation.dart';

import 'internal/sentinel.dart';

/// Baseline values from the physiological states classifier.
///
/// Mirrors `clCPhysiologicalStates_Baselines`. Each field is `null` when the
/// SDK has not yet produced a valid reading (sentinel `-1` / `-1.0`), including
/// [timestamp] which uses `-1` as its sentinel value.
@immutable
class PhysiologicalStatesBaselines {
  const PhysiologicalStatesBaselines({
    this.timestamp,
    this.alpha,
    this.beta,
    this.alphaGravity,
    this.betaGravity,
    this.concentration,
  });

  /// When this sample was produced, or `null` if not yet available.
  final DateTime? timestamp;

  /// Alpha baseline, or `null` if not yet available.
  final double? alpha;

  /// Beta baseline, or `null` if not yet available.
  final double? beta;

  /// Alpha gravity baseline, or `null` if not yet available.
  final double? alphaGravity;

  /// Beta gravity baseline, or `null` if not yet available.
  final double? betaGravity;

  /// Concentration baseline, or `null` if not yet available.
  final double? concentration;

  factory PhysiologicalStatesBaselines.fromMap(Map<Object?, Object?> map) {
    final tsRaw = map['ts'];
    DateTime? timestamp;
    if (tsRaw != null) {
      final tsInt = tsRaw as int;
      if (tsInt >= 0) {
        timestamp = DateTime.fromMillisecondsSinceEpoch(tsInt);
      }
    }
    return PhysiologicalStatesBaselines(
      timestamp: timestamp,
      alpha: orNull(map['alpha']),
      beta: orNull(map['beta']),
      alphaGravity: orNull(map['alphaGravity']),
      betaGravity: orNull(map['betaGravity']),
      concentration: orNull(map['concentration']),
    );
  }

  /// Serialises this instance back to a map compatible with the native bridge.
  ///
  /// Null fields are emitted as SDK sentinels: `-1.0` for doubles and `-1` for
  /// [timestamp], so the bridge receives C-compatible sentinel values.
  Map<String, dynamic> toMap() {
    return {
      'ts': timestamp?.millisecondsSinceEpoch ?? -1,
      'alpha': alpha ?? -1.0,
      'beta': beta ?? -1.0,
      'alphaGravity': alphaGravity ?? -1.0,
      'betaGravity': betaGravity ?? -1.0,
      'concentration': concentration ?? -1.0,
    };
  }
}
