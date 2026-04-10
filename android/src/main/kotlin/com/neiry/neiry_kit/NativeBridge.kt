package com.neiry.neiry_kit

import android.os.Handler
import io.flutter.plugin.common.EventChannel

/**
 * Holds all JNI `external fun` declarations for the plugin.
 * One instance per plugin attachment — prevents native state from leaking
 * across Flutter hot restarts.
 *
 * Native library loading is performed once in the companion [init] block.
 */
class NativeBridge {

    companion object {
        init {
            System.loadLibrary("CapsuleClient")
            System.loadLibrary("neiry_jni")
        }
    }

    // ── SDK version ──────────────────────────────────────────────────────────

    external fun nativeGetVersion(): String

    // ── Device locator ───────────────────────────────────────────────────────

    external fun nativeCreateLocator(logDir: String?): Long
    external fun nativeDestroyLocator(handle: Long)
    external fun nativeRequestDevices(handle: Long, deviceType: Int, searchTime: Int)
    external fun nativeSetDeviceListSink(sink: EventChannel.EventSink?)
    external fun nativeCreateDevice(locatorHandle: Long, serial: String): Long
    external fun nativeSetSingleThreaded(enabled: Boolean)
    external fun nativeUpdate(handle: Long)
    external fun nativeSetLogLevel(level: Int)

    // ── Device ───────────────────────────────────────────────────────────────

    external fun nativeRegisterDeviceCallbacks(handle: Long)
    external fun nativeUnregisterDeviceCallbacks(handle: Long)
    external fun nativeSetDeviceStreamSink(streamType: Int, sink: EventChannel.EventSink?)

    external fun nativeConnectDevice(handle: Long, bipolarChannels: Boolean)
    external fun nativeDisconnectDevice(handle: Long)
    external fun nativeStartDevice(handle: Long)
    external fun nativeStopDevice(handle: Long)
    external fun nativeReleaseDevice(handle: Long)
    external fun nativeGetBatteryCharge(handle: Long): Int
    external fun nativeGetMode(handle: Long): Int
    external fun nativeGetEEGSampleRate(handle: Long): Float
    external fun nativeGetPPGSampleRate(handle: Long): Float
    external fun nativeGetMEMSSampleRate(handle: Long): Float
    external fun nativeGetPPGIrAmplitude(handle: Long): Int
    external fun nativeGetPPGRedAmplitude(handle: Long): Int
    external fun nativeGetChannelNames(handle: Long): List<String>
    external fun nativeGetChannelsCount(handle: Long): Int
    external fun nativeGetChannelIndexByName(handle: Long, channelName: String): Int
    external fun nativeGetChannelNameByIndex(handle: Long, index: Int): String
    external fun nativeGetRawChannelNamesHandle(handle: Long): Long
    external fun nativeGetChannelsCountFromHandle(namesHandle: Long): Int
    external fun nativeGetChannelNameByIndexFromHandle(namesHandle: Long, index: Int): String
    external fun nativeGetChannelIndexByNameFromHandle(namesHandle: Long, channelName: String): Int

    // ── NFB classifier ────────────────────────────────────────────────────────

    external fun nativeCreateNfb(deviceHandle: Long): Long
    external fun nativeCreateNfbCalibrated(
        deviceHandle: Long,
        hasCalibrationData: Boolean,
        ts: Long,
        failReason: Int,
        individualFrequency: Float,
        individualPeakFrequency: Float,
        individualPeakFrequencyPower: Float,
        individualPeakFrequencySuppression: Float,
        individualBandwidth: Float,
        individualNormalizedPower: Float,
        lowerFrequency: Float,
        upperFrequency: Float,
    ): Long
    external fun nativeSetNfbStateSink(sink: EventChannel.EventSink?)
    external fun nativeSetNfbErrorSink(sink: EventChannel.EventSink?)
    external fun nativeDisposeNfb(nfbHandle: Long)

    // ── NFB calibrator ────────────────────────────────────────────────────────

    external fun nativeStartCalibration(deviceHandle: Long, quick: Boolean)
    external fun nativeStopCalibration()
    external fun nativeImportCalibration(
        deviceHandle: Long,
        ts: Long, failReason: Int,
        individualFrequency: Float, individualPeakFrequency: Float,
        individualPeakFrequencyPower: Float, individualPeakFrequencySuppression: Float,
        individualBandwidth: Float, individualNormalizedPower: Float,
        lowerFrequency: Float, upperFrequency: Float,
    )
    external fun nativeGetCalibration(deviceHandle: Long): Map<String, Any>?
    external fun nativeIsCalibrated(deviceHandle: Long): Boolean
    external fun nativeSetNfbCalibrationSink(sink: EventChannel.EventSink?)

    // ── Emotions classifier ───────────────────────────────────────────────────

    external fun nativeCreateEmotions(deviceHandle: Long): Long
    external fun nativeSetEmotionsStateSink(sink: EventChannel.EventSink?)
    external fun nativeSetEmotionsErrorSink(sink: EventChannel.EventSink?)
    external fun nativeDisposeEmotions(emotionsHandle: Long)

    // ── PhysiologicalStates classifier ───────────────────────────────────────

    external fun nativeCreatePhysio(deviceHandle: Long): Long
    external fun nativeSetPhysioStateSink(sink: EventChannel.EventSink?)
    external fun nativeSetPhysioCalibrationProgressSink(sink: EventChannel.EventSink?)
    external fun nativeSetPhysioCalibratedSink(sink: EventChannel.EventSink?)
    external fun nativeSetPhysioIndividualNfbSink(sink: EventChannel.EventSink?)
    external fun nativeStartBaselineCalibration(physioHandle: Long)
    external fun nativeImportBaselines(physioHandle: Long, ts: Long, alpha: Float, beta: Float, alphaGravity: Float, betaGravity: Float, concentration: Float)
    external fun nativeDisposePhysio(physioHandle: Long)
}

/**
 * Kotlin-side dispatcher invoked from JNI C callbacks via reflection.
 *
 * Posting to [handler] ensures EventChannel sinks are always called on the
 * main thread. Data objects passed as JNI arguments are captured by the
 * Kotlin lambda, making global JNI refs for data unnecessary.
 */
object SinkDispatcher {
    @JvmStatic
    fun postSuccess(handler: Handler, sink: Any?, data: Any?) {
        handler.post { (sink as? EventChannel.EventSink)?.success(data) }
    }

    @JvmStatic
    fun postError(handler: Handler, sink: Any?, code: String, message: String, details: Any?) {
        handler.post {
            (sink as? EventChannel.EventSink)?.error(code, message, details)
            (sink as? EventChannel.EventSink)?.endOfStream()
        }
    }

    @JvmStatic
    fun postEndOfStream(handler: Handler, sink: Any?) {
        handler.post { (sink as? EventChannel.EventSink)?.endOfStream() }
    }
}
