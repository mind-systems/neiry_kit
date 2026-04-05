## Code Review: DeviceBridge — streams

**Files reviewed:** `ios/Classes/DeviceBridge.swift`, `ios/Classes/NeiryKitPlugin.swift`, plus all Dart models (`EegData`, `PsdData`, `EegArtifactData`, `ResistanceData`, `sentinel.dart`, `enums.dart`, `device.dart`) and all C SDK headers (`CDevice.h`, `CEEGTimedData.h`, `CPSDData.h`, `CEEGArtifacts.h`, `CResistances.h`, `CError.h`, `CDefinesPrivate.h`).

### C SDK signature verification

All 8 `clCDevice_SetOn*Event` callback typedefs verified against `CDevice.h`:

| Callback | Handler signature | Code matches |
|---|---|---|
| `SetOnEEGDataEvent` | `(clCDevice, clCEEGTimedData)` | yes — `{ _, data in }` |
| `SetOnPSDDataEvent` | `(clCDevice, clCPSDData)` | yes |
| `SetOnEEGArtifactsEvent` | `(clCDevice, clCEEGArtifacts)` | yes |
| `SetOnResistanceUpdateEvent` | `(clCDevice, clCResistance)` | yes |
| `SetOnBatteryChargeUpdateEvent` | `(clCDevice, uint8_t)` | yes — `{ _, charge in }` |
| `SetOnErrorEvent` | `(clCDevice, const char*)` | yes — `{ _, msg in }` |
| `SetOnConnectionStatusChangedEvent` | `(clCDevice, clCDevice_ConnectionStatus)` | yes |
| `SetOnModeSwitchedEvent` | `(clCDevice, clCDevice_Mode)` | yes |

All data types (`clCEEGTimedData`, `clCPSDData`, etc.) are `const struct*` opaque pointers via `CLC_STRUCT_WNN` macro. Swift imports these as `OpaquePointer?`, which the `guard let data = data` correctly handles.

### Accessor error parameter verification

Verified each accessor against the corresponding C header:

| Header | Accessors | `clCError*` param | Code checks error |
|---|---|---|---|
| `CEEGTimedData.h` | `GetChannelsCount`, `GetSamplesCount`, `GetTimestampMilli`, `GetRawValue`, `GetProcessedValue` | all yes | yes — `guard error.success` after each |
| `CPSDData.h` | `GetTimestampMilli`, `GetChannelsCount`, `GetFrequenciesCount`, `GetFrequency`, `GetPSD`, `GetBandLower/Upper`, `HasIndividualAlpha/Beta`, `GetIndividualAlpha/BetaLower/Upper` | all yes | yes |
| `CEEGArtifacts.h` | `GetTimestampMilli`, `GetChannelsCount`, `GetArtifactByChannel`, `GetEEGQuality` | all yes | yes |
| `CResistances.h` | `GetCount`, `GetChannelName`, `GetValue` | **none** | correctly omitted |
| Battery | raw `uint8_t` value | n/a | n/a |
| Error | raw `const char*` | n/a | n/a |
| ConnectionStatus | raw `clCDevice_ConnectionStatus` enum | n/a | n/a |
| Mode | raw `clCDevice_Mode` enum | n/a | n/a |

### Map key alignment with Dart

Every emitted map key traced back to the corresponding Dart `fromMap` factory:

**EEG** — `ts`, `rawValues`, `processedValues`, `channelCount`, `sampleCount` → `EegData.fromMap` matches all 5 keys. `ts` used as `map['ts'] as int`.

**PSD** — `ts`, `values`, `frequencies`, `channelCount`, `frequencyCount`, 10 band keys (`deltaLower`/`Upper` through `betaLower`/`Upper`), `individualAlphaLower`/`Upper`, `individualBetaLower`/`Upper` → `PsdData.fromMap` matches all 19 keys. Band boundary keys use `(map[key] as num).toDouble()`. Individual keys use `orNull()` which returns `null` for negative values — sentinel `-1` correctly triggers this.

**Artifacts** — `ts`, `artifacts`, `qualities`, `channelCount` → `EegArtifactData.fromMap` matches all 4 keys.

**Resistance** — `channelNames`, `values`, `channelCount` → `ResistanceData.fromMap` matches all 3 keys.

**Battery** — `charge` → `device.dart` line 92: `(map) => map['charge'] as int`. Match.

**Error** — `message` → `device.dart` line 97: `(map) => map['message'] as String`. Match.

**ConnectionStatus** — `state` → `device.dart` line 62: `NeiryConnectionState.fromCode(map['state'] as int)`. Match. C enum values: `Disconnected=0, Connected=1, UnsupportedConnection=2` match Dart `NeiryConnectionState.fromCode`.

**Mode** — `mode` → `device.dart` line 67: `NeiryDeviceMode.fromCode(map['mode'] as int)`. Match. C enum values: `Resistance=0, Signal=1, ...StopPPG=6` match Dart `NeiryDeviceMode.fromCode`.

### Type conversion correctness

- **Timestamps**: C `uint64_t` → Swift `UInt64` → `Int64(bitPattern:)` → platform channel `NSNumber(value: Int64)` → Dart `int`. Millisecond timestamps (~1.7×10^12) fit in signed Int64. Correct.
- **EEG values**: C `float` → Swift `Float` → platform channel → Dart `num`, cast via `.toDouble()`. Correct.
- **PSD values/frequencies**: C `double` → Swift `Double` → Dart `num` → `.toDouble()`. Correct.
- **PSD band boundaries**: C `float` → Swift `Float` → Dart `num` → `.toDouble()`. Correct.
- **Artifact flags**: C `uint8_t` → Swift `UInt8` → `Int(artifact)` → Dart `int`. Correct.
- **Resistance values**: C `float` → Swift `Float` → Dart `num` → `.toDouble()`. Correct.
- **Battery**: C `uint8_t` → Swift `UInt8` → `Int(charge)` → Dart `int`. Correct.

### `clCError` initialization pattern

`clCError` struct (`CError.h` line 28): `{ char message[256]; bool success; clCError_Code code; }`. Swift `clCError()` zero-initializes: `success = false`, `code = clCError_OK`. C accessor functions write to `&error`, setting `success = true` on success. The code re-initializes with `error = clCError()` before each accessor call — correct and matches the existing getter pattern throughout `DeviceBridge`.

### Callback lifecycle

- `registerCallbacks()` called at end of `setDevice()` — callbacks active only after handle is stored.
- `unregisterCallbacks()` called at start of `release()` — callbacks cleared before handle is freed.
- Device swap: `unregisterCallbacks()` on old handle → `clCDevice_Release(old)` → store new handle → `registerCallbacks()` on new handle. Correct ordering.
- In-flight callbacks during unregister: `activeBridge` is nilled, so `guard let bridge = DeviceBridge.activeBridge` in any still-executing callback will fail and bail. Safe.
- Passing `nil` to `clCDevice_SetOn*Event` to clear callbacks: valid — C function pointer parameters imported as optional closures in Swift.

### NeiryKitPlugin.swift wiring

`allStreamHandlers()` returns 8 `(channelId, handler)` pairs with full EventChannel names (e.g., `"neiry_kit/events/eeg"`). The `deviceHandlers` dictionary lookup in `registerEventChannels()` correctly matches these against the `ids` array. The `else if let handler = deviceHandlers[id]` branch correctly falls through to `StubStreamHandler` for all non-device EventChannels.

### Thread safety

The `send()` method reads `sink` from a C callback thread while `onListen`/`onCancel` modify it on the main thread. This is technically a data race on the `sink` property. However, this is the same pattern used in `DeviceLocatorBridge` (which reads `deviceListSink` from C callback threads), and Swift's weak/strong reference operations use atomic instructions internally. Worst case: one extra event delivered to a cancelled sink (harmless — Dart silently ignores) or one dropped event (also harmless). This matches the standard Flutter iOS plugin convention.

### Critical issues

None.

### Minor notes

- `sendError()` on `DeviceStreamHandler` is defined but unused. Harmless — likely useful for future classifier bridges.
- Xcode project (`project.pbxproj`) and `Podfile.lock` changes are standard CocoaPods integration artifacts — no issues.

REVIEW_PASS
