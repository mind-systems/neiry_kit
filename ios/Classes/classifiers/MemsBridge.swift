import Flutter
import UIKit

// MARK: - MemsBridge

class MemsBridge: NSObject {

    // MARK: Static state (used by C callbacks which cannot capture `self`)

    /// The currently active bridge. C callbacks reach the instance through this
    /// static weak reference because `clCMEMS_Set*Event` callbacks have no
    /// `void* context` parameter.
    private static weak var activeBridge: MemsBridge?

    // MARK: Stream handlers

    let memsDataHandler = DeviceStreamHandler(channelId: "neiry_kit/events/memsData")

    /// Returns all (channelId, handler) pairs for EventChannel registration in the plugin.
    func allStreamHandlers() -> [(String, FlutterStreamHandler)] {
        return [
            (memsDataHandler.channelId, memsDataHandler),
        ]
    }

    // MARK: Instance state

    private var mems: OpaquePointer?

    // MARK: - Public API

    /// Creates an uncalibrated MEMS classifier for the given device handle.
    func create(device: OpaquePointer) throws {
        if mems != nil { unregisterCallbacks() }
        var error = clCError()
        mems = clCMEMS_Create(device, &error)
        try checkCError(error)
        try registerCallbacks()
    }

    /// Creates a calibrated MEMS classifier for the given device handle.
    /// If `calibrationData` is provided, it is imported into the calibrator before creating.
    func createCalibrated(device: OpaquePointer, calibrationData: [String: Any]?) throws {
        if mems != nil { unregisterCallbacks() }
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
        mems = clCMEMS_CreateCalibrated(device, calibrator, &error)
        try checkCError(error)
        try registerCallbacks()
    }

    /// Unregisters all callbacks and releases the MEMS handle.
    /// There is no `clCMEMS_Destroy` in the SDK — disposal is callback-only.
    func dispose() {
        unregisterCallbacks()
        mems = nil
    }

    // MARK: - Callbacks

    private func registerCallbacks() throws {
        guard let mems = mems else { return }
        MemsBridge.activeBridge = self

        var e1 = clCError()
        clCMEMS_SetOnMEMSTimedDataUpdateEvent(mems, { _, memsData in
            guard let bridge = MemsBridge.activeBridge,
                  let memsData = memsData else { return }
            let count = clCMEMSTimedData_GetCount(memsData)
            var samples: [[String: Any]] = []
            for i in 0..<count {
                let accel = clCMEMSTimedData_GetAccelerometer(memsData, i)
                let gyro = clCMEMSTimedData_GetGyroscope(memsData, i)
                let ts = clCMEMSTimedData_GetTimestampMilli(memsData, i)
                let sample: [String: Any] = [
                    "ax": accel.x,
                    "ay": accel.y,
                    "az": accel.z,
                    "gx": gyro.x,
                    "gy": gyro.y,
                    "gz": gyro.z,
                    "ts": ts,
                ]
                samples.append(sample)
            }
            bridge.memsDataHandler.sendList(samples)
        }, &e1)
        try checkCError(e1)
    }

    private func unregisterCallbacks() {
        guard let mems = mems else { return }
        var e = clCError()
        clCMEMS_SetOnMEMSTimedDataUpdateEvent(mems, nil, &e)
        if MemsBridge.activeBridge === self {
            MemsBridge.activeBridge = nil
        }
    }
}
