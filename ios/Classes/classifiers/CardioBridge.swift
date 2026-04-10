import Flutter
import UIKit

// MARK: - CardioBridge

class CardioBridge: NSObject {

    // MARK: Static state (used by C callbacks which cannot capture `self`)

    /// The currently active bridge. C callbacks reach the instance through this
    /// static weak reference because `clCCardio_Set*Event` callbacks have no
    /// `void* context` parameter.
    private static weak var activeBridge: CardioBridge?

    // MARK: Stream handlers

    let cardioDataHandler = DeviceStreamHandler(channelId: "neiry_kit/events/cardioData")
    let cardioPpgHandler = DeviceStreamHandler(channelId: "neiry_kit/events/ppgData")
    let cardioCalibratedHandler = DeviceStreamHandler(channelId: "neiry_kit/events/cardioCalibratedEvent")

    /// Returns all (channelId, handler) pairs for EventChannel registration in the plugin.
    func allStreamHandlers() -> [(String, FlutterStreamHandler)] {
        return [
            (cardioDataHandler.channelId, cardioDataHandler),
            (cardioPpgHandler.channelId, cardioPpgHandler),
            (cardioCalibratedHandler.channelId, cardioCalibratedHandler),
        ]
    }

    // MARK: Instance state

    private var cardio: OpaquePointer?

    // MARK: - Public API

    /// Creates an uncalibrated Cardio classifier for the given device handle.
    func create(device: OpaquePointer) throws {
        if cardio != nil { unregisterCallbacks() }
        var error = clCError()
        cardio = clCCardio_Create(device, &error)
        try checkCError(error)
        try registerCallbacks()
    }

    /// Creates a calibrated Cardio classifier for the given device handle.
    /// If `calibrationData` is provided, it is imported into the calibrator before creating.
    func createCalibrated(device: OpaquePointer, calibrationData: [String: Any]?) throws {
        if cardio != nil { unregisterCallbacks() }
        guard let calibrator = clCNFBCalibrator_CreateOrGet(device) else {
            throw FlutterError(code: "NULL_HANDLE", message: "clCNFBCalibrator_CreateOrGet returned nil", details: nil)
        }
        if let calibrationData = calibrationData {
            var data = clCIndividualNFBData()
            if let ts = calibrationData["ts"] as? Int {
                data.timestampMilli = Int64(ts)
            }
            if let failReasonRaw = calibrationData["failReason"] as? Int {
                data.failReason = clCIndividualNFBCalibrationFailReason(rawValue: UInt32(failReasonRaw))
            }
            if let v = calibrationData["individualFrequency"] as? Double { data.individualFrequency = Float(v) }
            if let v = calibrationData["individualPeakFrequency"] as? Double { data.individualPeakFrequency = Float(v) }
            if let v = calibrationData["individualPeakFrequencyPower"] as? Double { data.individualPeakFrequencyPower = Float(v) }
            if let v = calibrationData["individualPeakFrequencySuppression"] as? Double { data.individualPeakFrequencySuppression = Float(v) }
            if let v = calibrationData["individualBandwidth"] as? Double { data.individualBandwidth = Float(v) }
            if let v = calibrationData["individualNormalizedPower"] as? Double { data.individualNormalizedPower = Float(v) }
            if let v = calibrationData["lowerFrequency"] as? Double { data.lowerFrequency = Float(v) }
            if let v = calibrationData["upperFrequency"] as? Double { data.upperFrequency = Float(v) }
            var importError = clCError()
            clCNFBCalibrator_ImportIndividualNFBData(calibrator, &data, &importError)
            try checkCError(importError)
        }
        var error = clCError()
        cardio = clCCardio_CreateCalibrated(device, calibrator, &error)
        try checkCError(error)
        try registerCallbacks()
    }

    /// Unregisters all callbacks and releases the Cardio handle.
    /// There is no `clCCardio_Destroy` in the SDK — disposal is callback-only.
    func dispose() {
        unregisterCallbacks()
        cardio = nil
    }

    // MARK: - Callbacks

    private func registerCallbacks() throws {
        guard let cardio = cardio else { return }
        CardioBridge.activeBridge = self

        var e1 = clCError()
        clCCardio_SetOnIndexesUpdateEvent(cardio, { _, data in
            guard let bridge = CardioBridge.activeBridge,
                  let data = data else { return }
            let d = data.pointee
            let map: [String: Any] = [
                "ts":               d.timestampMilli,
                "heartRate":        d.heartRate,
                "stressIndex":      d.stressIndex,
                "kaplanIndex":      d.kaplanIndex,
                "hasArtifacts":     d.hasArtifacts,
                "skinContact":      d.skinContact,
                "motionArtifacts":  d.motionArtifacts,
                "metricsAvailable": d.metricsAvailable,
            ]
            bridge.cardioDataHandler.send(map)
        }, &e1)
        try checkCError(e1)

        var e2 = clCError()
        clCCardio_SetOnPPGDataEvent(cardio, { _, ppgData in
            guard let bridge = CardioBridge.activeBridge,
                  let ppgData = ppgData else { return }
            let count = clCPPGTimedData_GetCount(ppgData)
            var values: [Float] = []
            var timestamps: [UInt64] = []
            for i in 0..<count {
                values.append(clCPPGTimedData_GetValue(ppgData, i))
                timestamps.append(clCPPGTimedData_GetTimestampMilli(ppgData, i))
            }
            let map: [String: Any] = [
                "sampleCount": count,
                "values":      values,
                "timestamps":  timestamps,
            ]
            bridge.cardioPpgHandler.send(map)
        }, &e2)
        try checkCError(e2)

        var e3 = clCError()
        clCCardio_SetOnCalibratedEvent(cardio, { _ in
            guard let bridge = CardioBridge.activeBridge else { return }
            bridge.cardioCalibratedHandler.send([:])
        }, &e3)
        try checkCError(e3)
    }

    private func unregisterCallbacks() {
        guard let cardio = cardio else { return }
        var e = clCError()
        clCCardio_SetOnIndexesUpdateEvent(cardio, nil, &e)
        clCCardio_SetOnPPGDataEvent(cardio, nil, &e)
        clCCardio_SetOnCalibratedEvent(cardio, nil, &e)
        if CardioBridge.activeBridge === self {
            CardioBridge.activeBridge = nil
        }
    }
}
