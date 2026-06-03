package com.neiry.neiry_kit

import android.os.Handler
import android.util.Log
import io.flutter.plugin.common.EventChannel
import java.util.concurrent.atomic.AtomicBoolean

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
     * The currently active guarded sink. Guards two classes of spurious endOfStream:
     *
     * Class 1 — stale from previous scan:
     * SDK queues endOfStream via Handler.post during scan A; user starts scan B before
     * that fires; queued lambda fires on scan B's Dart handler → "No element".
     * Guard: identity check `currentSink === this` — replaced on each onListen.
     *
     * Class 2 — deferred SDK reset (~54ms after nativeRequestDevices):
     * Native C SDK fires endOfStream on the current scan's sink ~54ms into a new scan,
     * resetting leftover state from the previous scan. No success or error precedes it.
     * Guard: per-sink `eventReceived` flag — only allow endOfStream through if at least
     * one success or error event arrived first. A scan that closes with no data is
     * definitionally a spurious SDK reset.
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

        // eventReceived starts false; only success or error sets it true.
        // endOfStream is only forwarded to Dart if eventReceived is true — a scan
        // that closes with no prior data is a spurious SDK reset and is silently dropped.
        val eventReceived = AtomicBoolean(false)

        val wrappedSink = events?.let { realSink ->
            object : EventChannel.EventSink {
                override fun success(event: Any?) {
                    if (currentSink === this) {
                        eventReceived.set(true)
                        realSink.success(event)
                    }
                }
                override fun error(code: String, message: String?, details: Any?) {
                    if (currentSink === this) {
                        eventReceived.set(true)
                        realSink.error(code, message, details)
                    }
                }
                override fun endOfStream() {
                    val isCurrent = currentSink === this
                    val hasEvent  = eventReceived.get()
                    Log.d("Neiry", "DeviceLocatorBridge.endOfStream isCurrent=$isCurrent hasEvent=$hasEvent")
                    if (isCurrent && hasEvent) realSink.endOfStream()
                }
            }
        }
        currentSink = wrappedSink

        // Register the sink BEFORE starting the scan so the callback always finds it set.
        nativeBridge.nativeSetDeviceListSink(wrappedSink)

        try {
            Log.d("Neiry", "DeviceLocatorBridge.onListen: nativeRequestDevices")
            nativeBridge.nativeRequestDevices(handle, deviceType, searchTime)
        } catch (e: RuntimeException) {
            val err = parseSdkError(e.message ?: "255|Unknown error")
            currentSink = null
            events?.error(err.code, err.message, err.details)
            events?.endOfStream()
            nativeBridge.nativeSetDeviceListSink(null)
            return
        }
    }

    override fun onCancel(arguments: Any?) {
        Log.d("Neiry", "DeviceLocatorBridge.onCancel")
        currentSink = null
        nativeBridge.nativeSetDeviceListSink(null)
    }
}
