import Flutter
import UIKit

// MARK: - EmotionsBridge

class EmotionsBridge: NSObject {

    // MARK: Static state (used by C callbacks which cannot capture `self`)

    /// The currently active bridge. C callbacks reach the instance through this
    /// static weak reference because `clCEmotions_Set*Event` callbacks have no
    /// `void* context` parameter.
    private static weak var activeBridge: EmotionsBridge?

    // MARK: Stream handlers

    let emotionsStateHandler = DeviceStreamHandler(channelId: "neiry_kit/events/emotionsState")
    let emotionsErrorHandler = DeviceStreamHandler(channelId: "neiry_kit/events/emotionsError")

    /// Returns all (channelId, handler) pairs for EventChannel registration in the plugin.
    func allStreamHandlers() -> [(String, FlutterStreamHandler)] {
        return [
            (emotionsStateHandler.channelId, emotionsStateHandler),
            (emotionsErrorHandler.channelId, emotionsErrorHandler),
        ]
    }

    // MARK: Instance state

    private var emotions: OpaquePointer?

    // MARK: - Public API

    /// Creates an Emotions classifier for the given device handle.
    func create(device: OpaquePointer) throws {
        if emotions != nil { unregisterCallbacks() }
        var error = clCError()
        emotions = clCEmotions_Create(device, &error)
        try checkCError(error)
        registerCallbacks()
    }

    /// Unregisters all callbacks and releases the Emotions handle.
    /// There is no `clCEmotions_Destroy` in the SDK — disposal is callback-only.
    func dispose() {
        unregisterCallbacks()
        emotions = nil
    }

    // MARK: - Callbacks

    private func registerCallbacks() {
        guard let emotions = emotions else { return }
        EmotionsBridge.activeBridge = self

        clCEmotions_SetOnEmotionalStatesUpdateEvent(emotions) { _, data in
            guard let bridge = EmotionsBridge.activeBridge,
                  let data = data else { return }
            let state = data.pointee
            let map: [String: Any] = [
                "ts":               state.timestampMilli,
                "attention":        state.attention,
                "relaxation":       state.relaxation,
                "cognitiveLoad":    state.cognitiveLoad,
                "cognitiveControl": state.cognitiveControl,
                "selfControl":      state.selfControl,
            ]
            bridge.emotionsStateHandler.send(map)
        }

        clCEmotions_SetOnErrorEvent(emotions) { _, msg in
            guard let bridge = EmotionsBridge.activeBridge else { return }
            let message = msg.map { String(cString: $0) } ?? ""
            bridge.emotionsErrorHandler.send(["message": message])
        }
    }

    private func unregisterCallbacks() {
        guard let emotions = emotions else { return }
        clCEmotions_SetOnEmotionalStatesUpdateEvent(emotions, nil)
        clCEmotions_SetOnErrorEvent(emotions, nil)
        if EmotionsBridge.activeBridge === self {
            EmotionsBridge.activeBridge = nil
        }
    }
}
