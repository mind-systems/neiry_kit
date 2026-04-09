import Flutter
import UIKit

// MARK: - ProductivityBridge

class ProductivityBridge: NSObject {

    // MARK: Static state (used by C callbacks which cannot capture `self`)

    /// The currently active bridge. C callbacks reach the instance through this
    /// static weak reference because `clCProductivity_Set*Event` callbacks have no
    /// `void* context` parameter.
    private static weak var activeBridge: ProductivityBridge?

    // MARK: Stream handlers

    let metricsHandler = DeviceStreamHandler(channelId: "neiry_kit/events/productivityMetrics")
    let indexesHandler = DeviceStreamHandler(channelId: "neiry_kit/events/productivityIndexes")
    let baselinesHandler = DeviceStreamHandler(channelId: "neiry_kit/events/productivityBaselines")
    let calibrationProgressHandler = DeviceStreamHandler(channelId: "neiry_kit/events/productivityCalibrationProgress")
    let calibratedHandler = DeviceStreamHandler(channelId: "neiry_kit/events/productivityCalibrated")
    let individualNfbHandler = DeviceStreamHandler(channelId: "neiry_kit/events/productivityIndividualNfb")

    /// Returns all (channelId, handler) pairs for EventChannel registration in the plugin.
    func allStreamHandlers() -> [(String, FlutterStreamHandler)] {
        return [
            (metricsHandler.channelId, metricsHandler),
            (indexesHandler.channelId, indexesHandler),
            (baselinesHandler.channelId, baselinesHandler),
            (calibrationProgressHandler.channelId, calibrationProgressHandler),
            (calibratedHandler.channelId, calibratedHandler),
            (individualNfbHandler.channelId, individualNfbHandler),
        ]
    }

    // MARK: Instance state

    private var productivity: OpaquePointer?

    // MARK: - Public API

    /// Creates an uncalibrated Productivity classifier for the given device handle.
    func create(device: OpaquePointer) throws {
        if productivity != nil { unregisterCallbacks() }
        var error = clCError()
        productivity = clCProductivity_Create(device, &error)
        try checkCError(error)
        registerCallbacks()
    }

    /// Creates a calibrated Productivity classifier using individual NFB data.
    /// Unlike CardioBridge/NfbBridge, Productivity takes `clCIndividualNFBData` directly —
    /// no `clCNFBCalibrator_CreateOrGet` call is needed.
    func createCalibrated(device: OpaquePointer, calibrationData: [String: Any]) throws {
        if productivity != nil { unregisterCallbacks() }
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
        var error = clCError()
        productivity = clCProductivity_CreateWithIndividualData(device, &data, &error)
        try checkCError(error)
        registerCallbacks()
    }

    /// Unregisters all callbacks and releases the Productivity handle.
    /// There is no `clCProductivity_Destroy` in the SDK — disposal is callback-only.
    func dispose() {
        unregisterCallbacks()
        productivity = nil
    }

    // MARK: - Private helpers

    private func requireProductivity() throws -> OpaquePointer {
        guard let productivity = productivity else {
            throw FlutterError(code: "NOT_CREATED",
                               message: "ProductivityBridge not created — call create first",
                               details: nil)
        }
        return productivity
    }

    // MARK: - Callbacks

    private func registerCallbacks() {
        guard let productivity = productivity else { return }
        ProductivityBridge.activeBridge = self

        clCProductivity_SetOnMetricsUpdateEvent(productivity) { _, data in
            guard let bridge = ProductivityBridge.activeBridge,
                  let data = data else { return }
            let d = data.pointee
            var map: [String: Any] = [
                "ts":                   d.timestampMilli,
                "fatigueScore":         d.fatigueScore,
                "reverseFatigueScore":  d.reverseFatigueScore,
                "gravityScore":         d.gravityScore,
                "relaxationScore":      d.relaxationScore,
                "concentrationScore":   d.concentrationScore,
                "productivityScore":    d.productivityScore,
                "currentValue":         d.currentValue,
                "alpha":                d.alpha,
                "productivityBaseline": d.productivityBaseline,
                "accumulatedFatigue":   d.accumulatedFatigue,
                "fatigueGrowthRate":    d.fatigueGrowthRate.rawValue,
            ]
            if d.artifactsSize > 0, let ptr = d.artifactsData {
                let bytes = Data(bytes: ptr, count: Int(d.artifactsSize))
                map["artifactsData"] = FlutterStandardTypedData(bytes: bytes)
            } else {
                map["artifactsData"] = NSNull()
            }
            bridge.metricsHandler.send(map)
        }

        clCProductivity_SetOnIndexesUpdateEvent(productivity) { _, data in
            guard let bridge = ProductivityBridge.activeBridge,
                  let data = data else { return }
            let d = data.pointee
            let map: [String: Any] = [
                "ts":                     d.timestampMilli,
                "relaxation":             d.relaxation.rawValue,
                "stress":                 d.stress.rawValue,
                "hasArtifacts":           d.hasArtifacts,
                "gravityBaseline":        d.gravityBaseline,
                "productivityBaseline":   d.productivityBaseline,
                "fatigueBaseline":        d.fatigueBaseline,
                "reverseFatigueBaseline": d.reverseFatigueBaseline,
                "relaxationBaseline":     d.relaxationBaseline,
                "concentrationBaseline":  d.concentrationBaseline,
            ]
            bridge.indexesHandler.send(map)
        }

        clCProductivity_SetOnBaselineUpdateEvent(productivity) { _, baselines in
            guard let bridge = ProductivityBridge.activeBridge,
                  let baselines = baselines else { return }
            let b = baselines.pointee
            let map: [String: Any] = [
                "ts":             b.timestampMilli,
                "gravity":        b.gravity,
                "productivity":   b.productivity,
                "fatigue":        b.fatigue,
                "reverseFatigue": b.reverseFatigue,
                "relaxation":     b.relaxation,
                "concentration":  b.concentration,
            ]
            bridge.baselinesHandler.send(map)

            // Serialize the raw struct bytes for opaque blob persistence
            let raw = withUnsafePointer(to: b) {
                Data(bytes: $0, count: MemoryLayout<clCProductivity_Baselines>.size)
            }
            bridge.calibratedHandler.send(["baselines": FlutterStandardTypedData(bytes: raw)])
        }

        clCProductivity_SetOnCalibrationProgressUpdateEvent(productivity) { _, progress in
            guard let bridge = ProductivityBridge.activeBridge else { return }
            let clamped = max(0.0, min(1.0, progress))
            bridge.calibrationProgressHandler.send(["progress": clamped])
        }

        clCProductivity_SetOnIndividualNFBUpdateEvent(productivity) { _ in
            guard let bridge = ProductivityBridge.activeBridge else { return }
            bridge.individualNfbHandler.send([:])
        }
    }

    private func unregisterCallbacks() {
        guard let productivity = productivity else { return }
        clCProductivity_SetOnMetricsUpdateEvent(productivity, nil)
        clCProductivity_SetOnIndexesUpdateEvent(productivity, nil)
        clCProductivity_SetOnBaselineUpdateEvent(productivity, nil)
        clCProductivity_SetOnCalibrationProgressUpdateEvent(productivity, nil)
        clCProductivity_SetOnIndividualNFBUpdateEvent(productivity, nil)
        if ProductivityBridge.activeBridge === self {
            ProductivityBridge.activeBridge = nil
        }
    }

    // MARK: - Commands

    /// Starts baseline calibration on the native `clCProductivity` classifier.
    func startBaselineCalibration() throws {
        let productivity = try requireProductivity()
        clCProductivity_StartBaselineCalibration(productivity)
    }

    /// Imports previously saved baselines into the native classifier.
    /// The raw bytes must match the size of `clCProductivity_Baselines`.
    func importBaselines(data: FlutterStandardTypedData) throws {
        let productivity = try requireProductivity()
        guard data.data.count == MemoryLayout<clCProductivity_Baselines>.size else {
            throw FlutterError(code: "INVALID_ARGS",
                               message: "Baselines data size mismatch",
                               details: nil)
        }
        var baselines = clCProductivity_Baselines()
        data.data.withUnsafeBytes { baselines = $0.load(as: clCProductivity_Baselines.self) }
        var error = clCError()
        clCProductivity_ImportBaselines(productivity, &baselines, &error)
        try checkCError(error)
    }

    /// Resets accumulated fatigue state in the native classifier.
    /// SDK does not guarantee atomicity — metrics may briefly show stale fatigue during the reset window.
    func resetAccumulatedFatigue() throws {
        let productivity = try requireProductivity()
        var error = clCError()
        clCProductivity_ResetAccumulatedFatigue(productivity, &error)
        try checkCError(error)
    }
}
