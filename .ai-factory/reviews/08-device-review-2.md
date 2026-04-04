## Code Review: 08-device (iteration 2)

**Plan:** Device Dart API — lifecycle, streams, query getters
**Files Reviewed:** `lib/src/api/device.dart`, `lib/src/api/device_locator.dart`, `lib/src/models/eeg_data.dart`, `lib/src/models/psd_data.dart`, `lib/src/models/eeg_artifact_data.dart`, `lib/src/models/resistance_data.dart`, `lib/src/channel/channel_names.dart`, `lib/neiry_kit.dart`, `test/channel_names_test.dart`
**Tests:** 118 passing, `flutter analyze` clean

### Review-1 fixes — verification

1. **Leaked subscriptions on double-connect (critical):** Fixed. `connect()` now throws `StateError('Device is already connected')` at `device.dart:155` when `_connected` is already `true`. This prevents `_startStateTracking()` from being called twice without an intervening `_stopStateTracking()`.

2. **Double-dispose guard (suggestion):** Fixed. `dispose()` at `device.dart:207-208` now returns early with `if (_disposed) return;` before setting `_disposed = true`. Idempotent approach — no redundant native calls on repeated dispose.

### Critical Issues

None.

### Full verification

**Models** — All four follow existing conventions (`@immutable`, `const` constructor, `factory fromMap`). `PsdData` correctly uses `orNull` for individual bounds. `ResistanceData.values` documents kOhm unit with threshold guidance. Sample rate getters use `(result! as num).toDouble()` to handle `StandardMessageCodec` int/double ambiguity.

**Device class** — State machine guards enforced: `_checkNotDisposed()` on all public methods, `_checkConnected()` on `start()` and all async getters, double-connect guard on `connect()`, early-return on double-dispose. `_eventStream<T>` helper + `late final` caching ensures `receiveBroadcastStream` called at most once per stream. Internal `_startStateTracking()` correctly handles hardware-initiated disconnects. All 10 async getters and 6 sync getters present per plan, including `getChannelName(int)` and `getChannelsCount()`.

**DeviceLocator integration** — `createDevice()` return type changed to `Future<Device>`, returns `Device(serial: serial)` after native handle creation. Import added correctly.

**Barrel exports** — 5 new exports in alphabetical order. No missing or extra exports.

**Channel contract** — `NeiryArgs.bipolarChannels` added to `channel_names.dart:137` and covered by uniqueness test at `test/channel_names_test.dart:208`.

**Multi-device limitation** — Documented in class-level doc comment at `device.dart:17-23`.

REVIEW_PASS
