package com.neiry.neiry_kit

import android.os.Handler
import io.flutter.plugin.common.EventChannel

/**
 * Kotlin bridge for `clCDeviceLocator_*`. Owns the native locator handle and
 * implements [EventChannel.StreamHandler] for the `deviceList` event stream.
 *
 * Mirrors [DeviceLocatorBridge.swift] in behavior.
 */
class DeviceLocatorBridge(
    private val nativeBridge: NativeBridge,
    private val mainHandler: Handler,
) : EventChannel.StreamHandler {

    private var handle: Long = 0L

    /**
     * The currently active guarded sink. Used to drop stale events that arrive
     * after a new scan has already started.
     *
     * Sequence that causes stale events:
     * 1. Scan A ends — native queues endOfStream via Handler.post(mainHandler, ...)
     * 2. User immediately scans again — onListen registers a new Dart handler
     * 3. Queued endOfStream fires → reaches the NEW handler → controller.close() → "No element"
     *
     * Wrapping each sink lets us null out `currentSink` on every new onListen,
     * so the guarded wrapper rejects the stale event before it reaches Dart.
     */
    @Volatile private var currentSink: EventChannel.EventSink? = null

    companion object {
        /** Device handles keyed by serial. DeviceBridge looks up entries here. */
        var devices: MutableMap<String, Long> = mutableMapOf()
    }

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    /** Creates the native `clCDeviceLocator`. */
    fun create(logDirectory: String?) {
        try {
            handle = nativeBridge.nativeCreateLocator(logDirectory)
        } catch (e: RuntimeException) {
            throw parseSdkError(e.message ?: "255|Unknown error")
        }
    }

    /**
     * Creates a device handle for [serial] and stores it in [devices].
     * Returns the native handle (stored internally; Dart does not need it).
     */
    fun createDevice(serial: String): Long {
        if (handle == 0L) {
            throw FlutterError("NO_LOCATOR", "DeviceLocator not created", null)
        }
        return try {
            val deviceHandle = nativeBridge.nativeCreateDevice(handle, serial)
            devices[serial] = deviceHandle
            deviceHandle
        } catch (e: RuntimeException) {
            throw parseSdkError(e.message ?: "255|Unknown error")
        }
    }

    /** Switches the SDK between multi-threaded and single-threaded mode. */
    fun setSingleThreaded(enabled: Boolean) {
        nativeBridge.nativeSetSingleThreaded(enabled)
    }

    /** Pumps SDK callbacks when in single-threaded mode. */
    fun update() {
        if (handle == 0L) {
            throw FlutterError("NO_LOCATOR", "DeviceLocator not created", null)
        }
        nativeBridge.nativeUpdate(handle)
    }

    /** Sets SDK log verbosity. */
    fun setLogLevel(level: Int) {
        nativeBridge.nativeSetLogLevel(level)
    }

    /** Releases the native locator and clears all device handles. */
    fun dispose() {
        if (handle != 0L) {
            nativeBridge.nativeSetDeviceListSink(null)
            nativeBridge.nativeDestroyLocator(handle)
            handle = 0L
        }
        devices.clear()
    }

    // ── EventChannel.StreamHandler ────────────────────────────────────────────

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        if (handle == 0L) {
            events?.error("NO_LOCATOR", "DeviceLocator not created", null)
            events?.endOfStream()
            return
        }

        val args       = arguments as? Map<*, *>
        val deviceType = args?.get("deviceType") as? Int
        val searchTime = args?.get("searchTime") as? Int

        if (deviceType == null || searchTime == null) {
            events?.error("INVALID_ARGS", "Missing 'deviceType' or 'searchTime'", null)
            events?.endOfStream()
            return
        }

        // Wrap the real sink so stale events from the previous scan are dropped.
        // When a new onListen fires, currentSink is replaced — the old wrapper's
        // identity check fails and any pending Handler.post(endOfStream) is silently ignored.
        val wrappedSink = events?.let { realSink ->
            object : EventChannel.EventSink {
                override fun success(event: Any?) {
                    if (currentSink === this) realSink.success(event)
                }
                override fun error(code: String, message: String?, details: Any?) {
                    if (currentSink === this) realSink.error(code, message, details)
                }
                override fun endOfStream() {
                    if (currentSink === this) realSink.endOfStream()
                }
            }
        }
        currentSink = wrappedSink

        // Register the sink BEFORE starting the scan so the callback always finds it set.
        nativeBridge.nativeSetDeviceListSink(wrappedSink)

        try {
            nativeBridge.nativeRequestDevices(handle, deviceType, searchTime)
        } catch (e: RuntimeException) {
            val err = parseSdkError(e.message ?: "255|Unknown error")
            currentSink = null
            events?.error(err.code, err.message, err.details)
            events?.endOfStream()
            nativeBridge.nativeSetDeviceListSink(null)
        }
    }

    override fun onCancel(arguments: Any?) {
        currentSink = null
        nativeBridge.nativeSetDeviceListSink(null)
    }
}
