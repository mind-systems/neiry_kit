import Flutter
import UIKit

// MARK: - DeviceBridge

class DeviceBridge: NSObject {

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
    private func requireDevice() throws -> OpaquePointer {
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
            clCDevice_Release(old)
            channelNamesHandle = nil
        }
        device = handle
        serial = newSerial
    }

    /// Releases the native device handle and clears all cached state.
    /// Called by `NeiryKitPlugin` during explicit disposal — NOT on disconnect.
    func release() {
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
