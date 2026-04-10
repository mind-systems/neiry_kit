package com.neiry.neiry_kit

import io.flutter.plugin.common.EventChannel

/**
 * Kotlin bridge for the `clCEmotions` classifier. Owns the native Emotions handle
 * and exposes stream handlers for `emotionsState` and `emotionsError` event channels.
 *
 * Mirrors [EmotionsBridge.swift] in behavior.
 */
class EmotionsBridge(private val nativeBridge: NativeBridge) {

    private var handle: Long = 0L

    // ── Stream handlers ───────────────────────────────────────────────────────

    inner class EmotionsStreamHandler(
        private val setSink: (EventChannel.EventSink?) -> Unit
    ) : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            setSink(events)
        }
        override fun onCancel(arguments: Any?) {
            setSink(null)
        }
    }

    val emotionsStateHandler = EmotionsStreamHandler { nativeBridge.nativeSetEmotionsStateSink(it) }
    val emotionsErrorHandler = EmotionsStreamHandler { nativeBridge.nativeSetEmotionsErrorSink(it) }

    /** Returns all (channelId, handler) pairs for EventChannel registration in the plugin. */
    fun allStreamHandlers(): List<Pair<String, EventChannel.StreamHandler>> = listOf(
        "neiry_kit/events/emotionsState" to emotionsStateHandler,
        "neiry_kit/events/emotionsError" to emotionsErrorHandler,
    )

    // ── Factory method ────────────────────────────────────────────────────────

    /** Creates an Emotions classifier for the given device handle. */
    fun create(deviceHandle: Long) {
        if (handle != 0L) dispose()
        try {
            handle = nativeBridge.nativeCreateEmotions(deviceHandle)
        } catch (e: RuntimeException) {
            throw parseSdkError(e.message ?: "255|Unknown error")
        }
    }

    /** Unregisters callbacks and clears the Emotions handle. */
    fun dispose() {
        if (handle != 0L) {
            nativeBridge.nativeDisposeEmotions(handle)
            handle = 0L
        }
    }
}
