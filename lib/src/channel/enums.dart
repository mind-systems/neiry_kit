// Dart enums that mirror the Capsule SDK integer constants.
// Each enum carries an int [code] that maps 1:1 to the C SDK value so
// native bridges can encode/decode with a simple integer on the channel.

// ──────────────────────────────────────────────────────────────────────────────
// Device type
// ──────────────────────────────────────────────────────────────────────────────

/// Mirrors `clCDeviceType`.  [sinWave] and [noise] are simulator types.
enum NeiryDeviceType {
  headband(0),
  buds(1),
  headphones(2),
  impulse(3),
  any(4),
  brainBit(6),
  sinWave(100),
  noise(101);

  const NeiryDeviceType(this.code);

  /// The integer value used by the C SDK for this device type.
  final int code;

  /// Returns the [NeiryDeviceType] whose [code] equals [code].
  ///
  /// Throws [ArgumentError] when [code] does not correspond to any known type.
  static NeiryDeviceType fromCode(int code) {
    for (final v in values) {
      if (v.code == code) return v;
    }
    throw ArgumentError('Unknown NeiryDeviceType code: $code');
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Device mode
// ──────────────────────────────────────────────────────────────────────────────

/// Mirrors `clCDeviceMode` (operating mode of a connected device).
///
/// StartPPG=5 and StopPPG=6 are confirmed by `CDevice.h`.
enum NeiryDeviceMode {
  resistance(0),
  signal(1),
  signalAndResist(2),
  startMEMS(3),
  stopMEMS(4),
  startPPG(5),
  stopPPG(6);

  const NeiryDeviceMode(this.code);

  /// The integer value used by the C SDK for this device mode.
  final int code;

  /// Returns the [NeiryDeviceMode] whose [code] equals [code], or `null` for
  /// unrecognised codes.
  ///
  /// The Android AAR may emit undocumented internal `Device_Status` values
  /// (e.g. `7`) that are not part of the public `clCDevice_Mode` enum (0–6).
  /// These transient codes are silently ignored at this layer — callers receive
  /// `null` and should skip the event rather than treating it as an error.
  static NeiryDeviceMode? fromCode(int code) {
    for (final v in values) {
      if (v.code == code) return v;
    }
    return null;
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Connection state
// ──────────────────────────────────────────────────────────────────────────────

/// Mirrors the connection state reported via `SetOnConnectionStateChangedEvent`.
enum NeiryConnectionState {
  disconnected(0),
  connected(1),
  unsupportedConnection(2);

  const NeiryConnectionState(this.code);

  /// The integer value used by the C SDK for this connection state.
  final int code;

  /// Returns the [NeiryConnectionState] whose [code] equals [code].
  ///
  /// Throws [ArgumentError] when [code] does not correspond to any known state.
  static NeiryConnectionState fromCode(int code) {
    for (final v in values) {
      if (v.code == code) return v;
    }
    throw ArgumentError('Unknown NeiryConnectionState code: $code');
  }
}
