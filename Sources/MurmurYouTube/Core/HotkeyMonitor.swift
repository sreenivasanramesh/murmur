import AppKit
import Carbon.HIToolbox
import Foundation

/// A dynamic representation of any keyboard key or modifier.
public struct HotkeyKeyItem: Codable, Hashable, Identifiable, Sendable {
    public var id: String { "\(keyCode)_\(name)" }
    public var keyCode: Int64
    public var name: String
    public var isModifier: Bool
    public var flagRaw: UInt64?

    public init(keyCode: Int64, name: String, isModifier: Bool, flagRaw: UInt64? = nil) {
        self.keyCode = keyCode
        self.name = name
        self.isModifier = isModifier
        self.flagRaw = flagRaw
    }

    public var displayName: String { name }

    public var flag: CGEventFlags? {
        flagRaw.map { CGEventFlags(rawValue: $0) }
    }

    // Common standard presets
    public static let rightOption = HotkeyKeyItem(keyCode: Int64(kVK_RightOption), name: "Right ⌥", isModifier: true, flagRaw: 0x40)
    public static let leftOption = HotkeyKeyItem(keyCode: Int64(kVK_Option), name: "Option", isModifier: true, flagRaw: 0x20)
    public static let control = HotkeyKeyItem(keyCode: Int64(kVK_Control), name: "Ctrl", isModifier: true, flagRaw: CGEventFlags.maskControl.rawValue)
    public static let command = HotkeyKeyItem(keyCode: Int64(kVK_Command), name: "⌘", isModifier: true, flagRaw: CGEventFlags.maskCommand.rawValue)
    public static let rightCommand = HotkeyKeyItem(keyCode: Int64(kVK_RightCommand), name: "Right ⌘", isModifier: true, flagRaw: 0x10)
    public static let shift = HotkeyKeyItem(keyCode: Int64(kVK_Shift), name: "Shift", isModifier: true, flagRaw: CGEventFlags.maskShift.rawValue)
    public static let fn = HotkeyKeyItem(keyCode: Int64(kVK_Function), name: "fn", isModifier: true, flagRaw: CGEventFlags.maskSecondaryFn.rawValue)
    public static let space = HotkeyKeyItem(keyCode: Int64(kVK_Space), name: "Space", isModifier: false)

    /// Converts an incoming key code and modifier flags to a clean HotkeyKeyItem.
    public static func from(keyCode: Int64, flags: CGEventFlags? = nil, character: String? = nil) -> HotkeyKeyItem {
        switch Int(keyCode) {
        case kVK_RightOption: return .rightOption
        case kVK_Option: return .leftOption
        case kVK_Control: return .control
        case kVK_Command: return .command
        case kVK_RightCommand: return .rightCommand
        case kVK_Shift, kVK_RightShift: return .shift
        case kVK_Function: return .fn
        case kVK_Space: return .space
        case kVK_Return: return HotkeyKeyItem(keyCode: keyCode, name: "Return", isModifier: false)
        case kVK_Tab: return HotkeyKeyItem(keyCode: keyCode, name: "Tab", isModifier: false)
        case kVK_Delete: return HotkeyKeyItem(keyCode: keyCode, name: "Delete", isModifier: false)
        case kVK_Escape: return HotkeyKeyItem(keyCode: keyCode, name: "Esc", isModifier: false)
        case kVK_LeftArrow: return HotkeyKeyItem(keyCode: keyCode, name: "←", isModifier: false)
        case kVK_RightArrow: return HotkeyKeyItem(keyCode: keyCode, name: "→", isModifier: false)
        case kVK_DownArrow: return HotkeyKeyItem(keyCode: keyCode, name: "↓", isModifier: false)
        case kVK_UpArrow: return HotkeyKeyItem(keyCode: keyCode, name: "↑", isModifier: false)
        default:
            if let char = character?.trimmingCharacters(in: .whitespacesAndNewlines), !char.isEmpty {
                return HotkeyKeyItem(keyCode: keyCode, name: char.uppercased(), isModifier: false)
            }
            return HotkeyKeyItem(keyCode: keyCode, name: "Key \(keyCode)", isModifier: false)
        }
    }
}

/// A user-configured hotkey shortcut.
public struct CustomHotkey: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var keys: [HotkeyKeyItem]

    public init(id: UUID = UUID(), keys: [HotkeyKeyItem]) {
        self.id = id
        self.keys = keys
    }

    public var displayString: String {
        keys.map { $0.displayName }.joined(separator: " + ")
    }

    public static let defaultPushToTalk = CustomHotkey(keys: [.rightOption])
    public static let defaultHandsFree = CustomHotkey(keys: [.control, .space])
}

/// Legacy PushToTalkKey enum mapped to CustomHotkey for compatibility.
public enum PushToTalkKey: String, CaseIterable, Sendable {
    case rightOption
    case fn
    case rightCommand

    public var keyCode: Int64 {
        switch self {
        case .rightOption: Int64(kVK_RightOption)
        case .fn: Int64(kVK_Function)
        case .rightCommand: Int64(kVK_RightCommand)
        }
    }

    public var displayName: String {
        switch self {
        case .rightOption: "Right ⌥"
        case .fn: "fn"
        case .rightCommand: "Right ⌘"
        }
    }

    public var asCustomHotkey: CustomHotkey {
        switch self {
        case .rightOption: CustomHotkey(keys: [.rightOption])
        case .fn: CustomHotkey(keys: [.fn])
        case .rightCommand: CustomHotkey(keys: [.rightCommand])
        }
    }
}

/// Global event tap monitor handling a single Push-to-Talk hotkey and a single Hands-free hotkey.
@MainActor
public final class HotkeyMonitor {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    public var pushToTalkHotkey: CustomHotkey = .defaultPushToTalk
    public var handsFreeHotkey: CustomHotkey = .defaultHandsFree

    public var onPushToTalkPress: (() -> Void)?
    public var onPushToTalkRelease: (() -> Void)?
    public var onHandsFreeTrigger: (() -> Void)?

    private var isPushToTalkActive = false
    private var pressedKeyCodes = Set<Int64>()
    private var lastFlags = CGEventFlags()

    public init() {}

    @discardableResult
    public func start() -> Bool {
        stop()

        let mask = (1 << CGEventType.flagsChanged.rawValue) |
                   (1 << CGEventType.keyDown.rawValue) |
                   (1 << CGEventType.keyUp.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let flags = event.flags
                let consume = MainActor.assumeIsolated {
                    monitor.handle(type: type, keyCode: keyCode, flags: flags)
                }
                return consume ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else {
            Log.hotkey.error("tapCreate failed — Accessibility permission missing?")
            return false
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        Log.hotkey.info("Listening for PTT (\(self.pushToTalkHotkey.displayString)) & Hands-Free (\(self.handsFreeHotkey.displayString))")
        return true
    }

    public func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        isPushToTalkActive = false
        pressedKeyCodes.removeAll()
        lastFlags = CGEventFlags()
    }

    // MARK: - Event Dispatch

    private func handle(type: CGEventType, keyCode: Int64, flags: CGEventFlags) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }

        switch type {
        case .keyDown:
            pressedKeyCodes.insert(keyCode)
        case .keyUp:
            pressedKeyCodes.remove(keyCode)
        default:
            break
        }

        // 1. Check Hands-Free Trigger (press once to start, press again to stop)
        let isHfCandidate = handsFreeHotkey.keys.contains { $0.keyCode == keyCode }
        if isHfCandidate && (type == .keyDown || (type == .flagsChanged && handsFreeHotkey.keys.allSatisfy { $0.isModifier })) {
            if isHeld(hotkey: handsFreeHotkey, flags: flags) {
                onHandsFreeTrigger?()
                lastFlags = flags
                return shouldConsume(hotkey: handsFreeHotkey)
            }
        }

        // 2. Check Push-to-Talk (hold down to dictate, release to finish)
        if isPushToTalkActive {
            if !isHeld(hotkey: pushToTalkHotkey, flags: flags) {
                isPushToTalkActive = false
                onPushToTalkRelease?()
                lastFlags = flags
                return shouldConsume(hotkey: pushToTalkHotkey)
            }
        } else {
            let isPttCandidate = pushToTalkHotkey.keys.contains { $0.keyCode == keyCode }
            if isPttCandidate && isHeld(hotkey: pushToTalkHotkey, flags: flags) {
                isPushToTalkActive = true
                onPushToTalkPress?()
                lastFlags = flags
                return shouldConsume(hotkey: pushToTalkHotkey)
            }
        }

        lastFlags = flags
        return false
    }

    private func isHeld(hotkey: CustomHotkey, flags: CGEventFlags) -> Bool {
        guard !hotkey.keys.isEmpty else { return false }
        for key in hotkey.keys {
            if let flag = key.flag {
                if !flags.contains(flag) { return false }
            } else {
                if !pressedKeyCodes.contains(key.keyCode) { return false }
            }
        }
        return true
    }

    private func shouldConsume(hotkey: CustomHotkey) -> Bool {
        if hotkey.keys.count == 1 {
            if hotkey.keys[0].keyCode == Int64(kVK_Function) { return false }
            if hotkey.keys[0].keyCode == Int64(kVK_Space) { return false }
        }
        return true
    }
}
