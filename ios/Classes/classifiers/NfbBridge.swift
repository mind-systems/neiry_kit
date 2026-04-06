import Flutter
import UIKit

// MARK: - NfbBridge

class NfbBridge: NSObject {

    // MARK: Static state (used by C callbacks which cannot capture `self`)

    /// The currently active bridge. C callbacks reach the instance through this
    /// static weak reference because `clCNFB_Set*Event` callbacks have no
    /// `void* context` parameter.
    private static weak var activeBridge: NfbBridge?

    // MARK: Stream handlers

    let nfbStateHandler = DeviceStreamHandler(channelId: "neiry_kit/events/nfbState")
    let nfbErrorHandler = DeviceStreamHandler(channelId: "neiry_kit/events/nfbError")

    /// Returns all (channelId, handler) pairs for EventChannel registration in the plugin.
    func allStreamHandlers() -> [(String, FlutterStreamHandler)] {
        return [
            (nfbStateHandler.channelId, nfbStateHandler),
            (nfbErrorHandler.channelId, nfbErrorHandler),
        ]
    }

    // MARK: Instance state

    private var nfb: OpaquePointer?

    // MARK: - Public API

    /// Creates an uncalibrated NFB classifier for the given device handle.
    func create(device: OpaquePointer) throws {
        if nfb != nil { unregisterCallbacks() }
        var error = clCError()
        nfb = clCNFB_Create(device, &error)
        try checkCError(error)
        registerCallbacks()
    }

    /// Creates a calibrated NFB classifier for the given device handle.
    /// If `calibrationData` is provided, it is imported into the calibrator before creating.
    func createCalibrated(device: OpaquePointer, calibrationData: [String: Any]?) throws {
        if nfb != nil { unregisterCallbacks() }
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
        nfb = clCNFB_CreateCalibrated(device, calibrator, &error)
        try checkCError(error)
        registerCallbacks()
    }

    /// Unregisters all callbacks and releases the NFB handle.
    /// There is no `clCNFB_Destroy` in the SDK — disposal is callback-only.
    func dispose() {
        unregisterCallbacks()
        nfb = nil
    }

    // MARK: - Callbacks

    private func registerCallbacks() {
        guard let nfb = nfb else { return }
        NfbBridge.activeBridge = self

        clCNFB_SetOnUserStateChangedEvent(nfb) { _, data in
            guard let bridge = NfbBridge.activeBridge,
                  let data = data else { return }
            let state = data.pointee
            let map: [String: Any] = [
                "ts":    state.timestampMilli,
                "delta": state.delta,
                "theta": state.theta,
                "alpha": state.alpha,
                "smr":   state.smr,
                "beta":  state.beta,
            ]
            bridge.nfbStateHandler.send(map)
        }

        clCNFB_SetOnErrorEvent(nfb) { _, msg in
            guard let bridge = NfbBridge.activeBridge else { return }
            let message = msg.map { String(cString: $0) } ?? ""
            bridge.nfbErrorHandler.send(["message": message])
        }
    }

    private func unregisterCallbacks() {
        guard let nfb = nfb else { return }
        clCNFB_SetOnUserStateChangedEvent(nfb, nil)
        clCNFB_SetOnErrorEvent(nfb, nil)
        if NfbBridge.activeBridge === self {
            NfbBridge.activeBridge = nil
        }
    }
}
