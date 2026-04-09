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
        if (handle == 0L) return
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

        // Register the sink BEFORE starting the scan so the callback always finds it set.
        nativeBridge.nativeSetDeviceListSink(events)

        try {
            nativeBridge.nativeRequestDevices(handle, deviceType, searchTime)
        } catch (e: RuntimeException) {
            val err = parseSdkError(e.message ?: "255|Unknown error")
            events?.error(err.code, err.message, err.details)
            events?.endOfStream()
            nativeBridge.nativeSetDeviceListSink(null)
        }
    }

    override fun onCancel(arguments: Any?) {
        nativeBridge.nativeSetDeviceListSink(null)
    }
}
