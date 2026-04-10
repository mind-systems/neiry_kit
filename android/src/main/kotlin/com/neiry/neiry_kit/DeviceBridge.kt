package com.neiry.neiry_kit

/**
 * Kotlin bridge for `clCDevice_*`. Owns the native device handle and exposes
 * lifecycle commands and getters to the plugin dispatch layer.
 *
 * Mirrors [DeviceBridge.swift] in behavior, including the channel names handle
 * caching strategy to avoid leaking handles on repeated calls (there is no
 * release function for `clCDevice_ChannelNames`).
 */
class DeviceBridge(private val nativeBridge: NativeBridge) {

    /** Native device handle obtained via `clCDeviceLocator_CreateDevice`. */
    private var handle: Long = 0L

    /** Serial number of the currently active device. */
    private var serial: String? = null

    /**
     * Cached `clCDevice_ChannelNames` handle. There is no release function for
     * this type, so we cache it to avoid leaking handles on repeated calls.
     * Reset whenever the active device changes.
     */
    private var channelNamesHandle: Long = 0L

    // ── Handle management ─────────────────────────────────────────────────────

    /**
     * Returns the stored device handle or throws [FlutterError] if no device
     * has been set yet.
     */
    private fun requireHandle(): Long {
        if (handle == 0L) {
            throw FlutterError("NO_DEVICE", "No device handle — call createDevice first", null)
        }
        return handle
    }

    /**
     * Called by [NeiryKitPlugin] after `DeviceLocatorBridge.createDevice()` to
     * hand off the native handle. Releases any existing handle that differs from
     * the incoming one to prevent native handle leaks on repeated createDevice calls.
     */
    fun setDevice(serial: String, handle: Long) {
        val old = this.handle
        if (old != 0L && old != handle) {
            nativeBridge.nativeReleaseDevice(old)
        }
        this.handle = handle
        this.serial = serial
        channelNamesHandle = 0L
    }

    /**
     * Returns the cached `clCDevice_ChannelNames` handle, fetching and caching
     * it on first access. Mirrors iOS's `getOrCacheChannelNamesHandle()`.
     */
    private fun getOrCacheChannelNamesHandle(): Long {
        if (channelNamesHandle != 0L) return channelNamesHandle
        val h = requireHandle()
        return try {
            val namesHandle = nativeBridge.nativeGetRawChannelNamesHandle(h)
            channelNamesHandle = namesHandle
            namesHandle
        } catch (e: RuntimeException) {
            throw parseSdkError(e.message ?: "255|Unknown error")
        }
    }

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    fun connect(bipolarChannels: Boolean) {
        val h = requireHandle()
        try {
            nativeBridge.nativeConnectDevice(h, bipolarChannels)
        } catch (e: RuntimeException) {
            throw parseSdkError(e.message ?: "255|Unknown error")
        }
    }

    fun disconnect() {
        val h = requireHandle()
        try {
            nativeBridge.nativeDisconnectDevice(h)
        } catch (e: RuntimeException) {
            throw parseSdkError(e.message ?: "255|Unknown error")
        }
    }

    fun start() {
        val h = requireHandle()
        try {
            nativeBridge.nativeStartDevice(h)
        } catch (e: RuntimeException) {
            throw parseSdkError(e.message ?: "255|Unknown error")
        }
    }

    fun stop(): Boolean {
        val h = requireHandle()
        try {
            nativeBridge.nativeStopDevice(h)
        } catch (e: RuntimeException) {
            throw parseSdkError(e.message ?: "255|Unknown error")
        }
        return true
    }

    /**
     * Releases the native device handle and clears all cached state.
     * Called by [NeiryKitPlugin] during engine detach — NOT on disconnect.
     */
    fun release() {
        if (handle != 0L) {
            nativeBridge.nativeReleaseDevice(handle)
        }
        handle = 0L
        serial = null
        channelNamesHandle = 0L
    }

    // ── Getters ───────────────────────────────────────────────────────────────

    fun getBatteryCharge(): Int {
        val h = requireHandle()
        return try {
            nativeBridge.nativeGetBatteryCharge(h)
        } catch (e: RuntimeException) {
            throw parseSdkError(e.message ?: "255|Unknown error")
        }
    }

    /**
     * Returns the current device mode, or `-1` if no device handle is set.
     * Never throws — matches iOS behavior where `getMode()` has no guard.
     */
    fun getMode(): Int {
        if (handle == 0L) return -1
        return nativeBridge.nativeGetMode(handle)
    }

    fun getEEGSampleRate(): Float {
        val h = requireHandle()
        return try {
            nativeBridge.nativeGetEEGSampleRate(h)
        } catch (e: RuntimeException) {
            throw parseSdkError(e.message ?: "255|Unknown error")
        }
    }

    fun getPPGSampleRate(): Float {
        val h = requireHandle()
        return try {
            nativeBridge.nativeGetPPGSampleRate(h)
        } catch (e: RuntimeException) {
            throw parseSdkError(e.message ?: "255|Unknown error")
        }
    }

    fun getMEMSSampleRate(): Float {
        val h = requireHandle()
        return try {
            nativeBridge.nativeGetMEMSSampleRate(h)
        } catch (e: RuntimeException) {
            throw parseSdkError(e.message ?: "255|Unknown error")
        }
    }

    fun getPPGIrAmplitude(): Int {
        val h = requireHandle()
        return try {
            nativeBridge.nativeGetPPGIrAmplitude(h)
        } catch (e: RuntimeException) {
            throw parseSdkError(e.message ?: "255|Unknown error")
        }
    }

    fun getPPGRedAmplitude(): Int {
        val h = requireHandle()
        return try {
            nativeBridge.nativeGetPPGRedAmplitude(h)
        } catch (e: RuntimeException) {
            throw parseSdkError(e.message ?: "255|Unknown error")
        }
    }

    // ── Channel name accessors ────────────────────────────────────────────────

    fun getChannelNames(): List<String> {
        val namesHandle = getOrCacheChannelNamesHandle()
        return try {
            val count = nativeBridge.nativeGetChannelsCountFromHandle(namesHandle)
            (0 until count).map { i ->
                nativeBridge.nativeGetChannelNameByIndexFromHandle(namesHandle, i)
            }
        } catch (e: RuntimeException) {
            throw parseSdkError(e.message ?: "255|Unknown error")
        }
    }

    fun getChannelsCount(): Int {
        val namesHandle = getOrCacheChannelNamesHandle()
        return try {
            nativeBridge.nativeGetChannelsCountFromHandle(namesHandle)
        } catch (e: RuntimeException) {
            throw parseSdkError(e.message ?: "255|Unknown error")
        }
    }

    fun getChannelIndexByName(channelName: String): Int {
        val namesHandle = getOrCacheChannelNamesHandle()
        return try {
            nativeBridge.nativeGetChannelIndexByNameFromHandle(namesHandle, channelName)
        } catch (e: RuntimeException) {
            throw parseSdkError(e.message ?: "255|Unknown error")
        }
    }

    fun getChannelNameByIndex(index: Int): String {
        val namesHandle = getOrCacheChannelNamesHandle()
        return try {
            nativeBridge.nativeGetChannelNameByIndexFromHandle(namesHandle, index)
        } catch (e: RuntimeException) {
            throw parseSdkError(e.message ?: "255|Unknown error")
        }
    }
}
