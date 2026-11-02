import Foundation

#if os(macOS)
import AppKit
#endif

#if os(iOS)
import UIKit
#endif

#if canImport(SwiftUI)
import SwiftUI
#endif

@MainActor
final class KeyboardInputMonitor {
    static let shared = KeyboardInputMonitor()

    /// Return `true` to consume the event.
    var onKeyDown: ((KeyBinding) -> Bool)?

    #if os(macOS)
    private var monitor: Any?
    #endif

    private init() {}

    func start() {
        #if os(macOS)
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.isARepeat { return event }
            if Self.isTextInputFocused { return event }
            guard let binding = KeyBinding(nsEvent: event) else { return event }
            if Self.shouldNeverConsume(binding) { return event }
            if self.onKeyDown?(binding) == true {
                return nil
            }
            return event
        }
        #endif
    }

    func stop() {
        #if os(macOS)
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        #endif
    }

    #if os(macOS)
    private static var isTextInputFocused: Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        if responder is NSTextView || responder is NSTextField || responder is NSText {
            return true
        }
        return responder.className.contains("Text")
    }

    private static func shouldNeverConsume(_ binding: KeyBinding) -> Bool {
        guard binding.command else { return false }
        let character = binding.character.lowercased()
        return character == "q" || character == "w" || character == ","
    }
    #endif
}

extension KeyBinding {
    #if os(macOS)
    init?(nsEvent event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let command = flags.contains(.command)
        let shift = flags.contains(.shift)
        let option = flags.contains(.option)
        let control = flags.contains(.control)
        let character = event.charactersIgnoringModifiers ?? ""
        let keyName = Self.macKeyName(keyCode: event.keyCode, character: character)
        guard !keyName.isEmpty else { return nil }

        self.init(
            keyCode: event.keyCode,
            character: character,
            keyName: keyName,
            command: command,
            shift: shift,
            option: option,
            control: control
        )
    }

    private static func macKeyName(keyCode: UInt16, character: String) -> String {
        switch keyCode {
        case 36: return "Return"
        case 48: return "Tab"
        case 49: return "Space"
        case 51: return "Delete"
        case 53: return "Escape"
        case 117: return "Forward Delete"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        default: break
        }

        if character == " " { return "Space" }
        if character == "\u{1b}" { return "Escape" }
        if character.count == 1 {
            return character.uppercased()
        }
        return character
    }
    #endif

    #if os(iOS)
    init?(keyPress: KeyPress) {
        let modifiers = keyPress.modifiers
        let command = modifiers.contains(.command)
        let shift = modifiers.contains(.shift)
        let option = modifiers.contains(.option)
        let control = modifiers.contains(.control)
        let character = keyPress.characters
        let keyName = Self.iOSKeyName(keyPress: keyPress)
        guard !keyName.isEmpty else { return nil }

        self.init(
            keyCode: nil,
            character: character,
            keyName: keyName,
            command: command,
            shift: shift,
            option: option,
            control: control
        )
    }

    private static func iOSKeyName(keyPress: KeyPress) -> String {
        switch keyPress.key {
        case .space: return "Space"
        case .return: return "Return"
        case .tab: return "Tab"
        case .escape: return "Escape"
        case .delete: return "Delete"
        case .deleteForward: return "Forward Delete"
        case .leftArrow: return "←"
        case .rightArrow: return "→"
        case .downArrow: return "↓"
        case .upArrow: return "↑"
        case .home: return "Home"
        case .end: return "End"
        case .pageUp: return "Page Up"
        case .pageDown: return "Page Down"
        default: break
        }

        let character = keyPress.characters
        if character == " " { return "Space" }
        if character.count == 1 {
            return character.uppercased()
        }
        return character
    }
    #endif
}
