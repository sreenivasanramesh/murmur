import Carbon.HIToolbox
import Foundation
import Observation
import ServiceManagement

/// Which speech engine transcribes an utterance.
enum SpeechEngineChoice: String, CaseIterable, Sendable {
    case apple
    case parakeet
    case parakeetStreaming

    var displayName: String {
        switch self {
        case .apple: "Apple (streaming)"
        case .parakeet: "Parakeet (batch)"
        case .parakeetStreaming: "Parakeet (streaming · experimental)"
        }
    }

    var shortName: String {
        switch self {
        case .apple: "Apple"
        case .parakeet: "Parakeet"
        case .parakeetStreaming: "Parakeet Stream"
        }
    }

    /// Apple and Parakeet streaming show text while you talk; Parakeet batch only resolves on release.
    var showsLiveText: Bool { self == .apple || self == .parakeetStreaming }

    var requiresParakeetModel: Bool { self == .parakeet || self == .parakeetStreaming }
}

@MainActor
@Observable
final class Settings {
    static let shared = Settings()

    var pushToTalkHotkey: CustomHotkey {
        didSet {
            if let data = try? JSONEncoder().encode(pushToTalkHotkey) {
                defaults.set(data, forKey: Keys.pushToTalkHotkey)
            }
        }
    }

    var handsFreeHotkey: CustomHotkey {
        didSet {
            if let data = try? JSONEncoder().encode(handsFreeHotkey) {
                defaults.set(data, forKey: Keys.handsFreeHotkey)
            }
        }
    }

    var pushToTalkKey: PushToTalkKey {
        get {
            if let firstKey = pushToTalkHotkey.keys.first {
                switch firstKey.keyCode {
                case Int64(kVK_RightOption): return .rightOption
                case Int64(kVK_Function): return .fn
                case Int64(kVK_RightCommand): return .rightCommand
                default: return .rightOption
                }
            }
            return .rightOption
        }
        set {
            pushToTalkHotkey = newValue.asCustomHotkey
        }
    }

    var engine: SpeechEngineChoice {
        didSet { defaults.set(engine.rawValue, forKey: Keys.engine) }
    }

    /// Run the cleanup pass before injecting. Off = raw engine output.
    var cleanupEnabled: Bool {
        didSet { defaults.set(cleanupEnabled, forKey: Keys.cleanupEnabled) }
    }

    /// Use the on-device LLM for cleanup instead of the deterministic rule pass.
    var smartCleanup: Bool {
        didSet { defaults.set(smartCleanup, forKey: Keys.smartCleanup) }
    }

    /// Play a short tick when capture starts and stops.
    var soundEnabled: Bool {
        didSet { defaults.set(soundEnabled, forKey: Keys.soundEnabled) }
    }

    /// User-selected primary microphone UID. nil = system default.
    var selectedMicrophoneUID: String? {
        didSet { defaults.set(selectedMicrophoneUID, forKey: Keys.selectedMicrophoneUID) }
    }

    /// Dedicated microphone used automatically when MacBook lid is closed. nil = none/disabled.
    var clamshellMicrophoneUID: String? {
        didSet { defaults.set(clamshellMicrophoneUID, forKey: Keys.clamshellMicrophoneUID) }
    }

    /// Automatically launches Murmur in the background when the user logs in.
    var launchAtLogin: Bool {
        get {
            if #available(macOS 13.0, *) {
                return SMAppService.mainApp.status == .enabled
            } else {
                return defaults.bool(forKey: Keys.launchAtLogin)
            }
        }
        set {
            if #available(macOS 13.0, *) {
                do {
                    if newValue {
                        if SMAppService.mainApp.status != .enabled {
                            try SMAppService.mainApp.register()
                        }
                    } else {
                        if SMAppService.mainApp.status == .enabled {
                            try SMAppService.mainApp.unregister()
                        }
                    }
                } catch {
                    Log.app.error("Failed to update launch at login: \(error.localizedDescription)")
                }
            }
            defaults.set(newValue, forKey: Keys.launchAtLogin)
        }
    }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let pushToTalkHotkey = "pushToTalkHotkey"
        static let handsFreeHotkey = "handsFreeHotkey"
        static let pushToTalkKey = "pushToTalkKey"
        static let cleanupEnabled = "cleanupEnabled"
        static let soundEnabled = "soundEnabled"
        static let engine = "engine"
        static let smartCleanup = "smartCleanup"
        static let selectedMicrophoneUID = "selectedMicrophoneUID"
        static let clamshellMicrophoneUID = "clamshellMicrophoneUID"
        static let launchAtLogin = "launchAtLogin"
    }

    private init() {
        if let data = defaults.data(forKey: Keys.pushToTalkHotkey),
           let decoded = try? JSONDecoder().decode(CustomHotkey.self, from: data) {
            pushToTalkHotkey = decoded
        } else {
            let legacyRaw = defaults.string(forKey: Keys.pushToTalkKey) ?? PushToTalkKey.rightOption.rawValue
            let legacyKey = PushToTalkKey(rawValue: legacyRaw) ?? .rightOption
            pushToTalkHotkey = legacyKey.asCustomHotkey
        }

        if let data = defaults.data(forKey: Keys.handsFreeHotkey),
           let decoded = try? JSONDecoder().decode(CustomHotkey.self, from: data) {
            handsFreeHotkey = decoded
        } else {
            handsFreeHotkey = .defaultHandsFree
        }

        // Apple by default: no download, no dependency, live text while speaking.
        engine = SpeechEngineChoice(rawValue: defaults.string(forKey: Keys.engine) ?? "") ?? .apple
        cleanupEnabled = defaults.object(forKey: Keys.cleanupEnabled) as? Bool ?? true
        smartCleanup = defaults.object(forKey: Keys.smartCleanup) as? Bool ?? false
        soundEnabled = defaults.object(forKey: Keys.soundEnabled) as? Bool ?? true
        selectedMicrophoneUID = defaults.string(forKey: Keys.selectedMicrophoneUID)
        clamshellMicrophoneUID = defaults.string(forKey: Keys.clamshellMicrophoneUID)
    }
}
