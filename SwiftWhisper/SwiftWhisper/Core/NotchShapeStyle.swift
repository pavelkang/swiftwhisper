import Foundation

enum NotchShapeStyle: String, CaseIterable, Identifiable {
  case rectangle
  case halfCircle
  case splash

  static let storageKey = "notchShapeStyle"
  static let defaultStyle = NotchShapeStyle.rectangle

  var id: String { rawValue }

  var title: String {
    switch self {
    case .rectangle: "Rectangle"
    case .halfCircle: "Half Circle"
    case .splash: "Splash"
    }
  }

  var detail: String {
    switch self {
    case .rectangle: "The classic compact notch."
    case .halfCircle: "A smooth curved dome."
    case .splash: "A smooth milk-splash silhouette."
    }
  }

  var systemImage: String {
    switch self {
    case .rectangle: "rectangle.roundedtop"
    case .halfCircle: "circle.bottomhalf.filled"
    case .splash: "drop.fill"
    }
  }
}
