// Internal utility — not re-exported from the barrel.
// Import this file in model fromMap factories only.

/// Converts a raw SDK value to [double], returning `null` when the value
/// represents the SDK sentinel (any negative number, typically `-1` / `-1.0`).
///
/// Accepts both [int] and [double] because Flutter's [StandardMessageCodec]
/// may deliver a native integer sentinel (e.g. `-1`) as a Dart [int] rather
/// than a [double] — casting directly to [double] would throw a [TypeError].
double? orNull(Object? v) {
  if (v == null) return null;
  final d = (v as num).toDouble();
  return d < 0 ? null : d;
}
