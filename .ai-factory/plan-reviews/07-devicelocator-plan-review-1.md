## Plan Review: 07-devicelocator

**Plan:** DeviceLocator Dart API class
**Files Reviewed:** plan + `lib/src/channel/channel_names.dart`, `lib/src/channel/enums.dart`, `lib/src/models/device_info.dart`, `lib/src/models/neiry_exception.dart`, `lib/neiry_kit.dart`, `.ai-factory/notes/03-dart-api-device.md`, `.ai-factory/ARCHITECTURE.md`, `.ai-factory/ROADMAP.md`
**Risk Level:** 🟡 Medium

### Context Gates
- **ARCHITECTURE.md:** WARN — plan aligns with folder structure and dependency rules. One design tension noted below.
- **RULES.md:** not present (WARN — no file).
- **ROADMAP.md:** OK — plan maps directly to the `DeviceLocator` milestone under "Dart API."

### Critical Issues

**1. `_nativeReady` await inside `requestDevices` contradicts its synchronous contract**

The plan says:

> `await _nativeReady` at the top of `requestDevices`, `createDevice`, `setSingleThreaded`, and `update`

But `requestDevices` returns `Stream<List<DeviceInfo>>` — not `Future<Stream<...>>`. A synchronous-return method cannot `await` anything before returning. The plan also says:

> Must use a `StreamController<List<DeviceInfo>>` internally so that `_scanSubscription` is assigned synchronously (before any async gap)

These two requirements are mutually exclusive. Awaiting `_nativeReady` introduces an async gap, which makes synchronous `_scanSubscription` assignment impossible.

**Fix — pick one of two strategies:**

- **Option A (recommended):** Remove `requestDevices` from the `await _nativeReady` list. The `create` MethodChannel call is dispatched to the native platform thread before `receiveBroadcastStream`'s `onListen` message because `send()` calls through the binary messenger are FIFO on the platform thread. This means the native locator handle will exist by the time `onListen` fires. Explicitly document this ordering assumption in a code comment.

- **Option B:** Change `requestDevices` to `Future<Stream<List<DeviceInfo>>>`, await `_nativeReady` inside it, then build the controller + subscription synchronously after the await. This changes the public API signature (roadmap says `Stream`, not `Future<Stream>`), so it may not be acceptable.

**2. Native `create` failure leaves a broken singleton**

The factory constructor sets `_instance` immediately and fires the native `create` call. If the native call fails (e.g., Bluetooth framework unavailable, SDK init error), `_nativeReady` completes with an error. Every subsequent method that `await _nativeReady` will re-throw that error. But the factory keeps returning the same broken instance — the user can't recover without knowing to call `dispose()` first.

**Fix:** Add a recovery path. Either:
- Catch the error in `_nativeReady` and null out `_instance` on failure, so the next `DeviceLocator()` call retries creation.
- Or document that the caller must `dispose()` and re-create on failure.

### Suggestions

**3. `dispose()` needs an explicit return type**

The plan describes `dispose()` calling `invokeMethod` (async) but doesn't specify whether it returns `Future<void>` or `void`. The spec note says `void dispose()`, which means the native destroy is fire-and-forget. This is fine, but should be stated explicitly so the implementer doesn't accidentally make it `Future<void>` and force callers to await it.

Also consider: if `dispose()` is `void` and fire-and-forget, what happens if someone calls `DeviceLocator()` again before the native destroy completes? The new `create` call could race with the old `destroy` call on the native side. If `dispose()` is `Future<void>`, the caller can await it before re-creating. Pick one and state it.

**4. `dispose()` while `_nativeReady` is still pending**

If the user calls `DeviceLocator()` and immediately calls `dispose()`, the native `create` may not have completed yet. The plan sends `destroy` to native, which will be processed after `create` (FIFO ordering), so it should work. But the `_nativeReady` future is still pending — nothing awaits or cancels it. If something else later awaits `_nativeReady` (shouldn't happen after dispose, but defensive code helps), it would succeed even though the locator was destroyed. Consider awaiting `_nativeReady` inside `dispose()` before sending `destroy`, or explicitly completing/cancelling it.

**5. `DeviceLocatorMethods.requestDevices` becomes orphaned**

The existing `DeviceLocatorMethods.requestDevices` constant (line 68 of `channel_names.dart`) is not used by this plan's `requestDevices` implementation, which goes through `EventChannel` instead. The plan doesn't mention this. Either:
- Remove it in Task 1 (the plan currently says to only *add* constants, not remove any).
- Or add a comment explaining it may be used by native bridges as a reference string (if true).

Leaving an unused constant without explanation will confuse the next milestone's implementer.

**6. `EventChannel` instantiation on every call**

The plan creates `EventChannel(NeiryEvents.deviceList)` inside `requestDevices` each time it's called. Unlike the `MethodChannel` (which is stored as a private final field per the plan), the `EventChannel` is not cached. This works — `EventChannel` is lightweight — but is inconsistent with the MethodChannel caching pattern. Consider storing it as a `static const` or private field for consistency.

### Positive Notes

- The cancel-on-overlap pattern with `identical(_scanSubscription, thisSub)` is well-designed — it correctly handles the case where cancelling an old consumer's stream should not kill a newer active scan.
- The decision to route `createDevice` through `NeiryChannels.deviceLocator` (not `NeiryChannels.device`) correctly mirrors the C API's requirement that the locator handle is needed.
- Keeping `DeviceMethods.createDevice` in place for future Device milestone is pragmatic.
- The StreamController approach (vs. returning `receiveBroadcastStream` directly) enables proper lifecycle management of scan subscriptions.
- The `_checkNotDisposed()` guard on every public method is the right safety pattern.
- The plan correctly identifies that `update()` is a no-op in multi-threaded mode and avoids over-engineering enforcement in Dart.
