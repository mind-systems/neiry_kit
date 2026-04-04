# Plan: Sentinel helper + exceptions

## Context

Add the foundational error-handling and sentinel-conversion utilities that all subsequent Dart model classes depend on: a shared `orNull` helper to convert SDK sentinel values (`-1` / `-1.0`) to Dart `null`, a `NeiryErrorCode` enum mirroring all 17 `clCError_Code` values, and a `NeiryException` class hierarchy for typed error propagation from native bridges.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Sentinel helper

- [x] **Task 1: Create `orNull` sentinel helper**
  Files: `lib/src/models/internal/sentinel.dart`
  Create the `lib/src/models/internal/` directory and add `sentinel.dart` with a single top-level function `double? orNull(Object? v)`. Implementation:
  ```dart
  double? orNull(Object? v) {
    if (v == null) return null;
    final d = (v as num).toDouble();
    return d < 0 ? null : d;
  }
  ```
  Key design decisions: (1) Cast to `num` instead of `double` because Flutter's `StandardMessageCodec` may deliver native integers as Dart `int` (e.g. sentinel `-1` arrives as `int`, not `double`) — casting directly to `double` would throw a `TypeError` at runtime. (2) Assign the cast result to a typed local `d` because Dart's `as` cast does not promote the original variable — returning `v` directly where the return type is `double?` would be a compile error in Dart 3.x with sound null safety. This is the shared codec pattern from ARCHITECTURE.md principle 5: "Sentinel -1 is mapped to null at the Dart boundary". This file is internal — it will be imported by model `fromMap` factories but not re-exported from the barrel.

### Phase 2: Error code enum

- [x] **Task 2: Create `NeiryErrorCode` enum**
  Files: `lib/src/models/neiry_error_code.dart`
  Add an enum `NeiryErrorCode` mirroring `clCError_Code` from `CError.h`. Follow the exact same pattern used in `lib/src/channel/enums.dart` — each value carries a `final int code` field, constructor `const NeiryErrorCode(this.code)`, and a `static NeiryErrorCode fromCode(int code)` factory that iterates `values` and throws `ArgumentError` on unknown codes. Values (17 total):
  - `ok(0)`, `failedToConnect(1)`, `failedToInitConnection(2)`, `failedToInitialize(3)`, `deviceError(4)`, `individualNfbNotCalibrated(5)`, `notReceived(6)`, `nullPointer(7)`, `moduleAlreadyExists(8)`, `moduleIsNotSupported(9)`, `failedToSendData(10)`, `indexOutOfRange(11)`, `emptyCollection(12)`, `notFound(13)`, `sizeMismatch(14)`, `unknownEnum(15)`, `unknown(255)`

### Phase 3: Exception hierarchy

- [x] **Task 3: Create `NeiryException` base class and subclasses**
  Files: `lib/src/models/neiry_exception.dart`
  Create the exception hierarchy. `NeiryException` implements `Exception`, holds `final NeiryErrorCode code` and `final String message`, and overrides `toString()` to return `'NeiryException($code): $message'`. Add three subclasses in the same file:
  - `BluetoothDisabledException extends NeiryException` — constructor passes `NeiryErrorCode.failedToConnect` and a default message.
  - `DeviceNotConnectedException extends NeiryException` — constructor passes `NeiryErrorCode.deviceError` and a default message.
  - `CalibrationRequiredException extends NeiryException` — constructor passes `NeiryErrorCode.individualNfbNotCalibrated` and a default message.
  All subclasses allow an optional custom `message` override. Import `NeiryErrorCode` from Task 2.

### Phase 4: Export from barrel

- [x] **Task 4: Export new files from barrel**
  Files: `lib/neiry_kit.dart`
  Add two export lines to the barrel file: `export 'src/models/neiry_error_code.dart';` and `export 'src/models/neiry_exception.dart';`. Do NOT export `src/models/internal/sentinel.dart` — it is internal to the models layer and not part of the public API surface.
