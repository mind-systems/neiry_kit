import Flutter
import UIKit

// MARK: - PhysioBridge

class PhysioBridge: NSObject {

    // MARK: Static state (used by C callbacks which cannot capture `self`)

    /// The currently active bridge. C callbacks reach the instance through this
    /// static weak reference because `clCPhysiologicalStates_Set*Event` callbacks
    /// have no `void* context` parameter.
    private static weak var activeBridge: PhysioBridge?

    // MARK: Stream handlers

    let physiologicalStateHandler = DeviceStreamHandler(channelId: "neiry_kit/events/physiologicalState")
    let calibrationProgressHandler = DeviceStreamHandler(channelId: "neiry_kit/events/physiologicalCalibrationProgress")
    let calibratedHandler = DeviceStreamHandler(channelId: "neiry_kit/events/physiologicalCalibrated")
    let individualNfbHandler = DeviceStreamHandler(channelId: "neiry_kit/events/physiologicalIndividualNfb")

    /// Returns all (channelId, handler) pairs for EventChannel registration in the plugin.
    func allStreamHandlers() -> [(String, FlutterStreamHandler)] {
        return [
            (physiologicalStateHandler.channelId, physiologicalStateHandler),
            (calibrationProgressHandler.channelId, calibrationProgressHandler),
            (calibratedHandler.channelId, calibratedHandler),
            (individualNfbHandler.channelId, individualNfbHandler),
        ]
    }

    // MARK: Instance state

    private var physio: OpaquePointer?

    // MARK: - Public API

    /// Creates a PhysiologicalStates classifier for the given device handle.
    func create(device: OpaquePointer) throws {
        if physio != nil { unregisterCallbacks() }
        var error = clCError()
        physio = clCPhysiologicalStates_Create(device, &error)
        try checkCError(error)
        try registerCallbacks()
    }

    /// Starts baseline calibration on the native classifier.
    func startBaselineCalibration() throws {
        let physio = try requirePhysio()
        clCPhysiologicalStates_StartBaselineCalibration(physio)
    }

    /// Imports previously saved baselines into the native classifier.
    func importBaselines(map: [String: Any]) throws {
        let physio = try requirePhysio()
        var baselines = clCPhysiologicalStates_Baselines()
        if let ts = map["ts"] as? Int { baselines.timestampMilli = Int64(ts) }
        if let v = map["alpha"] as? Double { baselines.alpha = Float(v) }
        if let v = map["beta"] as? Double { baselines.beta = Float(v) }
        if let v = map["alphaGravity"] as? Double { baselines.alphaGravity = Float(v) }
        if let v = map["betaGravity"] as? Double { baselines.betaGravity = Float(v) }
        if let v = map["concentration"] as? Double { baselines.concentration = Float(v) }
        clCPhysiologicalStates_ImportBaselines(physio, &baselines)
    }

    /// Unregisters all callbacks and releases the PhysiologicalStates handle.
    /// There is no `clCPhysiologicalStates_Destroy` in the SDK — disposal is callback-only.
    func dispose() {
        unregisterCallbacks()
        physio = nil
    }

    // MARK: - Private helpers

    private func requirePhysio() throws -> OpaquePointer {
        guard let physio = physio else {
            throw FlutterError(code: "NOT_CREATED",
                               message: "PhysioBridge not created — call create first",
                               details: nil)
        }
        return physio
    }

    // MARK: - Callbacks

    private func registerCallbacks() throws {
        guard let physio = physio else { return }
        PhysioBridge.activeBridge = self

        var error1 = clCError()
        clCPhysiologicalStates_SetOnStatesUpdateEvent(physio, { _, data in
            guard let bridge = PhysioBridge.activeBridge,
                  let data = data else { return }
            let state = data.pointee
            let map: [String: Any] = [
                "ts":             state.timestampMilli,
                "relaxation":     state.relaxation,
                "fatigue":        state.fatigue,
                "none":           state.none,
                "concentration":  state.concentration,
                "involvement":    state.involvement,
                "stress":         state.stress,
                "nfbArtifacts":   state.nfbArtifacts,
                "cardioArtifacts": state.cardioArtifacts,
            ]
            bridge.physiologicalStateHandler.send(map)
        }, &error1)
        try checkCError(error1)

        var error2 = clCError()
        clCPhysiologicalStates_SetOnCalibrationProgressUpdateEvent(physio, { _, progress in
            guard let bridge = PhysioBridge.activeBridge else { return }
            let clamped = max(0.0, min(1.0, progress))
            bridge.calibrationProgressHandler.send(["progress": clamped])
        }, &error2)
        try checkCError(error2)

        var error3 = clCError()
        clCPhysiologicalStates_SetOnCalibratedEvent(physio, { _, baselines in
            guard let bridge = PhysioBridge.activeBridge,
                  let baselines = baselines else { return }
            let b = baselines.pointee
            let map: [String: Any] = [
                "ts":            b.timestampMilli,
                "alpha":         b.alpha,
                "beta":          b.beta,
                "alphaGravity":  b.alphaGravity,
                "betaGravity":   b.betaGravity,
                "concentration": b.concentration,
            ]
            bridge.calibratedHandler.send(map)
        }, &error3)
        try checkCError(error3)

        var error4 = clCError()
        clCPhysiologicalStates_SetOnIndividualNFBUpdateEvent(physio, { _ in
            guard let bridge = PhysioBridge.activeBridge else { return }
            bridge.individualNfbHandler.send([:])
        }, &error4)
        try checkCError(error4)
    }

    private func unregisterCallbacks() {
        guard let physio = physio else { return }
        var e = clCError()
        clCPhysiologicalStates_SetOnStatesUpdateEvent(physio, nil, &e)
        clCPhysiologicalStates_SetOnCalibrationProgressUpdateEvent(physio, nil, &e)
        clCPhysiologicalStates_SetOnCalibratedEvent(physio, nil, &e)
        clCPhysiologicalStates_SetOnIndividualNFBUpdateEvent(physio, nil, &e)
        if PhysioBridge.activeBridge === self {
            PhysioBridge.activeBridge = nil
        }
    }
}
