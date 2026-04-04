import Flutter
import UIKit

public class NeiryKitPlugin: NSObject, FlutterPlugin {
    private static var instance: NeiryKitPlugin?

    private let registrar: FlutterPluginRegistrar
    private var methodChannels: [String: FlutterMethodChannel] = [:]
    private var eventChannels: [String: FlutterEventChannel] = [:]

    private init(registrar: FlutterPluginRegistrar) {
        self.registrar = registrar
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = NeiryKitPlugin(registrar: registrar)
        self.instance = instance
        instance.registerMethodChannels()
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
            switch call.method {
            case "getVersionString":
                let version = String(cString: clCCapsule_GetVersionString())
                result(version)
            default:
                result(FlutterMethodNotImplemented)
            }
        } else {
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
            channel.setStreamHandler(StubStreamHandler())
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
