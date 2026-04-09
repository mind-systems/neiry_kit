package com.neiry.neiry_kit

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/** NeiryKitPlugin */
class NeiryKitPlugin : FlutterPlugin, MethodCallHandler {

    companion object {
        init {
            System.loadLibrary("CapsuleClient")  // triggers JNI_OnLoad in SDK
            System.loadLibrary("neiry_jni")
        }
    }

    private var methodChannels: MutableMap<String, MethodChannel> = mutableMapOf()
    private var eventChannels: MutableMap<String, EventChannel> = mutableMapOf()

    private external fun nativeGetVersion(): String

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        val messenger = flutterPluginBinding.binaryMessenger

        // Register all 8 MethodChannels
        val methodChannelIds = listOf(
            "neiry_kit/device_locator",
            "neiry_kit/device",
            "neiry_kit/nfb",
            "neiry_kit/physiological",
            "neiry_kit/emotions",
            "neiry_kit/productivity",
            "neiry_kit/cardio",
            "neiry_kit/nfb_calibrator",
        )
        for (id in methodChannelIds) {
            val channel = MethodChannel(messenger, id)
            channel.setMethodCallHandler { call, result ->
                handleMethodCall(call, result, id)
            }
            methodChannels[id] = channel
        }

        // Register all 29 EventChannels with StubStreamHandler
        val eventChannelIds = listOf(
            "neiry_kit/events/deviceList",
            "neiry_kit/events/eeg",
            "neiry_kit/events/psd",
            "neiry_kit/events/eegArtifacts",
            "neiry_kit/events/resistance",
            "neiry_kit/events/battery",
            "neiry_kit/events/connectionStatus",
            "neiry_kit/events/modeSwitched",
            "neiry_kit/events/nfbState",
            "neiry_kit/events/physiologicalState",
            "neiry_kit/events/emotionsState",
            "neiry_kit/events/productivityMetrics",
            "neiry_kit/events/productivityIndexes",
            "neiry_kit/events/cardioData",
            "neiry_kit/events/ppgData",
            "neiry_kit/events/memsData",
            "neiry_kit/events/nfbCalibration",
            "neiry_kit/events/physiologicalCalibrationProgress",
            "neiry_kit/events/physiologicalCalibrated",
            "neiry_kit/events/physiologicalIndividualNfb",
            "neiry_kit/events/productivityCalibrationProgress",
            "neiry_kit/events/productivityCalibrated",
            "neiry_kit/events/productivityBaselines",
            "neiry_kit/events/productivityIndividualNfb",
            "neiry_kit/events/cardioCalibratedEvent",
            "neiry_kit/events/error",
            "neiry_kit/events/nfbError",
            "neiry_kit/events/emotionsError",
            "neiry_kit/events/productivityError",
        )
        for (id in eventChannelIds) {
            val channel = EventChannel(messenger, id)
            channel.setStreamHandler(StubStreamHandler())
            eventChannels[id] = channel
        }
    }

    private fun handleMethodCall(call: MethodCall, result: Result, channelId: String) {
        if (channelId == "neiry_kit/device_locator") {
            handleDeviceLocatorCall(call, result)
        } else if (channelId == "neiry_kit/device") {
            handleDeviceCall(call, result)
        } else if (channelId == "neiry_kit/nfb") {
            handleNfbCall(call, result)
        } else if (channelId == "neiry_kit/nfb_calibrator") {
            handleNfbCalibratorCall(call, result)
        } else if (channelId == "neiry_kit/emotions") {
            handleEmotionsCall(call, result)
        } else if (channelId == "neiry_kit/physiological") {
            handlePhysiologicalCall(call, result)
        } else if (channelId == "neiry_kit/cardio") {
            handleCardioCall(call, result)
        } else if (channelId == "neiry_kit/productivity") {
            handleProductivityCall(call, result)
        } else {
            result.notImplemented()
        }
    }

    private fun handleDeviceLocatorCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getVersionString" -> result.success(nativeGetVersion())
            else -> result.notImplemented()
        }
    }

    private fun handleDeviceCall(call: MethodCall, result: Result) {
        result.notImplemented()
    }

    private fun handleNfbCall(call: MethodCall, result: Result) {
        result.notImplemented()
    }

    private fun handleNfbCalibratorCall(call: MethodCall, result: Result) {
        result.notImplemented()
    }

    private fun handleEmotionsCall(call: MethodCall, result: Result) {
        result.notImplemented()
    }

    private fun handlePhysiologicalCall(call: MethodCall, result: Result) {
        result.notImplemented()
    }

    private fun handleCardioCall(call: MethodCall, result: Result) {
        result.notImplemented()
    }

    private fun handleProductivityCall(call: MethodCall, result: Result) {
        result.notImplemented()
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        result.notImplemented()
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        for ((_, channel) in methodChannels) {
            channel.setMethodCallHandler(null)
        }
        methodChannels.clear()

        for ((_, channel) in eventChannels) {
            channel.setStreamHandler(null)
        }
        eventChannels.clear()
    }

    // Stub stream handler — no-op onListen/onCancel, mirrors iOS StubStreamHandler
    private inner class StubStreamHandler : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {}
        override fun onCancel(arguments: Any?) {}
    }
}
