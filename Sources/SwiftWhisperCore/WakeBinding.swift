import Foundation

public enum PhysicalModifierKey: String, Codable, Sendable, CaseIterable {
    case rightOption
    case leftOption
    case function
    case rightShift
    case leftShift
    case rightCommand
    case leftCommand
    case rightControl
    case leftControl
}

public struct ModifierMask: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static let command = Self(rawValue: 1 << 0)
    public static let option = Self(rawValue: 1 << 1)
    public static let control = Self(rawValue: 1 << 2)
    public static let shift = Self(rawValue: 1 << 3)
    public static let function = Self(rawValue: 1 << 4)
}

public enum WakeBinding: Codable, Sendable, Equatable {
    case modifierOnly(PhysicalModifierKey)
    case chord(keyCode: UInt16, modifiers: ModifierMask)

    public static let defaultBinding: Self = .modifierOnly(.rightOption)
    public static let secondaryBinding: Self = .modifierOnly(.function)
}

public enum HotKeyEvent: Sendable, Equatable {
    case pressed(monotonicTime: ContinuousClock.Instant)
    case released(monotonicTime: ContinuousClock.Instant)
    case escapePressed(monotonicTime: ContinuousClock.Instant)
    case tapDisabled
    case physicalStateInvalidated
}

public protocol GlobalHotKeyMonitoring: Sendable {
    func events(for binding: WakeBinding) async throws -> AsyncStream<HotKeyEvent>
    func stop() async
}
