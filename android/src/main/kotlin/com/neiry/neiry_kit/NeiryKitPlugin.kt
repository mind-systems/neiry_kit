package com.neiry.neiry_kit

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/** NeiryKitPlugin */
class NeiryKitPlugin : FlutterPlugin, MethodCallHandler {

    private var methodChannels: MutableMap<String, MethodChannel> = mutableMapOf()
    private var eventChannels: MutableMap<String, EventChannel> = mutableMapOf()

    private var nativeBridge: NativeBridge? = null
    private var deviceLocatorBridge: DeviceLocatorBridge? = null
    private var deviceBridge: DeviceBridge? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        nativeBridge = NativeBridge()  // triggers System.loadLibrary via companion init
        deviceLocatorBridge = DeviceLocatorBridge(nativeBridge!!, Handler(Looper.getMainLooper()))
        deviceBridge = DeviceBridge(nativeBridge!!)

        val messenger = flutterPluginBinding.binaryMessenger

        // Register all MethodChannels
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

        // Register all EventChannels — deviceList uses the real bridge, others use stub
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
            val handler: EventChannel.StreamHandler = when (id) {
                "neiry_kit/events/deviceList" -> deviceLocatorBridge!!
                else -> StubStreamHandler()
            }
            channel.setStreamHandler(handler)
            eventChannels[id] = channel
        }
    }

    private fun handleMethodCall(call: MethodCall, result: Result, channelId: String) {
        when (channelId) {
            "neiry_kit/device_locator" -> handleDeviceLocatorCall(call, result)
            "neiry_kit/device"         -> handleDeviceCall(call, result)
            "neiry_kit/nfb"            -> handleNfbCall(call, result)
            "neiry_kit/nfb_calibrator" -> handleNfbCalibratorCall(call, result)
            "neiry_kit/emotions"       -> handleEmotionsCall(call, result)
            "neiry_kit/physiological"  -> handlePhysiologicalCall(call, result)
            "neiry_kit/cardio"         -> handleCardioCall(call, result)
            "neiry_kit/productivity"   -> handleProductivityCall(call, result)
            else                       -> result.notImplemented()
        }
    }

    private fun handleDeviceLocatorCall(call: MethodCall, result: Result) {
        val bridge = deviceLocatorBridge
            ?: return result.error("NOT_INITIALIZED", "DeviceLocatorBridge not initialized", null)
        try {
            when (call.method) {
                "getVersionString" -> result.success(nativeBridge!!.nativeGetVersion())

                "create" -> {
                    val logDirectory = (call.arguments as? Map<*, *>)?.get("logDirectory") as? String
                    bridge.create(logDirectory)
                    result.success(null)
                }

                "createDevice" -> {
                    val serial = (call.arguments as? Map<*, *>)?.get("serial") as? String
                        ?: return result.error("INVALID_ARGS", "Missing 'serial'", null)
                    bridge.createDevice(serial)
                    val deviceHandle = DeviceLocatorBridge.devices[serial]
                    if (deviceHandle != null) {
                        deviceBridge?.setDevice(serial, deviceHandle)
                        DeviceLocatorBridge.devices.remove(serial)
                    }
                    result.success(null)
                }

                "setSingleThreaded" -> {
                    val enabled = (call.arguments as? Map<*, *>)?.get("enabled") as? Boolean
                        ?: return result.error("INVALID_ARGS", "Missing 'enabled'", null)
                    bridge.setSingleThreaded(enabled)
                    result.success(null)
                }

                "update" -> {
                    bridge.update()
                    result.success(null)
                }

                "setLogLevel" -> {
                    val level = (call.arguments as? Map<*, *>)?.get("level") as? Int
                        ?: return result.error("INVALID_ARGS", "Missing 'level'", null)
                    bridge.setLogLevel(level)
                    result.success(null)
                }

                "dispose" -> {
                    bridge.dispose()
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        } catch (e: FlutterError) {
            result.error(e.code, e.message, e.details)
        } catch (e: Exception) {
            result.error("UNKNOWN", e.message, null)
        }
    }

    private fun handleDeviceCall(call: MethodCall, result: Result) {
        val bridge = deviceBridge
            ?: return result.error("NOT_INITIALIZED", "DeviceBridge not initialized", null)
        try {
            when (call.method) {
                "connect" -> {
                    val bipolarChannels = (call.arguments as? Map<*, *>)?.get("bipolarChannels") as? Boolean ?: false
                    bridge.connect(bipolarChannels)
                    result.success(null)
                }
                "disconnect" -> {
                    bridge.disconnect()
                    result.success(null)
                }
                "start" -> {
                    bridge.start()
                    result.success(null)
                }
                "stop" -> result.success(bridge.stop())
                "getInfo" -> result.notImplemented()
                "getBatteryCharge" -> result.success(bridge.getBatteryCharge())
                "getMode" -> result.success(bridge.getMode())
                "getEEGSampleRate" -> result.success(bridge.getEEGSampleRate())
                "getPPGSampleRate" -> result.success(bridge.getPPGSampleRate())
                "getMEMSSampleRate" -> result.success(bridge.getMEMSSampleRate())
                "getPPGIrAmplitude" -> result.success(bridge.getPPGIrAmplitude())
                "getPPGRedAmplitude" -> result.success(bridge.getPPGRedAmplitude())
                "getChannelNames" -> result.success(bridge.getChannelNames())
                "getChannelsCount" -> result.success(bridge.getChannelsCount())
                "getChannelIndexByName" -> {
                    val channelName = (call.arguments as? Map<*, *>)?.get("channelName") as? String
                        ?: return result.error("INVALID_ARGS", "Missing 'channelName'", null)
                    result.success(bridge.getChannelIndexByName(channelName))
                }
                "getChannelNameByIndex" -> {
                    val index = (call.arguments as? Map<*, *>)?.get("index") as? Int
                        ?: return result.error("INVALID_ARGS", "Missing 'index'", null)
                    result.success(bridge.getChannelNameByIndex(index))
                }
                else -> result.notImplemented()
            }
        } catch (e: FlutterError) {
            result.error(e.code, e.message, e.details)
        } catch (e: Exception) {
            result.error("UNKNOWN", e.message, null)
        }
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
        deviceLocatorBridge?.dispose()
        deviceBridge?.release()
        deviceLocatorBridge = null
        deviceBridge = null
        nativeBridge = null

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
