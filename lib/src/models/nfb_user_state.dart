import 'package:flutter/foundation.dart';

import 'internal/sentinel.dart';

/// Per-sample output from the NFB brain-wave classifier.
///
/// Mirrors `clCNFB_UserState`. Each band value is `null` when the SDK has not
/// yet produced a valid reading (sentinel `-1` / `-1.0`).
@immutable
class NfbUserState {
  const NfbUserState({
    required this.timestamp,
    this.delta,
    this.theta,
    this.alpha,
    this.smr,
    this.beta,
  });

  /// When this sample was produced.
  final DateTime timestamp;

  /// Delta band power (0–1 normalized), or `null` if not yet available.
  final double? delta;

  /// Theta band power (0–1 normalized), or `null` if not yet available.
  final double? theta;

  /// Alpha band power (0–1 normalized), or `null` if not yet available.
  final double? alpha;

  /// SMR band power (0–1 normalized), or `null` if not yet available.
  final double? smr;

  /// Beta band power (0–1 normalized), or `null` if not yet available.
  final double? beta;

  factory NfbUserState.fromMap(Map<Object?, Object?> map) {
    return NfbUserState(
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['ts'] as int),
      delta: orNull(map['delta']),
      theta: orNull(map['theta']),
      alpha: orNull(map['alpha']),
      smr: orNull(map['smr']),
      beta: orNull(map['beta']),
    );
  }
}
