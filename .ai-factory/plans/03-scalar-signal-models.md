# Plan: Scalar + Signal Models

## Context

Create the five Dart model classes that mirror C SDK structs for device info, error reporting, and classifier output signals. `DeviceInfo` and `NeiryError` are plain value types with no sentinel fields; `NfbUserState`, `PhysiologicalStatesValue`, and `EmotionsStates` use the `orNull` sentinel helper on their float fields.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Scalar models (no sentinels)

- [x] **Task 1: DeviceInfo model**
  Files: `lib/src/models/device_info.dart`
  Create an `@immutable` class `DeviceInfo` with three non-nullable fields: `serial` (`String`), `name` (`String`), `type` (`NeiryDeviceType`). Add a `const` constructor with required named parameters and a `factory DeviceInfo.fromMap(Map<Object?, Object?> map)` that reads keys `'serial'` (as `String`), `'name'` (as `String`), `'type'` (pass `int` to `NeiryDeviceType.fromCode`). Import `NeiryDeviceType` from `../channel/enums.dart`. Follow the same file structure as the existing `neiry_error_code.dart` — `import 'package:flutter/foundation.dart'` for `@immutable`.

- [x] **Task 2: NeiryError model**
  Files: `lib/src/models/neiry_error.dart`
  Create an `@immutable` class `NeiryError` with three non-nullable fields: `message` (`String`), `success` (`bool`), `code` (`NeiryErrorCode`). Add a `const` constructor with required named parameters and a `factory NeiryError.fromMap(Map<Object?, Object?> map)` that reads keys `'message'` (as `String`), `'success'` (as `bool`), `'code'` (pass `int` to `NeiryErrorCode.fromCode`). Import `NeiryErrorCode` from `neiry_error_code.dart`. This model is used by the native bridge to construct `NeiryException` instances — it is not a data stream model.

### Phase 2: Signal models (sentinel → null)

- [x] **Task 3: NfbUserState model**
  Files: `lib/src/models/nfb_user_state.dart`
  Create an `@immutable` class `NfbUserState` mirroring `clCNFB_UserState`. Fields: `timestamp` (`DateTime`, required), `delta` / `theta` / `alpha` / `smr` / `beta` (all `double?`). `const` constructor with required `timestamp` and optional nullable band fields. `factory NfbUserState.fromMap(Map<Object?, Object?> map)`: convert `map['ts']` (int, milliseconds since epoch) to `DateTime` via `DateTime.fromMillisecondsSinceEpoch`, pass each band value through the `orNull` helper imported from `internal/sentinel.dart`. Follow the exact pattern shown in the ARCHITECTURE.md code example.

- [x] **Task 4: PhysiologicalStatesValue model**
  Files: `lib/src/models/physio_states.dart`
  Create an `@immutable` class `PhysiologicalStatesValue` mirroring `clCPhysiologicalStates_Value`. Fields: `timestamp` (`DateTime`, required), `relaxation` / `fatigue` / `none` / `concentration` / `involvement` / `stress` (all `double?`, sentinel-mapped via `orNull`), `nfbArtifacts` / `cardioArtifacts` (both `bool`, required, no sentinel — always valid from SDK). `factory PhysiologicalStatesValue.fromMap(Map<Object?, Object?> map)`: same timestamp pattern as Task 3, `orNull` for the six float fields, direct `as bool` cast for the two boolean fields with keys `'nfbArtifacts'` and `'cardioArtifacts'`.

- [x] **Task 5: EmotionsStates model**
  Files: `lib/src/models/emotions_states.dart`
  Create an `@immutable` class `EmotionsStates` mirroring `clCEmotions_States`. Fields: `timestamp` (`DateTime`, required), `attention` / `relaxation` / `cognitiveLoad` / `cognitiveControl` / `selfControl` (all `double?`, sentinel-mapped via `orNull`). `factory EmotionsStates.fromMap(Map<Object?, Object?> map)`: same timestamp and `orNull` pattern as Tasks 3–4. Map keys: `'ts'`, `'attention'`, `'relaxation'`, `'cognitiveLoad'`, `'cognitiveControl'`, `'selfControl'`.

## Commit Plan
- **Commit 1** (after tasks 1-2): "Add DeviceInfo and NeiryError scalar models"
- **Commit 2** (after tasks 3-5): "Add NfbUserState, PhysiologicalStatesValue, and EmotionsStates signal models"
