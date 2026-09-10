import Foundation

enum DictationActivationMode: String, CaseIterable, Identifiable {
  case holdToSpeak
  case pressToToggle

  static let storageKey = "dictationActivationMode"
  static let defaultMode = DictationActivationMode.holdToSpeak

  var id: String { rawValue }

  var title: String {
    switch self {
    case .holdToSpeak: "Hold to Speak"
    case .pressToToggle: "Press to Start/Stop"
    }
  }

  var stopAction: String {
    switch self {
    case .holdToSpeak: "Release Right Option"
    case .pressToToggle: "Press Right Option again"
    }
  }

  static var selected: DictationActivationMode {
    let rawValue = UserDefaults.standard.string(forKey: storageKey)
    return rawValue.flatMap(DictationActivationMode.init(rawValue:)) ?? defaultMode
  }
}

enum PhysicalModifierKey: String, Codable, Sendable, CaseIterable {
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

struct ModifierMask: OptionSet, Codable, Hashable, Sendable {
  let rawValue: UInt64

  static let command = Self(rawValue: 1 << 0)
  static let option = Self(rawValue: 1 << 1)
  static let control = Self(rawValue: 1 << 2)
  static let shift = Self(rawValue: 1 << 3)
  static let function = Self(rawValue: 1 << 4)
}

enum WakeBinding: Codable, Sendable, Equatable {
  case modifierOnly(PhysicalModifierKey)
  case chord(keyCode: UInt16, modifiers: ModifierMask)

  static let defaultBinding: Self = .modifierOnly(.rightOption)
}

enum HotKeyEvent: Sendable, Equatable {
  case pressed(monotonicTime: ContinuousClock.Instant)
  case released(monotonicTime: ContinuousClock.Instant)
  case cancelRequested
  case tapDisabled
  case physicalStateInvalidated
}

protocol GlobalHotKeyMonitoring: Sendable {
  func events(for binding: WakeBinding) async throws -> AsyncStream<HotKeyEvent>
  func stop() async
}
