package com.neiry.neiry_kit

import io.flutter.plugin.common.EventChannel

/**
 * Kotlin bridge for the `clCPhysiologicalStates` classifier. Owns the native
 * PhysiologicalStates handle and exposes stream handlers for the four event
 * channels: state updates, calibration progress, calibrated baselines, and
 * individual NFB updates.
 *
 * Mirrors [PhysioBridge.swift] in behavior.
 */
class PhysioBridge(private val nativeBridge: NativeBridge) {

    private var handle: Long = 0L

    // ── Stream handlers ───────────────────────────────────────────────────────

    inner class PhysioStreamHandler(
        private val setSink: (EventChannel.EventSink?) -> Unit
    ) : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            setSink(events)
        }
        override fun onCancel(arguments: Any?) {
            setSink(null)
        }
    }

    val physioStateHandler            = PhysioStreamHandler { nativeBridge.nativeSetPhysioStateSink(it) }
    val calibrationProgressHandler    = PhysioStreamHandler { nativeBridge.nativeSetPhysioCalibrationProgressSink(it) }
    val calibratedHandler             = PhysioStreamHandler { nativeBridge.nativeSetPhysioCalibratedSink(it) }
    val individualNfbHandler          = PhysioStreamHandler { nativeBridge.nativeSetPhysioIndividualNfbSink(it) }

    /** Returns all (channelId, handler) pairs for EventChannel registration in the plugin. */
    fun allStreamHandlers(): List<Pair<String, EventChannel.StreamHandler>> = listOf(
        "neiry_kit/events/physiologicalState"               to physioStateHandler,
        "neiry_kit/events/physiologicalCalibrationProgress" to calibrationProgressHandler,
        "neiry_kit/events/physiologicalCalibrated"          to calibratedHandler,
        "neiry_kit/events/physiologicalIndividualNfb"       to individualNfbHandler,
    )

    // ── Factory method ────────────────────────────────────────────────────────

    /** Creates a PhysiologicalStates classifier for the given device handle. */
    fun create(deviceHandle: Long) {
        if (handle != 0L) dispose()
        try {
            handle = nativeBridge.nativeCreatePhysio(deviceHandle)
        } catch (e: RuntimeException) {
            throw parseSdkError(e.message ?: "255|Unknown error")
        }
    }

    // ── Calibration methods ───────────────────────────────────────────────────

    /** Starts baseline calibration. Throws [FlutterError] if not yet created. */
    fun startBaselineCalibration() {
        if (handle == 0L) throw FlutterError("NOT_CREATED", "PhysioBridge not created — call create first", null)
        nativeBridge.nativeStartBaselineCalibration(handle)
    }

    /**
     * Imports previously saved baselines. The map must contain keys:
     * `ts` (Number → Long), `alpha`, `beta`, `alphaGravity`, `betaGravity`,
     * `concentration` (each Number → Float).
     *
     * Throws [FlutterError] if not yet created.
     */
    fun importBaselines(map: Map<String, Any>) {
        if (handle == 0L) throw FlutterError("NOT_CREATED", "PhysioBridge not created — call create first", null)
        val ts            = (map["ts"] as Number).toLong()
        val alpha         = (map["alpha"] as Number).toFloat()
        val beta          = (map["beta"] as Number).toFloat()
        val alphaGravity  = (map["alphaGravity"] as Number).toFloat()
        val betaGravity   = (map["betaGravity"] as Number).toFloat()
        val concentration = (map["concentration"] as Number).toFloat()
        nativeBridge.nativeImportBaselines(handle, ts, alpha, beta, alphaGravity, betaGravity, concentration)
    }

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    /** Unregisters callbacks and clears the PhysiologicalStates handle. */
    fun dispose() {
        if (handle != 0L) {
            nativeBridge.nativeDisposePhysio(handle)
            handle = 0L
        }
    }
}
