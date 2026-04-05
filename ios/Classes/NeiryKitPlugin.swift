import Flutter
import UIKit

public class NeiryKitPlugin: NSObject, FlutterPlugin {
    private static var instance: NeiryKitPlugin?

    private let registrar: FlutterPluginRegistrar
    private var methodChannels: [String: FlutterMethodChannel] = [:]
    private var eventChannels: [String: FlutterEventChannel] = [:]
    private var deviceLocatorBridge: DeviceLocatorBridge?
    private var deviceBridge: DeviceBridge?

    private init(registrar: FlutterPluginRegistrar) {
        self.registrar = registrar
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = NeiryKitPlugin(registrar: registrar)
        self.instance = instance
        instance.registerMethodChannels()
        instance.deviceLocatorBridge = DeviceLocatorBridge()
        instance.deviceBridge = DeviceBridge()
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
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - EventChannel registration

    private func registerEventChannels() {
        let messenger = registrar.messenger()
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
