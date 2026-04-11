package com.neiry.neiry_kit

import io.flutter.plugin.common.EventChannel

/**
 * Kotlin bridge for the `clCCardio` classifier. Owns the native Cardio handle
 * and exposes factory methods (plain and calibrated) plus stream handlers for
 * the three event channels: cardioState, cardioPpg, and cardioCalibratedEvent.
 *
 * Mirrors [CardioBridge.swift] in behavior.
 */
class CardioBridge(private val nativeBridge: NativeBridge) {

    private var handle: Long = 0L

    // ── Stream handlers ───────────────────────────────────────────────────────

    inner class CardioStreamHandler(
        private val setSink: (EventChannel.EventSink?) -> Unit
    ) : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            setSink(events)
        }
        override fun onCancel(arguments: Any?) {
            setSink(null)
        }
    }

    val cardioStateHandler      = CardioStreamHandler { nativeBridge.nativeSetCardioStateSink(it) }
    val cardioPpgHandler        = CardioStreamHandler { nativeBridge.nativeSetCardioPpgSink(it) }
    val cardioCalibratedHandler = CardioStreamHandler { nativeBridge.nativeSetCardioCalibratedSink(it) }

    /** Returns all (channelId, handler) pairs for EventChannel registration in the plugin. */
    fun allStreamHandlers(): List<Pair<String, EventChannel.StreamHandler>> = listOf(
        "neiry_kit/events/cardioData"           to cardioStateHandler,
        "neiry_kit/events/ppgData"              to cardioPpgHandler,
        "neiry_kit/events/cardioCalibratedEvent" to cardioCalibratedHandler,
    )

    // ── Factory methods ───────────────────────────────────────────────────────

    /** Creates an uncalibrated Cardio classifier for the given device handle. */
    fun create(deviceHandle: Long) {
        if (handle != 0L) dispose()
        try {
            handle = nativeBridge.nativeCreateCardio(deviceHandle)
        } catch (e: RuntimeException) {
            throw parseSdkError(e.message ?: "255|Unknown error")
        }
    }

    /**
     * Creates a calibrated Cardio classifier for the given device handle.
     * If [calibrationData] is non-null, its fields are imported into the
     * calibrator before creating the classifier.
     */
    fun createCalibrated(deviceHandle: Long, calibrationData: Map<String, Any>?) {
        if (handle != 0L) dispose()
        val hasData = calibrationData != null
        val ts                                 = (calibrationData?.get("ts") as? Number)?.toLong()    ?: 0L
        val failReason                         = (calibrationData?.get("failReason") as? Number)?.toInt()  ?: 0
        val individualFrequency                = (calibrationData?.get("individualFrequency") as? Number)?.toFloat()             ?: 0f
        val individualPeakFrequency            = (calibrationData?.get("individualPeakFrequency") as? Number)?.toFloat()         ?: 0f
        val individualPeakFrequencyPower       = (calibrationData?.get("individualPeakFrequencyPower") as? Number)?.toFloat()    ?: 0f
        val individualPeakFrequencySuppression = (calibrationData?.get("individualPeakFrequencySuppression") as? Number)?.toFloat() ?: 0f
        val individualBandwidth                = (calibrationData?.get("individualBandwidth") as? Number)?.toFloat()             ?: 0f
        val individualNormalizedPower          = (calibrationData?.get("individualNormalizedPower") as? Number)?.toFloat()       ?: 0f
        val lowerFrequency                     = (calibrationData?.get("lowerFrequency") as? Number)?.toFloat()                  ?: 0f
        val upperFrequency                     = (calibrationData?.get("upperFrequency") as? Number)?.toFloat()                  ?: 0f

        try {
            handle = nativeBridge.nativeCreateCardioCalibrated(
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

    /** Unregisters callbacks and clears the Cardio handle. */
    fun dispose() {
        if (handle != 0L) {
            nativeBridge.nativeDisposeCardio(handle)
            handle = 0L
        }
    }
}
