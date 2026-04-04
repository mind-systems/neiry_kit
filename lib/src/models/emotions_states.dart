import 'package:flutter/foundation.dart';

import 'internal/sentinel.dart';

/// Per-sample output from the emotions classifier.
///
/// Mirrors `clCEmotions_States`. Each field is `null` when the SDK has not
/// yet produced a valid reading (sentinel `-1` / `-1.0`).
@immutable
class EmotionsStates {
  const EmotionsStates({
    required this.timestamp,
    this.attention,
    this.relaxation,
    this.cognitiveLoad,
    this.cognitiveControl,
    this.selfControl,
  });

  /// When this sample was produced.
  final DateTime timestamp;

  /// Attention score (0–1 normalized), or `null` if not yet available.
  final double? attention;

  /// Relaxation score (0–1 normalized), or `null` if not yet available.
  final double? relaxation;

  /// Cognitive load score (0–1 normalized), or `null` if not yet available.
  final double? cognitiveLoad;

  /// Cognitive control score (0–1 normalized), or `null` if not yet available.
  final double? cognitiveControl;

  /// Self-control score (0–1 normalized), or `null` if not yet available.
  final double? selfControl;

  factory EmotionsStates.fromMap(Map<Object?, Object?> map) {
    return EmotionsStates(
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['ts'] as int),
      attention: orNull(map['attention']),
      relaxation: orNull(map['relaxation']),
      cognitiveLoad: orNull(map['cognitiveLoad']),
      cognitiveControl: orNull(map['cognitiveControl']),
      selfControl: orNull(map['selfControl']),
    );
  }
}
