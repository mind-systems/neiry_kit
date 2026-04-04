import 'neiry_error_code.dart';

/// Base class for all exceptions thrown by the neiry_kit plugin.
///
/// Native `PlatformException`s carrying a `clCError_Code` are caught by the
/// Dart API layer and re-thrown as [NeiryException] subclasses so that
/// callers benefit from typed catch clauses and null-safe error codes.
class NeiryException implements Exception {
  const NeiryException({required this.code, required this.message});

  /// The SDK error code that caused this exception.
  final NeiryErrorCode code;

  /// Human-readable description of what went wrong.
  final String message;

  @override
  String toString() => 'NeiryException($code): $message';
}

// ──────────────────────────────────────────────────────────────────────────────
// Subclasses
// ──────────────────────────────────────────────────────────────────────────────

/// Thrown when the BLE adapter is off or access is denied.
class BluetoothDisabledException extends NeiryException {
  const BluetoothDisabledException({
    super.message = 'Bluetooth is disabled or access is not granted.',
  }) : super(code: NeiryErrorCode.failedToConnect);
}

/// Thrown when a method is called on a device that is not connected.
class DeviceNotConnectedException extends NeiryException {
  const DeviceNotConnectedException({
    super.message = 'No device is connected.',
  }) : super(code: NeiryErrorCode.deviceError);
}

/// Thrown when a classifier requires individual NFB calibration data that has
/// not been produced yet.
class CalibrationRequiredException extends NeiryException {
  const CalibrationRequiredException({
    super.message = 'Individual NFB calibration must be completed before '
        'starting this classifier.',
  }) : super(code: NeiryErrorCode.individualNfbNotCalibrated);
}
