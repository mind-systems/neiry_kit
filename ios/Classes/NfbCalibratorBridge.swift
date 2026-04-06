import Flutter
import UIKit

// MARK: - NfbCalibratorBridge

class NfbCalibratorBridge: NSObject {

    // MARK: Static state (used by C callbacks which cannot capture `self`)

    /// The currently active bridge. C callbacks reach the instance through this
    /// static weak reference because `clCNFBCalibrator` callbacks have no
    /// `void* context` parameter.
    private static weak var activeBridge: NfbCalibratorBridge?

    // MARK: Stream handlers

    let calibrationHandler = DeviceStreamHandler(channelId: "neiry_kit/events/nfbCalibration")

    /// Returns all (channelId, handler) pairs for EventChannel registration in the plugin.
    func allStreamHandlers() -> [(String, FlutterStreamHandler)] {
        return [(calibrationHandler.channelId, calibrationHandler)]
    }

    // MARK: Instance state

    /// Cached `clCNFBCalibrator` handle. Never destroyed — the SDK manages its lifecycle.
    private var calibrator: OpaquePointer?

    /// Tracks the current stage index (0-indexed); incremented each time the
    /// stage-finished callback fires. Reset to 0 at the start of each calibration run.
    private var currentStage: Int = 0

    /// Set true when quick calibration is active; used only to guard against stage
    /// advancement in the stage-finished callback. Does NOT affect how data is delivered.
    private var isQuickMode: Bool = false

    // MARK: - Public API

    /// Starts a full 4-stage or quick individual NFB calibration.
    ///
    /// Calls `result(nil)` immediately — progress and completion are delivered via
    /// `calibrationHandler` (EventChannel), not through the MethodChannel return value.
    func startCalibration(device: OpaquePointer, quick: Bool, result: @escaping FlutterResult) throws {
        guard let cal = clCNFBCalibrator_CreateOrGet(device) else {
            throw FlutterError(code: "NULL_HANDLE",
                               message: "clCNFBCalibrator_CreateOrGet returned nil",
                               details: nil)
        }
        calibrator = cal
        currentStage = 0
        isQuickMode = quick
        registerCallbacks()

        if quick {
            var error = clCError()
            clCNFBCalibrator_CalibrateIndividualNFBQuick(cal, &error)
            try checkCError(error)
        } else {
            var error = clCError()
            clCNFBCalibrator_CalibrateIndividualNFB(cal, clCIndividualNFBCalibrationStage_1, &error)
            try checkCError(error)
        }
        result(nil)
    }

    /// Stops any in-progress calibration. Does NOT call any C cancel function —
    /// the calibrator is left idle; no handle cleanup is needed.
    func stopCalibration() {
        unregisterCallbacks()
        currentStage = 0
        isQuickMode = false
    }

    /// Imports previously obtained calibration data into the native calibrator.
    func importCalibration(device: OpaquePointer, calibratorData: [String: Any]) throws {
        guard let cal = clCNFBCalibrator_CreateOrGet(device) else {
            throw FlutterError(code: "NULL_HANDLE",
                               message: "clCNFBCalibrator_CreateOrGet returned nil",
                               details: nil)
        }
        calibrator = cal
        var data = clCIndividualNFBData()
        if let ts = calibratorData["ts"] as? Int {
            data.timestampMilli = Int64(ts)
        }
        if let v = calibratorData["failReason"] as? Int {
            data.failReason = clCIndividualNFBCalibrationFailReason(rawValue: UInt32(v))
        }
        if let v = calibratorData["individualFrequency"] as? Double { data.individualFrequency = Float(v) }
        if let v = calibratorData["individualPeakFrequency"] as? Double { data.individualPeakFrequency = Float(v) }
        if let v = calibratorData["individualPeakFrequencyPower"] as? Double { data.individualPeakFrequencyPower = Float(v) }
        if let v = calibratorData["individualPeakFrequencySuppression"] as? Double { data.individualPeakFrequencySuppression = Float(v) }
        if let v = calibratorData["individualBandwidth"] as? Double { data.individualBandwidth = Float(v) }
        if let v = calibratorData["individualNormalizedPower"] as? Double { data.individualNormalizedPower = Float(v) }
        if let v = calibratorData["lowerFrequency"] as? Double { data.lowerFrequency = Float(v) }
        if let v = calibratorData["upperFrequency"] as? Double { data.upperFrequency = Float(v) }
        var error = clCError()
        clCNFBCalibrator_ImportIndividualNFBData(cal, &data, &error)
        try checkCError(error)
    }

    /// Returns the calibration data stored in the native calibrator, or `nil`
    /// if no calibration has been performed or imported yet.
    ///
    /// The `isCalibrated` guard is required because the SDK may error or return
    /// a zero-filled struct when queried before any calibration has run.
    func getCalibration(device: OpaquePointer) throws -> [String: Any]? {
        guard let cal = clCNFBCalibrator_CreateOrGet(device) else {
            return nil
        }
        calibrator = cal
        guard clCNFBCalibrator_IsCalibrated(cal) else {
            return nil
        }
        var data = clCIndividualNFBData()
        var error = clCError()
        clCNFBCalibrator_GetIndividualNFB(cal, &data, &error)
        try checkCError(error)
        return NfbCalibratorBridge.nfbDataToMap(data)
    }

    /// Returns `true` when valid calibration data is present in the native calibrator.
    func isCalibrated(device: OpaquePointer) -> Bool {
        guard let cal = clCNFBCalibrator_CreateOrGet(device) else {
            return false
        }
        return clCNFBCalibrator_IsCalibrated(cal)
    }

    // MARK: - Callbacks

    private func registerCallbacks() {
        guard let cal = calibrator else { return }
        NfbCalibratorBridge.activeBridge = self

        clCNFBCalibrator_SetOnCalibrationStageFinishedEvent(cal) { _ in
            guard let bridge = NfbCalibratorBridge.activeBridge else { return }
            // Quick mode does not advance stages via this callback
            if bridge.isQuickMode { return }

            // Emit the finished stage (0-indexed, matches CalibrationStage.code on the Dart side)
            bridge.calibrationHandler.send(["type": "stage", "stage": bridge.currentStage])
            bridge.currentStage += 1

            if bridge.currentStage < 4 {
                // Re-entering the SDK from its own callback is intentional and safe
                // per the SDK's threading model.
                guard let cal = bridge.calibrator else { return }
                var error = clCError()
                clCNFBCalibrator_CalibrateIndividualNFB(
                    cal,
                    clCIndividualNFBCalibrationStage(rawValue: UInt32(bridge.currentStage)),
                    &error
                )
                if !error.success {
                    let message = withUnsafePointer(to: error.message) {
                        $0.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) }
                    }
                    bridge.calibrationHandler.sendError(String(error.code.rawValue), message)
                }
            }
            // currentStage >= 4: all stages triggered — wait for the onCalibrated callback
        }

        clCNFBCalibrator_SetOnCalibratedEvent(cal) { _, dataPtr in
            guard let bridge = NfbCalibratorBridge.activeBridge,
                  let dataPtr = dataPtr else { return }
            let dataMap = NfbCalibratorBridge.nfbDataToMap(dataPtr.pointee)
            // Deliver completion via EventChannel for both full and quick modes
            bridge.calibrationHandler.send(["type": "done", "data": dataMap])
        }
    }

    private func unregisterCallbacks() {
        guard let cal = calibrator else { return }
        clCNFBCalibrator_SetOnCalibrationStageFinishedEvent(cal, nil)
        clCNFBCalibrator_SetOnCalibratedEvent(cal, nil)
        if NfbCalibratorBridge.activeBridge === self {
            NfbCalibratorBridge.activeBridge = nil
        }
    }

    // MARK: - Helpers

    /// Serializes a `clCIndividualNFBData` struct to a `[String: Any]` map
    /// using the same 10 keys expected by `IndividualNfbData.fromMap` on the Dart side.
    /// Float fields are serialized as-is — Flutter's standard message codec handles them correctly.
    private static func nfbDataToMap(_ d: clCIndividualNFBData) -> [String: Any] {
        return [
            "ts":                                 d.timestampMilli,
            "failReason":                         Int(d.failReason.rawValue),
            "individualFrequency":                d.individualFrequency,
            "individualPeakFrequency":            d.individualPeakFrequency,
            "individualPeakFrequencyPower":       d.individualPeakFrequencyPower,
            "individualPeakFrequencySuppression": d.individualPeakFrequencySuppression,
            "individualBandwidth":                d.individualBandwidth,
            "individualNormalizedPower":          d.individualNormalizedPower,
            "lowerFrequency":                     d.lowerFrequency,
            "upperFrequency":                     d.upperFrequency,
        ]
    }
}
