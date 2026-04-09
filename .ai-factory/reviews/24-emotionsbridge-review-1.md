## Code Review: EmotionsBridge (iOS)

**Plan:** `.ai-factory/plans/24-emotionsbridge.md`
**Changed files:** `ios/Classes/classifiers/EmotionsBridge.swift` (new), `ios/Classes/NeiryKitPlugin.swift` (modified)
**Reference files checked:** `CEmotions.h`, `NfbBridge.swift`, `DeviceBridge.swift` (DeviceStreamHandler), `DeviceLocatorBridge.swift` (checkCError), `channel_names.dart`, `emotions_states.dart`, `emotions_classifier.dart`

### EmotionsBridge.swift

**C API contract — verified against `CEmotions.h`:**

| C function | Takes `clCError*`? | Bridge wraps in `do/catch checkCError`? | Correct? |
|---|---|---|---|
| `clCEmotions_Create` | YES | YES (line 38–39) | OK |
| `clCEmotions_SetOnEmotionalStatesUpdateEvent` | NO | NO | OK |
| `clCEmotions_SetOnErrorEvent` | NO | NO | OK |

No `clCEmotions_Destroy` exists — bridge correctly just nils the handle (line 47). OK.

**Map keys — cross-verified against Dart `EmotionsStates.fromMap()`:**

| Swift map key | Dart `fromMap` key | C struct field | Match? |
|---|---|---|---|
| `"ts"` | `map['ts'] as int` | `timestampMilli` (int64_t) | OK |
| `"attention"` | `orNull(map['attention'])` | `attention` (float) | OK |
| `"relaxation"` | `orNull(map['relaxation'])` | `relaxation` (float) | OK |
| `"cognitiveLoad"` | `orNull(map['cognitiveLoad'])` | `cognitiveLoad` (float) | OK |
| `"cognitiveControl"` | `orNull(map['cognitiveControl'])` | `cognitiveControl` (float) | OK |
| `"selfControl"` | `orNull(map['selfControl'])` | `selfControl` (float) | OK |

All 6 fields present on both sides. No extra, no missing. OK.

**Error event shape:** Bridge sends `["message": message]` (line 74). Dart decodes `map['message'] as String` (`emotions_classifier.dart:78`). OK.

**Channel IDs:**

| Bridge handler channelId | `NeiryEvents` constant | In plugin `ids` list? |
|---|---|---|
| `neiry_kit/events/emotionsState` | `NeiryEvents.emotionsState` | YES (line 472) |
| `neiry_kit/events/emotionsError` | `NeiryEvents.emotionsError` | YES (line 489) |

OK.

**Thread safety:** Both callbacks dispatch via `DeviceStreamHandler.send()` which uses `DispatchQueue.main.async` with captured sink (DeviceBridge.swift:31–34). No direct `sink()` calls from C callback thread. OK.

**Weak reference pattern:** `private static weak var activeBridge` (line 13) — matches NfbBridge. Both callbacks guard on `activeBridge` before accessing handlers. `unregisterCallbacks()` nils `activeBridge` only if still `self` (line 82). OK.

**Null C string in error callback:** `msg.map { String(cString: $0) } ?? ""` (line 73) — safely handles `nil` pointer. Matches NfbBridge pattern. OK.

**Unregister passes `nil` to both `SetOn*Event` functions** (lines 80–81) — disables callbacks. Same pattern as NfbBridge. OK.

### NeiryKitPlugin.swift

**Property + instantiation:** `emotionsBridge` declared (line 14), instantiated (line 28) before `registerEventChannels()` (line 29). OK.

**Method dispatch:** `"neiry_kit/emotions"` routed to `handleEmotionsCall` (lines 64–65). Channel ID already in `registerMethodChannels` ids list (line 41). Previously fell through to `FlutterMethodNotImplemented` — now correctly handled. OK.

**handleEmotionsCall (lines 400–422):**
- Guards both `emotionsBridge` and `deviceBridge`. OK.
- `"create"`: calls `requireDevice()` then `emotionsBridge.create(device:)` in do/catch. Matches NfbBridge dispatch. OK.
- `"dispose"`: calls `emotionsBridge.dispose()`, returns nil. OK.
- `default`: returns `FlutterMethodNotImplemented`. OK.
- Dart `EmotionsClassifier` only invokes `create` and `dispose` — complete coverage. OK.

**Event channel registration (lines 453–459, 502–503):** Builds `emotionsHandlers` dict from `emotionsBridge.allStreamHandlers()`, inserted in lookup chain after `nfbCalibratorHandlers` and before `StubStreamHandler` fallback. Replaces stubs for both emotion channels. OK.

**Dispose cleanup (line 137):** `emotionsBridge?.dispose()` added between `nfbCalibratorBridge?.stopCalibration()` and `nfbBridge?.dispose()`. No ordering dependency (Emotions has no Destroy, no NFB dependency at C API level). OK.

### Critical Issues

None.

### Minor Issues

None.

### Suggestions

None.

REVIEW_PASS
