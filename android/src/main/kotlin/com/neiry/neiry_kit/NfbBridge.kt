package com.neiry.neiry_kit

import io.flutter.plugin.common.EventChannel

/**
 * Kotlin bridge for the `clCNFB` classifier. Owns the native NFB handle and
 * exposes factory methods (plain and calibrated) plus stream handlers for
 * `nfbState` and `nfbError` event channels.
 *
 * Mirrors [NfbBridge.swift] in behavior.
 */
class NfbBridge(private val nativeBridge: NativeBridge) {

    private var handle: Long = 0L

    // ── Stream handlers ───────────────────────────────────────────────────────

    inner class NfbStreamHandler(
        private val setSink: (EventChannel.EventSink?) -> Unit
    ) : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            setSink(events)
        }
        override fun onCancel(arguments: Any?) {
            setSink(null)
        }
    }

    val nfbStateHandler = NfbStreamHandler { nativeBridge.nativeSetNfbStateSink(it) }
    val nfbErrorHandler = NfbStreamHandler { nativeBridge.nativeSetNfbErrorSink(it) }

    /** Returns all (channelId, handler) pairs for EventChannel registration in the plugin. */
    fun allStreamHandlers(): List<Pair<String, EventChannel.StreamHandler>> = listOf(
        "neiry_kit/events/nfbState" to nfbStateHandler,
        "neiry_kit/events/nfbError" to nfbErrorHandler,
    )

    // ── Factory methods ───────────────────────────────────────────────────────

    /** Creates an uncalibrated NFB classifier for the given device handle. */
    fun create(deviceHandle: Long) {
        if (handle != 0L) dispose()
        try {
            handle = nativeBridge.nativeCreateNfb(deviceHandle)
        } catch (e: RuntimeException) {
            throw parseSdkError(e.message ?: "255|Unknown error")
        }
    }

    /**
     * Creates a calibrated NFB classifier for the given device handle.
     * If [calibrationData] is non-null, its fields are imported into the
     * calibrator before creating the classifier.
     */
    fun createCalibrated(deviceHandle: Long, calibrationData: Map<String, Any>?) {
        if (handle != 0L) dispose()
        val hasData = calibrationData != null
        val ts                              = (calibrationData?.get("ts") as? Number)?.toLong()    ?: 0L
        val failReason                      = (calibrationData?.get("failReason") as? Number)?.toInt()  ?: 0
        val individualFrequency             = (calibrationData?.get("individualFrequency") as? Number)?.toFloat()             ?: 0f
        val individualPeakFrequency         = (calibrationData?.get("individualPeakFrequency") as? Number)?.toFloat()         ?: 0f
        val individualPeakFrequencyPower    = (calibrationData?.get("individualPeakFrequencyPower") as? Number)?.toFloat()    ?: 0f
        val individualPeakFrequencySuppression = (calibrationData?.get("individualPeakFrequencySuppression") as? Number)?.toFloat() ?: 0f
        val individualBandwidth             = (calibrationData?.get("individualBandwidth") as? Number)?.toFloat()             ?: 0f
        val individualNormalizedPower       = (calibrationData?.get("individualNormalizedPower") as? Number)?.toFloat()       ?: 0f
        val lowerFrequency                  = (calibrationData?.get("lowerFrequency") as? Number)?.toFloat()                  ?: 0f
        val upperFrequency                  = (calibrationData?.get("upperFrequency") as? Number)?.toFloat()                  ?: 0f

        try {
            handle = nativeBridge.nativeCreateNfbCalibrated(
                deviceHandle,
                hasData,
                ts,
                failReason,
                individualFrequency,
                individualPeakFrequency,
                individualPeakFrequencyPower,
                individualPeakFrequencySuppression,
                individualBandwidth,
                individualNormalizedPower,
                lowerFrequency,
                upperFrequency,
            )
        } catch (e: RuntimeException) {
            throw parseSdkError(e.message ?: "255|Unknown error")
        }
    }

    /** Unregisters callbacks and clears the NFB handle. */
    fun dispose() {
        if (handle != 0L) {
            nativeBridge.nativeDisposeNfb(handle)
            handle = 0L
        }
    }
}
