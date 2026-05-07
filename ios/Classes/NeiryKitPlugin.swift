import Flutter
import UIKit

public class NeiryKitPlugin: NSObject, FlutterPlugin {
    private static var instance: NeiryKitPlugin?

    private let registrar: FlutterPluginRegistrar
    private var methodChannels: [String: FlutterMethodChannel] = [:]
    private var eventChannels: [String: FlutterEventChannel] = [:]
    private var deviceLocatorBridge: DeviceLocatorBridge?
    private var deviceBridge: DeviceBridge?
    private var nfbBridge: NfbBridge?
    private var nfbCalibratorBridge: NfbCalibratorBridge?
    private var emotionsBridge: EmotionsBridge?
    private var physioBridge: PhysioBridge?
    private var cardioBridge: CardioBridge?
    private var productivityBridge: ProductivityBridge?

    private init(registrar: FlutterPluginRegistrar) {
        self.registrar = registrar
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = NeiryKitPlugin(registrar: registrar)
        self.instance = instance
        instance.registerMethodChannels()
        instance.deviceLocatorBridge = DeviceLocatorBridge()
        instance.deviceBridge = DeviceBridge()
        instance.nfbBridge = NfbBridge()
        instance.nfbCalibratorBridge = NfbCalibratorBridge()
        instance.emotionsBridge = EmotionsBridge()
        instance.physioBridge = PhysioBridge()
        instance.cardioBridge = CardioBridge()
        instance.productivityBridge = ProductivityBridge()
        instance.registerEventChannels()
    }

    // MARK: - MethodChannel registration

    private func registerMethodChannels() {
        let messenger = registrar.messenger()
        let ids: [String] = [
            "neiry_kit/device_locator",
            "neiry_kit/device",
            "neiry_kit/nfb",
            "neiry_kit/physiological",
            "neiry_kit/emotions",
            "neiry_kit/productivity",
            "neiry_kit/cardio",
            "neiry_kit/nfb_calibrator",
        ]
        for id in ids {
            let channel = FlutterMethodChannel(name: id, binaryMessenger: messenger)
            methodChannels[id] = channel
            channel.setMethodCallHandler { [weak self] call, result in
                self?.handleMethodCall(call, result: result, channelId: id)
            }
        }
    }

    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult, channelId: String) {
        if channelId == "neiry_kit/device_locator" {
            handleDeviceLocatorCall(call, result: result)
        } else if channelId == "neiry_kit/device" {
            handleDeviceCall(call, result: result)
        } else if channelId == "neiry_kit/nfb" {
            handleNfbCall(call, result: result)
        } else if channelId == "neiry_kit/nfb_calibrator" {
            handleNfbCalibratorCall(call, result: result)
        } else if channelId == "neiry_kit/emotions" {
            handleEmotionsCall(call, result: result)
        } else if channelId == "neiry_kit/physiological" {
            handlePhysiologicalCall(call, result: result)
        } else if channelId == "neiry_kit/cardio" {
            handleCardioCall(call, result: result)
        } else if channelId == "neiry_kit/productivity" {
            handleProductivityCall(call, result: result)
        } else {
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - device_locator dispatch

    private func handleDeviceLocatorCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let bridge = deviceLocatorBridge else {
            result(FlutterError(code: "NOT_INITIALIZED", message: "DeviceLocatorBridge not initialized", details: nil))
            return
        }
        switch call.method {
        case "getVersionString":
            let version = String(cString: clCCapsule_GetVersionString())
            result(version)
        case "create":
            let logDirectory = (call.arguments as? [String: Any])?["logDirectory"] as? String
            do {
                try bridge.create(logDirectory: logDirectory)
                result(nil)
            } catch let e as FlutterError {
                result(e)
            } catch {
                result(FlutterError(code: "UNKNOWN", message: "\(error)", details: nil))
            }
        case "createDevice":
            guard let args = call.arguments as? [String: Any],
                  let serial = args["serial"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing 'serial'", details: nil))
                return
            }
            do {
                let ret = try bridge.createDevice(serial: serial)
                if let handle = DeviceLocatorBridge.devices[serial] {
                    deviceBridge?.setDevice(serial: serial, handle: handle)
                    DeviceLocatorBridge.devices.removeValue(forKey: serial)
                }
                result(ret)
            } catch let e as FlutterError {
                result(e)
            } catch {
                result(FlutterError(code: "UNKNOWN", message: "\(error)", details: nil))
            }
        case "setSingleThreaded":
            guard let args = call.arguments as? [String: Any],
                  let enabled = args["enabled"] as? Bool else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing 'enabled'", details: nil))
                return
            }
            bridge.setSingleThreaded(enabled: enabled)
            result(nil)
        case "update":
            do {
                try bridge.update()
                result(nil)
            } catch let e as FlutterError {
                result(e)
            } catch {
                result(FlutterError(code: "UNKNOWN", message: "\(error)", details: nil))
            }
        case "setLogLevel":
            guard let args = call.arguments as? [String: Any],
                  let level = args["level"] as? Int else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing 'level'", details: nil))
                return
            }
            bridge.setLogLevel(level: level)
            result(nil)
        case "dispose":
            nfbCalibratorBridge?.stopCalibration()
            cardioBridge?.dispose()
            productivityBridge?.dispose()
            emotionsBridge?.dispose()
            physioBridge?.dispose()
            nfbBridge?.dispose()
            bridge.dispose()
            deviceBridge?.release()
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - device dispatch

    private func handleDeviceCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let bridge = deviceBridge else {
            result(FlutterError(code: "NOT_INITIALIZED", message: "DeviceBridge not initialized", details: nil))
            return
        }
        switch call.method {
        case "connect":
            do {
                try bridge.connect(call)
                result(nil)
            } catch let e as FlutterError {
                result(e)
            } catch {
                result(FlutterError(code: "UNKNOWN", message: "\(error)", details: nil))
            }
        case "disconnect":
            do {
                try bridge.disconnect()
                result(nil)
            } catch let e as FlutterError {
                result(e)
            } catch {
                result(FlutterError(code: "UNKNOWN", message: "\(error)", details: nil))
            }
        case "start":
            do {
                try bridge.start()
                result(nil)
            } catch let e as FlutterError {
                result(e)
            } catch {
                result(FlutterError(code: "UNKNOWN", message: "\(error)", details: nil))
            }
        case "stop":
            do {
                let ret = try bridge.stop()
                result(ret)
            } catch let e as FlutterError {
                result(e)
            } catch {
                result(FlutterError(code: "UNKNOWN", message: "\(error)", details: nil))
            }
        case "getInfo":
            do {
                let info = try bridge.getInfo()
                result(info)
            } catch let e as FlutterError {
                result(e)
            } catch {
                result(FlutterError(code: "UNKNOWN", message: "\(error)", details: nil))
            }
        case "getBatteryCharge":
            do {
                let charge = try bridge.getBatteryCharge()
                result(charge)
            } catch let e as FlutterError {
                result(e)
            } catch {
                result(FlutterError(code: "UNKNOWN", message: "\(error)", details: nil))
            }
        case "getMode":
            result(bridge.getMode())
        case "getEEGSampleRate":
            do {
                let rate = try bridge.getEEGSampleRate()
                result(rate)
            } catch let e as FlutterError {
                result(e)
            } catch {
                result(FlutterError(code: "UNKNOWN", message: "\(error)", details: nil))
            }
        case "getPPGSampleRate":
            do {
                let rate = try bridge.getPPGSampleRate()
                result(rate)
            } catch let e as FlutterError {
                result(e)
            } catch {
                result(FlutterError(code: "UNKNOWN", message: "\(error)", details: nil))
            }
        case "getMEMSSampleRate":
            do {
                let rate = try bridge.getMEMSSampleRate()
                result(rate)
            } catch let e as FlutterError {
                result(e)
            } catch {
                result(FlutterError(code: "UNKNOWN", message: "\(error)", details: nil))
            }
        case "getPPGIrAmplitude":
            do {
                let amplitude = try bridge.getPPGIrAmplitude()
                result(amplitude)
            } catch let e as FlutterError {
                result(e)
            } catch {
                result(FlutterError(code: "UNKNOWN", message: "\(error)", details: nil))
            }
        case "getPPGRedAmplitude":
            do {
                let amplitude = try bridge.getPPGRedAmplitude()
                result(amplitude)
            } catch let e as FlutterError {
                result(e)
            } catch {
                result(FlutterError(code: "UNKNOWN", message: "\(error)", details: nil))
            }
        case "getChannelNames":
            do {
                let names = try bridge.getChannelNames()
                result(names)
            } catch let e as FlutterError {
                result(e)
            } catch {
                result(FlutterError(code: "UNKNOWN", message: "\(error)", details: nil))
            }
        case "getChannelsCount":
            do {
                let count = try bridge.getChannelsCount()
                result(count)
            } catch let e as FlutterError {
                result(e)
            } catch {
                result(FlutterError(code: "UNKNOWN", message: "\(error)", details: nil))
            }
        case "getChannelIndexByName":
            do {
                let index = try bridge.getChannelIndexByName(call)
                result(index)
            } catch let e as FlutterError {
                result(e)
            } catch {
                result(FlutterError(code: "UNKNOWN", message: "\(error)", details: nil))
            }
        case "getChannelNameByIndex":
            do {
                let name = try bridge.getChannelNameByIndex(call)
                result(name)
            } catch let e as FlutterError {
                result(e)
            } catch {
                result(FlutterError(code: "UNKNOWN", message: "\(error)", details: nil))
            }
        case "getFirmwareVersion":
            do {
                let version = try bridge.getFirmwareVersion()
                result(version)
            } catch let e as FlutterError {
                result(e)
            } catch {
                result(FlutterError(code: "UNKNOWN", message: "\(error)", details: nil))
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - nfb dispatch

    private func handleNfbCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let nfbBridge = nfbBridge, let deviceBridge = deviceBridge else {
            result(FlutterError(code: "NOT_INITIALIZED", message: "NfbBridge or DeviceBridge not initialized", details: nil))
            return
        }
        switch call.method {
        case "create":
            do {
                let dev = try deviceBridge.requireDevice()
                try nfbBridge.create(device: dev)
                result(nil)
            } catch let e as FlutterError {
                result(e)
            } catch {
                result(FlutterError(code: "UNKNOWN", message: "\(error)", details: nil))
            }
        case "createCalibrated":
            let args = call.arguments as? [String: Any]
            let calibrationData = args?["calibrationData"] as? [String: Any]
            do {
                let dev = try deviceBridge.requireDevice()
                try nfbBridge.createCalibrated(device: dev, calibrationData: calibrationData)
                result(nil)
            } catch let e as FlutterError {
                result(e)
            } catch {
                result(FlutterError(code: "UNKNOWN", message: "\(error)", details: nil))
            }
        case "dispose":
            nfbBridge.dispose()
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - nfb_calibrator dispatch

    private func handleNfbCalibratorCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let nfbCalibratorBridge = nfbCalibratorBridge, let deviceBridge = deviceBridge else {
            result(FlutterError(code: "NOT_INITIALIZED",
                                message: "NfbCalibratorBridge or DeviceBridge not initialized",
                                details: nil))
            return
        }
        switch call.method {
        case "startCalibration":
            let args = call.arguments as? [String: Any]
            let quick = (args?["calibratorData"] as? String) == "quick"
            do {
                let dev = try deviceBridge.requireDevice()
                try nfbCalibratorBridge.startCalibration(device: dev, quick: quick, result: result)
            } catch let e as FlutterError {
                result(e)
            } catch {
                result(FlutterError(code: "UNKNOWN", message: "\(error)", details: nil))
            }
        case "stopCalibration":
            nfbCalibratorBridge.stopCalibration()
            result(nil)
        case "importCalibration":
            guard let args = call.arguments as? [String: Any],
                  let calibratorData = args["calibratorData"] as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing 'calibratorData'", details: nil))
                return
            }
            do {
                let dev = try deviceBridge.requireDevice()
                try nfbCalibratorBridge.importCalibration(device: dev, calibratorData: calibratorData)
                result(nil)
            } catch let e as FlutterError {
                result(e)
            } catch {
                result(FlutterError(code: "UNKNOWN", message: "\(error)", details: nil))
            }
        case "getCalibration":
            do {
                let dev = try deviceBridge.requireDevice()
                let map = try nfbCalibratorBridge.getCalibration(device: dev)
                result(map)
            } catch let e as FlutterError {
                result(e)
            } catch {
                result(FlutterError(code: "UNKNOWN", message: "\(error)", details: nil))
            }
        case "isCalibrated":
            do {
                let dev = try deviceBridge.requireDevice()
                result(nfbCalibratorBridge.isCalibrated(device: dev))
            } catch let e as FlutterError {
                result(e)
            } catch {
                result(FlutterError(code: "UNKNOWN", message: "\(error)", details: nil))
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - emotions dispatch

    private func handleEmotionsCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let emotionsBridge = emotionsBridge, let deviceBridge = deviceBridge else {
            result(FlutterError(code: "NOT_INITIALIZED", message: "EmotionsBridge or DeviceBridge not initialized", details: nil))
            return
        }
        switch call.method {
        case "create":
            do {
                let dev = try deviceBridge.requireDevice()
                try emotionsBridge.create(device: dev)
                result(nil)
            } catch let e as FlutterError {
                result(e)
            } catch {
                result(FlutterError(code: "UNKNOWN", message: "\(error)", details: nil))
            }
        case "dispose":
            emotionsBridge.dispose()
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - physiological dispatch

    private func handlePhysiologicalCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let physioBridge = physioBridge, let deviceBridge = deviceBridge else {
            result(FlutterError(code: "NOT_INITIALIZED", message: "PhysioBridge or DeviceBridge not initialized", details: nil))
            return
        }
        switch call.method {
        case "create":
            do {
                let dev = try deviceBridge.requireDevice()
                try physioBridge.create(device: dev)
                result(nil)
            } catch let e as FlutterError {
                result(e)
            } catch {
                result(FlutterError(code: "UNKNOWN", message: "\(error)", details: nil))
            }
        case "startBaselineCalibration":
            do {
                try physioBridge.startBaselineCalibration()
                result(nil)
            } catch let e as FlutterError {
                result(e)
            } catch {
                result(FlutterError(code: "UNKNOWN", message: "\(error)", details: nil))
            }
        case "importBaselines":
            let args = call.arguments as? [String: Any]
            guard let baselines = args?["baselines"] as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing 'baselines'", details: nil))
                return
            }
            do {
                try physioBridge.importBaselines(map: baselines)
                result(nil)
            } catch let e as FlutterError {
                result(e)
            } catch {
                result(FlutterError(code: "UNKNOWN", message: "\(error)", details: nil))
            }
        case "dispose":
            physioBridge.dispose()
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - cardio dispatch

    private func handleCardioCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let cardioBridge = cardioBridge, let deviceBridge = deviceBridge else {
            result(FlutterError(code: "NOT_INITIALIZED", message: "CardioBridge or DeviceBridge not initialized", details: nil))
            return
        }
        switch call.method {
        case "create":
            do {
                let dev = try deviceBridge.requireDevice()
                try cardioBridge.create(device: dev)
                result(nil)
            } catch let e as FlutterError {
                result(e)
            } catch {
                result(FlutterError(code: "UNKNOWN", message: "\(error)", details: nil))
            }
        case "createCalibrated":
            let args = call.arguments as? [String: Any]
            let calibrationData = args?["calibrationData"] as? [String: Any]
            do {
                let dev = try deviceBridge.requireDevice()
                try cardioBridge.createCalibrated(device: dev, calibrationData: calibrationData)
                result(nil)
            } catch let e as FlutterError {
                result(e)
            } catch {
                result(FlutterError(code: "UNKNOWN", message: "\(error)", details: nil))
            }
        case "dispose":
            cardioBridge.dispose()
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - productivity dispatch

    private func handleProductivityCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let productivityBridge = productivityBridge, let deviceBridge = deviceBridge else {
            result(FlutterError(code: "NOT_INITIALIZED", message: "ProductivityBridge or DeviceBridge not initialized", details: nil))
            return
        }
        let args = call.arguments as? [String: Any]
        switch call.method {
        case "create":
            do {
                let dev = try deviceBridge.requireDevice()
                try productivityBridge.create(device: dev)
                result(nil)
            } catch let e as FlutterError {
                result(e)
            } catch {
                result(FlutterError(code: "UNKNOWN", message: "\(error)", details: nil))
            }
        case "createCalibrated":
            guard let calibrationData = args?["calibrationData"] as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARGS", message: "calibrationData is required", details: nil))
                return
            }
            do {
                let dev = try deviceBridge.requireDevice()
                try productivityBridge.createCalibrated(device: dev, calibrationData: calibrationData)
                result(nil)
            } catch let e as FlutterError {
                result(e)
            } catch {
                result(FlutterError(code: "UNKNOWN", message: "\(error)", details: nil))
            }
        case "startBaselineCalibration":
            do {
                try productivityBridge.startBaselineCalibration()
                result(nil)
            } catch let e as FlutterError {
                result(e)
            } catch {
                result(FlutterError(code: "UNKNOWN", message: "\(error)", details: nil))
            }
        case "importBaselines":
            guard let baselines = args?["baselines"] as? FlutterStandardTypedData else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing 'baselines'", details: nil))
                return
            }
            do {
                try productivityBridge.importBaselines(data: baselines)
                result(nil)
            } catch let e as FlutterError {
                result(e)
            } catch {
                result(FlutterError(code: "UNKNOWN", message: "\(error)", details: nil))
            }
        case "resetAccumulatedFatigue":
            do {
                try productivityBridge.resetAccumulatedFatigue()
                result(nil)
            } catch let e as FlutterError {
                result(e)
            } catch {
                result(FlutterError(code: "UNKNOWN", message: "\(error)", details: nil))
            }
        case "dispose":
            productivityBridge.dispose()
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - EventChannel registration

    private func registerEventChannels() {
        let messenger = registrar.messenger()

        // Build lookup for the 8 live device stream handlers
        var deviceHandlers: [String: FlutterStreamHandler] = [:]
        if let bridge = deviceBridge {
            for (id, handler) in bridge.allStreamHandlers() {
                deviceHandlers[id] = handler
            }
        }

        // Build lookup for the 2 NFB stream handlers
        var nfbHandlers: [String: FlutterStreamHandler] = [:]
        if let bridge = nfbBridge {
            for (id, handler) in bridge.allStreamHandlers() {
                nfbHandlers[id] = handler
            }
        }

        // Build lookup for the NFB calibration stream handler
        var nfbCalibratorHandlers: [String: FlutterStreamHandler] = [:]
        if let bridge = nfbCalibratorBridge {
            for (id, handler) in bridge.allStreamHandlers() {
                nfbCalibratorHandlers[id] = handler
            }
        }

        // Build lookup for the 2 Emotions stream handlers
        var emotionsHandlers: [String: FlutterStreamHandler] = [:]
        if let bridge = emotionsBridge {
            for (id, handler) in bridge.allStreamHandlers() {
                emotionsHandlers[id] = handler
            }
        }

        // Build lookup for the 4 Physiological stream handlers
        var physioHandlers: [String: FlutterStreamHandler] = [:]
        if let bridge = physioBridge {
            for (id, handler) in bridge.allStreamHandlers() {
                physioHandlers[id] = handler
            }
        }

        // Build lookup for the 3 Cardio stream handlers
        var cardioHandlers: [String: FlutterStreamHandler] = [:]
        if let bridge = cardioBridge {
            for (id, handler) in bridge.allStreamHandlers() {
                cardioHandlers[id] = handler
            }
        }

        // Build lookup for the 6 Productivity stream handlers
        var productivityHandlers: [String: FlutterStreamHandler] = [:]
        if let bridge = productivityBridge {
            for (id, handler) in bridge.allStreamHandlers() {
                productivityHandlers[id] = handler
            }
        }

        let ids: [String] = [
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
        ]
        for id in ids {
            let channel = FlutterEventChannel(name: id, binaryMessenger: messenger)
            if id == "neiry_kit/events/deviceList" {
                channel.setStreamHandler(deviceLocatorBridge)
            } else if let handler = deviceHandlers[id] {
                channel.setStreamHandler(handler)
            } else if let handler = nfbHandlers[id] {
                channel.setStreamHandler(handler)
            } else if let handler = nfbCalibratorHandlers[id] {
                channel.setStreamHandler(handler)
            } else if let handler = emotionsHandlers[id] {
                channel.setStreamHandler(handler)
            } else if let handler = physioHandlers[id] {
                channel.setStreamHandler(handler)
            } else if let handler = cardioHandlers[id] {
                channel.setStreamHandler(handler)
            } else if let handler = productivityHandlers[id] {
                channel.setStreamHandler(handler)
            } else {
                channel.setStreamHandler(StubStreamHandler())
            }
            eventChannels[id] = channel
        }
    }
}

// MARK: - StubStreamHandler

private class StubStreamHandler: NSObject, FlutterStreamHandler {
    func onListen(withArguments arguments: Any?,
                  eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        return nil
    }
}
