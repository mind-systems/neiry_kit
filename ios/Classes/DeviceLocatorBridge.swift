import Flutter
import UIKit

// `FlutterError` inherits from NSObject, not NSError, so it does not automatically
// conform to Swift's `Error` protocol.  This retroactive conformance lets us
// `throw FlutterError(...)` from any method that declares `throws`.
extension FlutterError: @retroactive Error {}

// MARK: - C error helper

/// Converts a `clCError` to a thrown `FlutterError` when the operation failed.
/// The `error.message` field is a fixed-size C char array (`char[256]`); read it
/// via `withUnsafePointer` + `withMemoryRebound` to obtain a Swift `String`.
func checkCError(_ error: clCError) throws {
    guard error.success else {
        let message = withUnsafePointer(to: error.message) {
            $0.withMemoryRebound(to: CChar.self, capacity: 256) {
                String(cString: $0)
            }
        }
        throw FlutterError(
            code: String(error.code.rawValue),
            message: message,
            details: nil
        )
    }
}

// MARK: - DeviceLocatorBridge

class DeviceLocatorBridge: NSObject, FlutterStreamHandler {

    // MARK: Static state (used by C callbacks which cannot capture `self`)

    /// The currently active bridge. C callbacks reach the instance through this
    /// static weak reference because `clCDeviceLocator_SetOnDeviceListEvent`
    /// takes a bare C function pointer with no `void* context` parameter.
    private static weak var activeBridge: DeviceLocatorBridge?

    /// Device handles created by `createDevice`, keyed by serial number.
    /// `DeviceBridge` looks up entries here when it needs an existing handle.
    static var devices: [String: OpaquePointer] = [:]

    // MARK: Instance state

    private var locator: OpaquePointer?
    private var deviceListSink: FlutterEventSink?

    // MARK: - Lifecycle methods

    /// Creates the native `clCDeviceLocator`. Optionally writes SDK logs to `logDirectory`.
    func create(logDirectory: String?) throws {
        var error = clCError()
        if let dir = logDirectory {
            locator = clCDeviceLocator_CreateWithLogDirectory(dir, &error)
        } else {
            locator = clCDeviceLocator_Create(&error)
        }
        try checkCError(error)
    }

    /// Creates a `clCDevice` handle for `serial` and stores it in `DeviceLocatorBridge.devices`.
    /// Returns `nil` — the Dart side constructs the `Device` object locally from the serial.
    @discardableResult
    func createDevice(serial: String) throws -> Any? {
        guard let loc = locator else {
            throw FlutterError(code: "NO_LOCATOR", message: "DeviceLocator not created", details: nil)
        }
        var error = clCError()
        let device = clCDeviceLocator_CreateDevice(loc, serial, &error)
        try checkCError(error)
        if let device = device {
            DeviceLocatorBridge.devices[serial] = device
        }
        return nil
    }

    /// Switches the SDK between multi-threaded (default) and single-threaded mode.
    /// In single-threaded mode `update()` must be called periodically from the main thread.
    func setSingleThreaded(enabled: Bool) {
        clCCapsule_SetSingleThreaded(enabled)
    }

    /// Pumps pending SDK callbacks when operating in single-threaded mode.
    func update() throws {
        guard let loc = locator else {
            throw FlutterError(code: "NO_LOCATOR", message: "DeviceLocator not created", details: nil)
        }
        clCDeviceLocator_Update(loc)
    }

    /// Sets the SDK log verbosity level.
    func setLogLevel(level: Int) {
        clCCapsule_SetLogLevel(clCCapsule_LogLevel(rawValue: UInt32(level)))
    }

    /// Releases the native locator handle and clears all stored device handles.
    func dispose() {
        if let loc = locator {
            clCDeviceLocator_Destroy(loc)
            locator = nil
        }
        DeviceLocatorBridge.devices.removeAll()
        if DeviceLocatorBridge.activeBridge === self {
            DeviceLocatorBridge.activeBridge = nil
        }
    }

    deinit {
        if let loc = locator {
            clCDeviceLocator_Destroy(loc)
        }
        DeviceLocatorBridge.devices.removeAll()
    }

    // MARK: - FlutterStreamHandler

    func onListen(withArguments arguments: Any?,
                  eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        guard let loc = locator else {
            return FlutterError(code: "NO_LOCATOR", message: "DeviceLocator not created", details: nil)
        }
        guard let args = arguments as? [String: Any],
              let deviceType = args["deviceType"] as? Int,
              let searchTime = args["searchTime"] as? Int else {
            return FlutterError(
                code: "INVALID_ARGS",
                message: "Missing 'deviceType' or 'searchTime'",
                details: nil
            )
        }

        deviceListSink = events
        DeviceLocatorBridge.activeBridge = self

        // Register a non-capturing @convention(c) callback. The callback reaches
        // the bridge instance via the static `activeBridge` weak reference.
        clCDeviceLocator_SetOnDeviceListEvent(loc) { _, list, failReason in
            guard let bridge = DeviceLocatorBridge.activeBridge,
                  let sink = bridge.deviceListSink else { return }

            if failReason != clCDeviceLocator_FailReason_OK {
                let flutterError: FlutterError
                if failReason == clCDeviceLocator_FailReason_BluetoothDisabled {
                    // code "1" = NeiryErrorCode.failedToConnect → Dart: BluetoothDisabledException
                    flutterError = FlutterError(
                        code: "1",
                        message: "Bluetooth is disabled",
                        details: nil
                    )
                } else {
                    // code "255" = NeiryErrorCode.unknown
                    flutterError = FlutterError(
                        code: "255",
                        message: "Unknown error during device search",
                        details: nil
                    )
                }
                DispatchQueue.main.async {
                    sink(flutterError)
                    sink(FlutterEndOfEventStream)
                }
                return
            }

            // Build the device-info array from the list.
            var devicesArray: [[String: Any]] = []
            if let list = list {
                var countError = clCError()
                let count = clCDeviceInfoList_GetCount(list, &countError)
                if countError.success {
                    for i in 0..<count {
                        var infoError = clCError()
                        if let info = clCDeviceInfoList_GetDeviceInfo(list, i, &infoError),
                           infoError.success {
                            let serial = String(cString: clCDeviceInfo_GetSerial(info))
                            let name   = String(cString: clCDeviceInfo_GetName(info))
                            // .rawValue converts clCDeviceType C enum to Int expected by
                            // DeviceInfo.fromMap on the Dart side.
                            let type   = Int(clCDeviceInfo_GetType(info).rawValue)
                            devicesArray.append(["serial": serial, "name": name, "type": type])
                        }
                    }
                }
            }

            DispatchQueue.main.async {
                sink(devicesArray)
                sink(FlutterEndOfEventStream)
            }
        }

        // Start the BLE scan — callbacks fire asynchronously when the timeout expires.
        var requestError = clCError()
        clCDeviceLocator_RequestDevices(
            loc,
            clCDeviceType(rawValue: UInt32(deviceType)),
            Int32(searchTime),
            &requestError
        )
        if !requestError.success {
            let message = withUnsafePointer(to: requestError.message) {
                $0.withMemoryRebound(to: CChar.self, capacity: 256) {
                    String(cString: $0)
                }
            }
            let err = FlutterError(
                code: String(requestError.code.rawValue),
                message: message,
                details: nil
            )
            deviceListSink = nil
            DeviceLocatorBridge.activeBridge = nil
            events(err)
            events(FlutterEndOfEventStream)
        }

        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        deviceListSink = nil
        if DeviceLocatorBridge.activeBridge === self {
            DeviceLocatorBridge.activeBridge = nil
        }
        // Clearing deviceListSink is sufficient — pending callbacks will early-return
        // via the `guard let sink = bridge.deviceListSink` check above.
        return nil
    }
}
