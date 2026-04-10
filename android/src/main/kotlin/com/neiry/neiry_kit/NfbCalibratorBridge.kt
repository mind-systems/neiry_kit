package com.neiry.neiry_kit

import io.flutter.plugin.common.EventChannel

/**
 * Kotlin bridge for the `clCNFBCalibrator` calibration pipeline. Supports
 * 4-stage and quick calibration modes, import/export of calibration data,
 * and state queries.
 *
 * Mirrors [NfbCalibratorBridge.swift] in behavior.
 */
class NfbCalibratorBridge(private val nativeBridge: NativeBridge) {

    // ── Stream handlers ───────────────────────────────────────────────────────

    inner class CalibrationStreamHandler(
        private val setSink: (EventChannel.EventSink?) -> Unit
    ) : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            setSink(events)
        }
        override fun onCancel(arguments: Any?) {
            setSink(null)
        }
    }

    val calibrationHandler = CalibrationStreamHandler { nativeBridge.nativeSetNfbCalibrationSink(it) }

    /** Returns all (channelId, handler) pairs for EventChannel registration in the plugin. */
    fun allStreamHandlers(): List<Pair<String, EventChannel.StreamHandler>> = listOf(
        "neiry_kit/events/nfbCalibration" to calibrationHandler,
    )

    // ── Methods ───────────────────────────────────────────────────────────────

    /** Starts calibration in 4-stage or quick mode. */
    fun startCalibration(deviceHandle: Long, quick: Boolean) {
        try {
            nativeBridge.nativeStartCalibration(deviceHandle, quick)
        } catch (e: RuntimeException) {
            throw parseSdkError(e.message ?: "255|Unknown error")
        }
    }

    /** Stops calibration and unregisters callbacks. */
    fun stopCalibration() {
        nativeBridge.nativeStopCalibration()
    }

    /** Imports externally stored calibration data into the calibrator. */
    fun importCalibration(deviceHandle: Long, data: Map<String, Any>) {
        val ts                              = (data["ts"] as? Number)?.toLong()    ?: 0L
        val failReason                      = (data["failReason"] as? Number)?.toInt()  ?: 0
        val individualFrequency             = (data["individualFrequency"] as? Number)?.toFloat()             ?: 0f
        val individualPeakFrequency         = (data["individualPeakFrequency"] as? Number)?.toFloat()         ?: 0f
        val individualPeakFrequencyPower    = (data["individualPeakFrequencyPower"] as? Number)?.toFloat()    ?: 0f
        val individualPeakFrequencySuppression = (data["individualPeakFrequencySuppression"] as? Number)?.toFloat() ?: 0f
        val individualBandwidth             = (data["individualBandwidth"] as? Number)?.toFloat()             ?: 0f
        val individualNormalizedPower       = (data["individualNormalizedPower"] as? Number)?.toFloat()       ?: 0f
        val lowerFrequency                  = (data["lowerFrequency"] as? Number)?.toFloat()                  ?: 0f
        val upperFrequency                  = (data["upperFrequency"] as? Number)?.toFloat()                  ?: 0f

        try {
            nativeBridge.nativeImportCalibration(
                deviceHandle,
                ts, failReason,
                individualFrequency, individualPeakFrequency,
                individualPeakFrequencyPower, individualPeakFrequencySuppression,
                individualBandwidth, individualNormalizedPower,
                lowerFrequency, upperFrequency,
            )
        } catch (e: RuntimeException) {
            throw parseSdkError(e.message ?: "255|Unknown error")
        }
    }

    /** Returns the current calibration data map, or null if not calibrated. */
    fun getCalibration(deviceHandle: Long): Map<String, Any>? {
        return try {
            nativeBridge.nativeGetCalibration(deviceHandle)
        } catch (e: RuntimeException) {
            throw parseSdkError(e.message ?: "255|Unknown error")
        }
    }

    /** Returns true if the calibrator has valid calibration data. */
    fun isCalibrated(deviceHandle: Long): Boolean {
        return nativeBridge.nativeIsCalibrated(deviceHandle)
    }

    /** Stops calibration and releases resources. */
    fun dispose() {
        stopCalibration()
    }
}
