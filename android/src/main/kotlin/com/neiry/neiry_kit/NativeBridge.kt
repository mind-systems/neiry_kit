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
