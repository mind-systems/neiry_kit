// Mirrors `clCError_Code` from `CError.h`.
// Each value carries the integer code sent by the native bridge so that
// [NeiryException] can reconstruct the error type without string matching.

/// All error codes returned by the Capsule C SDK (`clCError_Code`).
enum NeiryErrorCode {
  ok(0),
  failedToConnect(1),
  failedToInitConnection(2),
  failedToInitialize(3),
  deviceError(4),
  individualNfbNotCalibrated(5),
  notReceived(6),
  nullPointer(7),
  moduleAlreadyExists(8),
  moduleIsNotSupported(9),
  failedToSendData(10),
  indexOutOfRange(11),
  emptyCollection(12),
  notFound(13),
  sizeMismatch(14),
  unknownEnum(15),
  unknown(255);

  const NeiryErrorCode(this.code);

  /// The integer value used by the C SDK for this error code.
  final int code;

  /// Returns the [NeiryErrorCode] whose [code] equals [code].
  ///
  /// Throws [ArgumentError] when [code] does not correspond to any known value.
  static NeiryErrorCode fromCode(int code) {
    for (final v in values) {
      if (v.code == code) return v;
    }
    throw ArgumentError('Unknown NeiryErrorCode code: $code');
  }
}
