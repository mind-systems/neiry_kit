import 'package:flutter/foundation.dart';

import 'neiry_error_code.dart';

/// Immutable value carrying the native bridge error payload.
///
/// The native bridge encodes a `clCError` as a map with these three fields;
/// the Dart API layer converts the map to [NeiryError] and raises a
/// [NeiryException] when [success] is `false`.
@immutable
class NeiryError {
  const NeiryError({
    required this.message,
    required this.success,
    required this.code,
  });

  /// Human-readable description of what went wrong (or empty string on success).
  final String message;

  /// `true` when the operation completed without error.
  final bool success;

  /// Typed SDK error code.
  final NeiryErrorCode code;

  factory NeiryError.fromMap(Map<Object?, Object?> map) {
    return NeiryError(
      message: map['message'] as String,
      success: map['success'] as bool,
      code: NeiryErrorCode.fromCode(map['code'] as int),
    );
  }
}
