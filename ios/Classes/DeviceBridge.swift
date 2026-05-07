import Flutter
import UIKit

// MARK: - DeviceStreamHandler

/// A reusable FlutterStreamHandler that holds a single event sink and
/// provides thread-safe helpers for dispatching data to Dart.
class DeviceStreamHandler: NSObject, FlutterStreamHandler {

    let channelId: String
    private var sink: FlutterEventSink?

    init(channelId: String) {
        self.channelId = channelId
    }

    func onListen(withArguments _: Any?,
                  eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        sink = events
        return nil
    }

    func onCancel(withArguments _: Any?) -> FlutterError? {
        sink = nil
        return nil
    }

    /// Dispatches `map` to the Dart event sink on the main thread.
    /// Safe to call from any thread; silently drops events when no listener is attached.
    func send(_ map: [String: Any]) {
        let captured = sink
        DispatchQueue.main.async {
            captured?(map)
        }
    }

    /// Dispatches a FlutterError to the Dart event sink on the main thread.
    func sendError(_ code: String, _ message: String) {
        let captured = sink
        DispatchQueue.main.async {
            captured?(FlutterError(code: code, message: message, details: nil))
        }
    }

    /// Dispatches a list of maps to the Dart event sink on the main thread.
    /// Safe to call from any thread; silently drops events when no listener is attached.
    func sendList(_ list: [[String: Any]]) {
        let captured = sink
        DispatchQueue.main.async {
            captured?(list)
        }
    }
}

// MARK: - DeviceBridge

class DeviceBridge: NSObject {

    // MARK: Static state (used by C callbacks which cannot capture `self`)

    /// The currently active bridge. C callbacks reach the instance through this
    /// static weak reference because device event handlers are bare C function
    /// pointers with no `void* context` parameter.
    private static weak var activeBridge: DeviceBridge?

    // MARK: Stream handlers

    let eegHandler              = DeviceStreamHandler(channelId: "neiry_kit/events/eeg")
    let psdHandler              = DeviceStreamHandler(channelId: "neiry_kit/events/psd")
    let artifactsHandler        = DeviceStreamHandler(channelId: "neiry_kit/events/eegArtifacts")
    let resistanceHandler       = DeviceStreamHandler(channelId: "neiry_kit/events/resistance")
    let batteryHandler          = DeviceStreamHandler(channelId: "neiry_kit/events/battery")
    let errorHandler            = DeviceStreamHandler(channelId: "neiry_kit/events/error")
    let connectionStatusHandler = DeviceStreamHandler(channelId: "neiry_kit/events/connectionStatus")
    let modeHandler             = DeviceStreamHandler(channelId: "neiry_kit/events/modeSwitched")

    /// Returns all (channelId, handler) pairs for EventChannel registration in the plugin.
    func allStreamHandlers() -> [(String, FlutterStreamHandler)] {
        return [
            (eegHandler.channelId,              eegHandler),
            (psdHandler.channelId,              psdHandler),
            (artifactsHandler.channelId,        artifactsHandler),
            (resistanceHandler.channelId,       resistanceHandler),
            (batteryHandler.channelId,          batteryHandler),
            (errorHandler.channelId,            errorHandler),
            (connectionStatusHandler.channelId, connectionStatusHandler),
            (modeHandler.channelId,             modeHandler),
        ]
    }

    // MARK: Instance state

    /// Native device handle obtained via `clCDeviceLocator_CreateDevice`.
    private var device: OpaquePointer?

    /// Serial number of the currently active device.
    private var serial: String?

    /// Cached `clCDevice_ChannelNames` handle. There is no release function for this
    /// type, so we cache it to avoid leaking handles on repeated calls.
    private var channelNamesHandle: OpaquePointer?

    // MARK: - Handle management

    /// Returns the stored device handle or throws if no device has been set.
    func requireDevice() throws -> OpaquePointer {
        guard let dev = device else {
            throw FlutterError(
                code: "NO_DEVICE",
                message: "No device handle — call createDevice first",
                details: nil
            )
        }
        return dev
    }

    /// Called by `NeiryKitPlugin` after `DeviceLocatorBridge.createDevice()` to
    /// hand off the native handle. Releases any existing handle that differs from
    /// the incoming one to prevent native handle leaks on repeated createDevice calls.
    func setDevice(serial newSerial: String, handle: OpaquePointer) {
        if let old = device, old != handle {
            unregisterCallbacks()
            clCDevice_Release(old)
            channelNamesHandle = nil
        }
        device = handle
        serial = newSerial
        registerCallbacks()
    }

    /// Releases the native device handle and clears all cached state.
    /// Called by `NeiryKitPlugin` during explicit disposal — NOT on disconnect.
    func release() {
        unregisterCallbacks()
        if let dev = device {
            clCDevice_Release(dev)
        }
        device = nil
        serial = nil
        channelNamesHandle = nil
    }

    deinit {
        release()
    }

    // MARK: - Callback registration

    private func registerCallbacks() {
        guard let dev = device else { return }
        DeviceBridge.activeBridge = self

        clCDevice_SetOnEEGDataEvent(dev) { _, data in
            guard let bridge = DeviceBridge.activeBridge,
                  let data = data else { return }

            var error = clCError()
            let channelCount = clCEEGTimedData_GetChannelsCount(data, &error)
            guard error.success else { return }

            error = clCError()
            let sampleCount = clCEEGTimedData_GetSamplesCount(data, &error)
            guard error.success else { return }

            error = clCError()
            let ts = clCEEGTimedData_GetTimestampMilli(data, 0, &error)
            guard error.success else { return }

            var rawValues: [[Float]] = []
            var processedValues: [[Float]] = []
            for ch in 0..<channelCount {
                var rawRow: [Float] = []
                var procRow: [Float] = []
                for s in 0..<sampleCount {
                    error = clCError()
                    let raw = clCEEGTimedData_GetRawValue(data, ch, s, &error)
                    guard error.success else { return }
                    rawRow.append(raw)

                    error = clCError()
                    let proc = clCEEGTimedData_GetProcessedValue(data, ch, s, &error)
                    guard error.success else { return }
                    procRow.append(proc)
                }
                rawValues.append(rawRow)
                processedValues.append(procRow)
            }

            let map: [String: Any] = [
                "ts":              Int64(bitPattern: ts),
                "rawValues":       rawValues,
                "processedValues": processedValues,
                "channelCount":    Int(channelCount),
                "sampleCount":     Int(sampleCount),
            ]
            bridge.eegHandler.send(map)
        }

        clCDevice_SetOnPSDDataEvent(dev) { _, data in
            guard let bridge = DeviceBridge.activeBridge,
                  let data = data else { return }

            var error = clCError()
            let ts = clCPSDData_GetTimestampMilli(data, &error)
            guard error.success else { return }

            error = clCError()
            let channelCount = clCPSDData_GetChannelsCount(data, &error)
            guard error.success else { return }

            error = clCError()
            let freqCount = clCPSDData_GetFrequenciesCount(data, &error)
            guard error.success else { return }

            var frequencies: [Double] = []
            for f in 0..<freqCount {
                error = clCError()
                let freq = clCPSDData_GetFrequency(data, f, &error)
                guard error.success else { return }
                frequencies.append(freq)
            }

            var values: [[Double]] = []
            for ch in 0..<channelCount {
                var row: [Double] = []
                for f in 0..<freqCount {
                    error = clCError()
                    let psd = clCPSDData_GetPSD(data, ch, f, &error)
                    guard error.success else { return }
                    row.append(psd)
                }
                values.append(row)
            }

            var map: [String: Any] = [
                "ts":             Int64(bitPattern: ts),
                "values":         values,
                "frequencies":    frequencies,
                "channelCount":   Int(channelCount),
                "frequencyCount": Int(freqCount),
            ]

            let bands: [(String, clCPSDData_Band)] = [
                ("delta", clCPSDData_Band_Delta),
                ("theta", clCPSDData_Band_Theta),
                ("alpha", clCPSDData_Band_Alpha),
                ("smr",   clCPSDData_Band_SMR),
                ("beta",  clCPSDData_Band_Beta),
            ]
            for (name, band) in bands {
                error = clCError()
                let lower = clCPSDData_GetBandLower(data, band, &error)
                guard error.success else { return }
                error = clCError()
                let upper = clCPSDData_GetBandUpper(data, band, &error)
                guard error.success else { return }
                map["\(name)Lower"] = lower
                map["\(name)Upper"] = upper
            }

            // Individual alpha — emit -1 sentinel when unavailable or accessor fails
            error = clCError()
            let hasAlpha = clCPSDData_HasIndividualAlpha(data, &error)
            guard error.success else { return }
            if hasAlpha {
                error = clCError()
                let lower = clCPSDData_GetIndividualAlphaLower(data, &error)
                let lowerVal: Float = error.success ? lower : -1
                error = clCError()
                let upper = clCPSDData_GetIndividualAlphaUpper(data, &error)
                let upperVal: Float = error.success ? upper : -1
                map["individualAlphaLower"] = lowerVal
                map["individualAlphaUpper"] = upperVal
            } else {
                map["individualAlphaLower"] = Float(-1)
                map["individualAlphaUpper"] = Float(-1)
            }

            // Individual beta — same pattern
            error = clCError()
            let hasBeta = clCPSDData_HasIndividualBeta(data, &error)
            guard error.success else { return }
            if hasBeta {
                error = clCError()
                let lower = clCPSDData_GetIndividualBetaLower(data, &error)
                let lowerVal: Float = error.success ? lower : -1
                error = clCError()
                let upper = clCPSDData_GetIndividualBetaUpper(data, &error)
                let upperVal: Float = error.success ? upper : -1
                map["individualBetaLower"] = lowerVal
                map["individualBetaUpper"] = upperVal
            } else {
                map["individualBetaLower"] = Float(-1)
                map["individualBetaUpper"] = Float(-1)
            }

            bridge.psdHandler.send(map)
        }

        clCDevice_SetOnEEGArtifactsEvent(dev) { _, data in
            guard let bridge = DeviceBridge.activeBridge,
                  let data = data else { return }

            var error = clCError()
            let ts = clCEEGArtifacts_GetTimestampMilli(data, &error)
            guard error.success else { return }

            error = clCError()
            let channelCount = clCEEGArtifacts_GetChannelsCount(data, &error)
            guard error.success else { return }

            var artifacts: [Int] = []
            var qualities: [Float] = []
            for ch in 0..<channelCount {
                error = clCError()
                let artifact = clCEEGArtifacts_GetArtifactByChannel(data, ch, &error)
                guard error.success else { return }
                artifacts.append(Int(artifact))

                error = clCError()
                let quality = clCEEGArtifacts_GetEEGQuality(data, ch, &error)
                guard error.success else { return }
                qualities.append(quality)
            }

            let map: [String: Any] = [
                "ts":           Int64(bitPattern: ts),
                "artifacts":    artifacts,
                "qualities":    qualities,
                "channelCount": Int(channelCount),
            ]
            bridge.artifactsHandler.send(map)
        }

        clCDevice_SetOnResistanceUpdateEvent(dev) { _, data in
            guard let bridge = DeviceBridge.activeBridge,
                  let data = data else { return }

            let count = clCResistance_GetCount(data)
            var channelNames: [String] = []
            var values: [Float] = []
            for i in 0..<count {
                if let cName = clCResistance_GetChannelName(data, i) {
                    channelNames.append(String(cString: cName))
                } else {
                    channelNames.append("")
                }
                values.append(clCResistance_GetValue(data, i))
            }

            let map: [String: Any] = [
                "channelNames": channelNames,
                "values":       values,
                "channelCount": Int(count),
            ]
            bridge.resistanceHandler.send(map)
        }

        clCDevice_SetOnBatteryChargeUpdateEvent(dev) { _, charge in
            guard let bridge = DeviceBridge.activeBridge else { return }
            bridge.batteryHandler.send(["charge": Int(charge)])
        }

        clCDevice_SetOnErrorEvent(dev) { _, msg in
            guard let bridge = DeviceBridge.activeBridge else { return }
            let message = msg.map { String(cString: $0) } ?? ""
            bridge.errorHandler.send(["message": message])
        }

        clCDevice_SetOnConnectionStatusChangedEvent(dev) { _, status in
            guard let bridge = DeviceBridge.activeBridge else { return }
            bridge.connectionStatusHandler.send(["state": Int(status.rawValue)])
        }

        clCDevice_SetOnModeSwitchedEvent(dev) { _, mode in
            guard let bridge = DeviceBridge.activeBridge else { return }
            bridge.modeHandler.send(["mode": Int(mode.rawValue)])
        }
    }

    private func unregisterCallbacks() {
        guard let dev = device else { return }
        clCDevice_SetOnEEGDataEvent(dev, nil)
        clCDevice_SetOnPSDDataEvent(dev, nil)
        clCDevice_SetOnEEGArtifactsEvent(dev, nil)
        clCDevice_SetOnResistanceUpdateEvent(dev, nil)
        clCDevice_SetOnBatteryChargeUpdateEvent(dev, nil)
        clCDevice_SetOnErrorEvent(dev, nil)
        clCDevice_SetOnConnectionStatusChangedEvent(dev, nil)
        clCDevice_SetOnModeSwitchedEvent(dev, nil)
        if DeviceBridge.activeBridge === self {
            DeviceBridge.activeBridge = nil
        }
    }

    // MARK: - Private helpers

    /// Returns the cached `clCDevice_ChannelNames` handle, fetching and caching
    /// it on first access.
    private func getOrCacheChannelNamesHandle() throws -> OpaquePointer {
        if let cached = channelNamesHandle {
            return cached
        }
        let dev = try requireDevice()
        var error = clCError()
        let handle = clCDevice_GetChannelNames(dev, &error)
        try checkCError(error)
        guard let handle = handle else {
            throw FlutterError(code: "NULL_HANDLE", message: "clCDevice_GetChannelNames returned nil", details: nil)
        }
        channelNamesHandle = handle
        return handle
    }

    // MARK: - Lifecycle methods

    func connect(_ call: FlutterMethodCall) throws {
        let dev = try requireDevice()
        let bipolarChannels = (call.arguments as? [String: Any])?["bipolarChannels"] as? Bool ?? false
        var error = clCError()
        clCDevice_Connect(dev, bipolarChannels, &error)
        try checkCError(error)
    }

    func disconnect() throws {
        let dev = try requireDevice()
        var error = clCError()
        clCDevice_Disconnect(dev, &error)
        try checkCError(error)
    }

    func start() throws {
        let dev = try requireDevice()
        var error = clCError()
        clCDevice_Start(dev, &error)
        try checkCError(error)
    }

    @discardableResult
    func stop() throws -> Bool {
        let dev = try requireDevice()
        var error = clCError()
        clCDevice_Stop(dev, &error)
        try checkCError(error)
        return true
    }

    // MARK: - Getters

    func getInfo() throws -> [String: Any] {
        let dev = try requireDevice()
        var error = clCError()
        let info = clCDevice_GetInfo(dev, &error)
        try checkCError(error)
        guard let info = info else {
            throw FlutterError(code: "NULL_INFO", message: "clCDevice_GetInfo returned nil", details: nil)
        }
        let serial = String(cString: clCDeviceInfo_GetSerial(info))
        let name   = String(cString: clCDeviceInfo_GetName(info))
        let type   = Int(clCDeviceInfo_GetType(info).rawValue)
        return ["serial": serial, "name": name, "type": type]
    }

    func getBatteryCharge() throws -> Int {
        let dev = try requireDevice()
        var error = clCError()
        let result = clCDevice_GetBatteryCharge(dev, &error)
        try checkCError(error)
        return Int(result)
    }

    func getMode() -> Int {
        guard let dev = device else { return -1 }
        let result = clCDevice_GetMode(dev)
        return Int(result.rawValue)
    }

    func getEEGSampleRate() throws -> Float {
        let dev = try requireDevice()
        var error = clCError()
        let result = clCDevice_GetEEGSampleRate(dev, &error)
        try checkCError(error)
        return result
    }

    func getPPGSampleRate() throws -> Float {
        let dev = try requireDevice()
        var error = clCError()
        let result = clCDevice_GetPPGSampleRate(dev, &error)
        try checkCError(error)
        return result
    }

    func getMEMSSampleRate() throws -> Float {
        let dev = try requireDevice()
        var error = clCError()
        let result = clCDevice_GetMEMSSampleRate(dev, &error)
        try checkCError(error)
        return result
    }

    func getPPGIrAmplitude() throws -> Int32 {
        let dev = try requireDevice()
        var error = clCError()
        let result = clCDevice_GetPPGIrAmplitude(dev, &error)
        try checkCError(error)
        return result
    }

    func getPPGRedAmplitude() throws -> Int32 {
        let dev = try requireDevice()
        var error = clCError()
        let result = clCDevice_GetPPGRedAmplitude(dev, &error)
        try checkCError(error)
        return result
    }

    func getFirmwareVersion() throws -> String {
        let dev = try requireDevice()
        var error = clCError()
        let result = clCDevice_GetFirmwareVersion(dev, &error)
        try checkCError(error)
        guard let result = result else {
            throw FlutterError(code: "NULL_RESULT", message: "clCDevice_GetFirmwareVersion returned nil", details: nil)
        }
        return String(cString: result)
    }

    // MARK: - Channel name accessors

    func getChannelNames() throws -> [String] {
        let handle = try getOrCacheChannelNamesHandle()
        var countError = clCError()
        let count = clCDevice_ChannelNames_GetChannelsCount(handle, &countError)
        try checkCError(countError)
        var names: [String] = []
        for i in 0..<count {
            var nameError = clCError()
            let cName = clCDevice_ChannelNames_GetChannelNameByIndex(handle, i, &nameError)
            try checkCError(nameError)
            if let cName = cName {
                names.append(String(cString: cName))
            }
        }
        return names
    }

    func getChannelsCount() throws -> Int {
        let handle = try getOrCacheChannelNamesHandle()
        var error = clCError()
        let count = clCDevice_ChannelNames_GetChannelsCount(handle, &error)
        try checkCError(error)
        return Int(count)
    }

    func getChannelIndexByName(_ call: FlutterMethodCall) throws -> Int {
        guard let args = call.arguments as? [String: Any],
              let channelName = args["channelName"] as? String else {
            throw FlutterError(code: "INVALID_ARGS", message: "Missing 'channelName'", details: nil)
        }
        let handle = try getOrCacheChannelNamesHandle()
        var error = clCError()
        let result = clCDevice_ChannelNames_GetChannelIndexByName(handle, channelName, &error)
        try checkCError(error)
        return Int(result)
    }

    func getChannelNameByIndex(_ call: FlutterMethodCall) throws -> String {
        guard let args = call.arguments as? [String: Any],
              let index = args["index"] as? Int else {
            throw FlutterError(code: "INVALID_ARGS", message: "Missing 'index'", details: nil)
        }
        let handle = try getOrCacheChannelNamesHandle()
        var error = clCError()
        let cName = clCDevice_ChannelNames_GetChannelNameByIndex(handle, Int32(index), &error)
        try checkCError(error)
        guard let cName = cName else {
            throw FlutterError(code: "NULL_RESULT", message: "Channel name at index \(index) is nil", details: nil)
        }
        return String(cString: cName)
    }
}
