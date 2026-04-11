package com.neiry.neiry_kit

import io.flutter.plugin.common.EventChannel

/**
 * Kotlin bridge for the `clCProductivity` classifier. Owns the native
 * Productivity handle and exposes factory methods (plain and with individual NFB
 * data), calibration commands, and stream handlers for the six event channels:
 * metrics, indexes, baselines, calibration progress, calibrated blob, and
 * individual NFB updates.
 *
 * Mirrors [ProductivityBridge.swift] in behavior.
 */
class ProductivityBridge(private val nativeBridge: NativeBridge) {

    private var handle: Long = 0L

    // ── Stream handlers ───────────────────────────────────────────────────────

    inner class ProductivityStreamHandler(
        private val setSink: (EventChannel.EventSink?) -> Unit
    ) : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            setSink(events)
        }
        override fun onCancel(arguments: Any?) {
            setSink(null)
        }
    }

    val metricsHandler             = ProductivityStreamHandler { nativeBridge.nativeSetProductivityMetricsSink(it) }
    val indexesHandler             = ProductivityStreamHandler { nativeBridge.nativeSetProductivityIndexesSink(it) }
    val baselinesHandler           = ProductivityStreamHandler { nativeBridge.nativeSetProductivityBaselinesSink(it) }
    val calibrationProgressHandler = ProductivityStreamHandler { nativeBridge.nativeSetProductivityCalibrationProgressSink(it) }
    val calibratedHandler          = ProductivityStreamHandler { nativeBridge.nativeSetProductivityCalibratedSink(it) }
    val individualNfbHandler       = ProductivityStreamHandler { nativeBridge.nativeSetProductivityIndividualNfbSink(it) }

    /** Returns all (channelId, handler) pairs for EventChannel registration in the plugin. */
    fun allStreamHandlers(): List<Pair<String, EventChannel.StreamHandler>> = listOf(
        "neiry_kit/events/productivityMetrics"             to metricsHandler,
        "neiry_kit/events/productivityIndexes"             to indexesHandler,
        "neiry_kit/events/productivityBaselines"           to baselinesHandler,
        "neiry_kit/events/productivityCalibrationProgress" to calibrationProgressHandler,
        "neiry_kit/events/productivityCalibrated"          to calibratedHandler,
        "neiry_kit/events/productivityIndividualNfb"       to individualNfbHandler,
    )

    // ── Factory methods ───────────────────────────────────────────────────────

    /** Creates a plain Productivity classifier for the given device handle. */
    fun create(deviceHandle: Long) {
        if (handle != 0L) dispose()
        try {
            handle = nativeBridge.nativeCreateProductivity(deviceHandle)
        } catch (e: RuntimeException) {
            throw parseSdkError(e.message ?: "255|Unknown error")
        }
    }

    /**
     * Creates a Productivity classifier pre-loaded with individual NFB calibration data.
     * All 10 fields must be present in [calibrationData].
     */
    fun createWithIndividualData(deviceHandle: Long, calibrationData: Map<String, Any>) {
        if (handle != 0L) dispose()
        val ts                                 = (calibrationData["ts"] as? Number)?.toLong()                             ?: 0L
        val failReason                         = (calibrationData["failReason"] as? Number)?.toInt()                     ?: 0
        val individualFrequency                = (calibrationData["individualFrequency"] as? Number)?.toFloat()           ?: 0f
        val individualPeakFrequency            = (calibrationData["individualPeakFrequency"] as? Number)?.toFloat()       ?: 0f
        val individualPeakFrequencyPower       = (calibrationData["individualPeakFrequencyPower"] as? Number)?.toFloat()  ?: 0f
        val individualPeakFrequencySuppression = (calibrationData["individualPeakFrequencySuppression"] as? Number)?.toFloat() ?: 0f
        val individualBandwidth                = (calibrationData["individualBandwidth"] as? Number)?.toFloat()           ?: 0f
        val individualNormalizedPower          = (calibrationData["individualNormalizedPower"] as? Number)?.toFloat()     ?: 0f
        val lowerFrequency                     = (calibrationData["lowerFrequency"] as? Number)?.toFloat()                ?: 0f
        val upperFrequency                     = (calibrationData["upperFrequency"] as? Number)?.toFloat()                ?: 0f

        try {
            handle = nativeBridge.nativeCreateProductivityWithIndividualData(
                deviceHandle,
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

    // ── Calibration methods ───────────────────────────────────────────────────

    /** Starts baseline calibration. Throws [FlutterError] if not yet created. */
    fun startBaselineCalibration() {
        if (handle == 0L) throw FlutterError("NOT_CREATED", "ProductivityBridge not created — call create first", null)
        nativeBridge.nativeStartProductivityBaselineCalibration(handle)
    }

    /**
     * Imports previously saved baselines as a raw byte blob.
     *
     * [data] is the opaque in-memory representation of `clCProductivity_Baselines`
     * received from Flutter's standard codec (Dart's `Uint8List` arrives as `byte[]`
     * on Android). The bytes are passed directly to JNI which reinterprets them
     * into the C struct without field unpacking.
     *
     * Throws [FlutterError] if not yet created.
     */
    fun importBaselines(data: ByteArray) {
        if (handle == 0L) throw FlutterError("NOT_CREATED", "ProductivityBridge not created — call create first", null)
        try {
            nativeBridge.nativeImportProductivityBaselines(handle, data)
        } catch (e: RuntimeException) {
            throw parseSdkError(e.message ?: "255|Unknown error")
        }
    }

    /** Resets accumulated fatigue counter. Throws [FlutterError] if not yet created. */
    fun resetAccumulatedFatigue() {
        if (handle == 0L) throw FlutterError("NOT_CREATED", "ProductivityBridge not created — call create first", null)
        try {
            nativeBridge.nativeResetAccumulatedFatigue(handle)
        } catch (e: RuntimeException) {
            throw parseSdkError(e.message ?: "255|Unknown error")
        }
    }

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    /** Unregisters callbacks and clears the Productivity handle. */
    fun dispose() {
        if (handle != 0L) {
            nativeBridge.nativeDisposeProductivity(handle)
            handle = 0L
        }
    }
}
