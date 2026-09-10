import Foundation

enum NotchAnimationStyle: String, CaseIterable, Identifiable {
  case voiceWave
  case particleOrbit
  case auroraPulse

  static let storageKey = "notchAnimationStyle"
  static let defaultStyle = NotchAnimationStyle.voiceWave

  var id: String { rawValue }

  var title: String {
    switch self {
    case .voiceWave: "Voice Wave"
    case .particleOrbit: "Glowing Sphere"
    case .auroraPulse: "Aurora Pulse"
    }
  }

  var detail: String {
    switch self {
    case .voiceWave: "Audio bars react directly to your voice."
    case .particleOrbit: "A dreamy energy sphere blooms with your voice."
    case .auroraPulse: "Liquid color blooms and breathes with your voice."
    }
  }

  var systemImage: String {
    switch self {
    case .voiceWave: "waveform"
    case .particleOrbit: "circle.fill"
    case .auroraPulse: "sparkles"
    }
  }
}
